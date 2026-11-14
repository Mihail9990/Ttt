"""Behavioral checks: camera stability, interpolation, timing and export failures."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import motionforge as mf


class EngineTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        rng = np.random.default_rng(7)
        self.rgb = rng.integers(40, 210, (180, 320, 3), dtype=np.uint8)
        Image.fromarray(self.rgb).save(self.root / "photo.png")

    def tearDown(self):
        self.temporary.cleanup()

    def test_invalid_resolution_is_rejected_before_rendering(self):
        for width, height in [(321, 180), (4096, 2160), (1920, 1920)]:
            with self.assertRaises(mf.EngineError):
                mf.validate_video(width, height, 24)

    def test_nan_and_infinity_are_rejected(self):
        for value in [float("nan"), float("inf"), -.1]:
            with self.assertRaises(mf.EngineError):
                mf.number(value, "seconds", 0, 100)

    def test_missing_image_has_actionable_error(self):
        with self.assertRaisesRegex(mf.EngineError, "Image not found"):
            mf.load_rgb(self.root / "missing.png")

    def test_still_camera_preserves_image_exactly(self):
        scene = mf.Scene({"image": "photo.png", "depth": "flat", "camera": "still"},
                         self.root, 320, 180, None)
        self.assertTrue(np.array_equal(self.rgb, scene.render(.7)))

    def test_loop_returns_to_same_camera_pose(self):
        scene = mf.Scene({"image": "photo.png", "depth": "flat", "camera": "loop"},
                         self.root, 320, 180, None)
        self.assertTrue(np.array_equal(scene.render(0), scene.render(1)))
        self.assertGreater(np.abs(scene.render(0).astype(float) - scene.render(.25)).mean(), 5)

    def test_keyframe_flow_preserves_endpoints_and_translates_texture(self):
        # A globally translated textured image has a known intermediate position.
        yy, xx = np.mgrid[:128, :192]
        rng = np.random.default_rng(13)
        source = rng.integers(20, 235, (128, 192, 3), dtype=np.uint8)
        source = cv2.GaussianBlur(source, (5, 5), 0)
        cv2.circle(source, (72, 64), 18, (240, 40, 20), -1)
        shifted = cv2.warpAffine(source, np.float32([[1, 0, 12], [0, 1, 0]]), (192, 128),
                                 borderMode=cv2.BORDER_REFLECT)
        expected = cv2.warpAffine(source, np.float32([[1, 0, 6], [0, 1, 0]]), (192, 128),
                                  borderMode=cv2.BORDER_REFLECT)
        pair = mf.KeyframePair(source, shifted)
        self.assertTrue(np.array_equal(pair.render(0), source))
        self.assertTrue(np.array_equal(pair.render(1), shifted))
        middle = pair.render(.5)
        error = np.abs(middle[20:-20, 25:-25].astype(float) - expected[20:-20, 25:-25]).mean()
        self.assertLess(error, 6, f"The interpolated translation was inaccurate: MAE {error}")

    def test_crossfade_timeline_has_exact_duration(self):
        project = {"width": 160, "height": 90, "fps": 12, "transition": .25,
                   "shots": [{"image": "photo.png", "depth": "flat", "seconds": 1,
                              "camera": "push"},
                             {"image": "photo.png", "depth": "flat", "seconds": 1,
                              "camera": "rise"},
                             {"image": "photo.png", "depth": "flat", "seconds": 1,
                              "camera": "drift"}]}
        output = self.root / "timeline.mp4"
        with contextlib.redirect_stdout(io.StringIO()):
            result = mf.render_project(project, output, self.root, threads=2)
        self.assertEqual(result["frames"], 30)  # 36 minus two 3-frame overlaps
        self.assertEqual(result["duration_seconds"], 2.5)
        capture = cv2.VideoCapture(str(output))
        decoded = 0
        while True:
            ok, frame = capture.read()
            if not ok:
                break
            decoded += 1
            self.assertEqual(frame.shape, (90, 160, 3))
            self.assertGreater(float(frame.mean()), 20)
        capture.release()
        self.assertEqual(decoded, 30)
        self.assertTrue(output.with_suffix(".report.json").is_file())

    def test_failed_later_shot_leaves_no_partial_export(self):
        project = {"width": 160, "height": 90, "fps": 12,
                   "shots": [{"image": "photo.png", "depth": "flat", "seconds": .5},
                             {"image": "missing.png", "depth": "flat", "seconds": .5}]}
        output = self.root / "failed.mp4"
        with self.assertRaises(mf.EngineError):
            mf.render_project(project, output, self.root, threads=2)
        self.assertFalse(output.exists())
        self.assertEqual(list(self.root.glob("*.partial.mp4")), [])

    def test_morph_export_is_decodable_with_expected_frame_count(self):
        shifted = np.roll(self.rgb, 4, axis=1)
        Image.fromarray(shifted).save(self.root / "next.png")
        output = self.root / "morph.mp4"
        with contextlib.redirect_stdout(io.StringIO()):
            report = mf.render_keyframes([self.root / "photo.png", self.root / "next.png"],
                                         output, seconds=.5, width=160, height=90, fps=12, threads=2)
        self.assertEqual(report["frames"], 6)
        capture = cv2.VideoCapture(str(output))
        self.assertEqual(int(capture.get(cv2.CAP_PROP_FRAME_COUNT)), 6)
        self.assertTrue(capture.read()[0])
        capture.release()

    def test_neural_depth_is_nonconstant_and_cached(self):
        if not mf.MODEL.exists():
            self.skipTest("Download model with motionforge.py setup to run the neural check")
        rgb = mf.fit_cover(mf.load_rgb(mf.ROOT / "assets/forest_path.jpg"), 320, 180)
        estimator = mf.DepthEstimator(threads=2, input_size=280, cache=self.root / "cache")
        depth = estimator.predict(rgb)
        self.assertEqual(depth.shape, (180, 320))
        self.assertTrue(np.isfinite(depth).all())
        self.assertGreater(float(depth.std()), .08)
        cached = estimator.predict(rgb)
        self.assertTrue(np.array_equal(depth, cached))
        self.assertEqual(estimator.inferences, 1)
        self.assertEqual(estimator.cache_hits, 1)


if __name__ == "__main__":
    unittest.main()
