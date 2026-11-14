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
import motionforge as core
import studio


class StudioTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        atlas = np.zeros((129, 259, 4), np.uint8)
        # Two identical shapes at different positions, with exact known geometry.
        cv2.circle(atlas, (50, 75), 22, (240, 35, 20, 255), -1)
        cv2.circle(atlas, (195, 75), 22, (240, 35, 20, 255), -1)
        Image.fromarray(atlas).save(self.root / "atlas.png")
        Image.new("RGB", (320, 180), (35, 50, 65)).save(self.root / "background.png")

    def tearDown(self):
        self.temp.cleanup()

    def test_odd_sized_atlas_unpacks_without_losing_a_pose(self):
        frames = studio.unpack_atlas(self.root / "atlas.png", 2, 1, size=128)
        self.assertEqual(len(frames), 2)
        self.assertEqual(frames[0].shape, (128, 128, 4))
        for frame in frames:
            self.assertGreater(int((frame[..., 3] > 128).sum()), 100)
            ys, _ = np.where(frame[..., 3] > 128)
            self.assertLessEqual(abs(int(ys.max()) - 115), 2)

    def test_opaque_atlas_is_rejected(self):
        with self.assertRaisesRegex(core.EngineError, "transparent"):
            studio.unpack_atlas(self.root / "background.png", 1, 1)

    def test_flow_preserves_rgba_endpoints_and_transparent_pixels(self):
        first = np.zeros((128, 128, 4), np.uint8)
        cv2.rectangle(first, (35, 45), (60, 85), (250, 90, 30, 255), -1)
        second = cv2.warpAffine(first, np.float32([[1, 0, 12], [0, 1, 0]]), (128, 128))
        flow = studio.AlphaFlow(first, second)
        self.assertTrue(np.array_equal(flow.render(0), studio.premultiply(first)))
        self.assertTrue(np.array_equal(flow.render(1), studio.premultiply(second)))
        middle = flow.render(.5)
        self.assertTrue(np.isfinite(middle).all())
        self.assertTrue((middle[..., :3] <= middle[..., 3:4] + 1e-6).all())
        ys, xs = np.where(middle[..., 3] > .8)
        self.assertLess(abs(float(xs.mean()) - 53.5), 2)
        self.assertEqual(float(middle[0, 0, 3]), 0)

    def test_linear_trajectory_and_inherited_properties(self):
        track = studio.Track({"atlas": "atlas.png", "columns": 2, "rows": 1,
                              "keys": [{"time": 0, "x": .1, "y": .8, "height": .4},
                                       {"time": 2, "x": .9}]}, self.root, 2)
        center = studio.transform_at(track.keys, 1)
        self.assertAlmostEqual(center["x"], .5)
        self.assertEqual(center["y"], .8)
        self.assertEqual(center["height"], .4)

    def test_duplicate_key_times_are_rejected(self):
        with self.assertRaisesRegex(core.EngineError, "strictly increase"):
            studio.Track({"atlas": "atlas.png", "columns": 2, "rows": 1,
                          "keys": [{"time": 0}, {"time": 0}]}, self.root, 2)

    def test_pose_cache_is_bounded(self):
        sequence = studio.PoseSequence({"atlas": "atlas.png", "columns": 2, "rows": 1,
                                       "work_size": 128, "pose_fps": 8}, self.root)
        for seconds in np.linspace(0, 3, 30):
            pose = sequence.sample(seconds)
            self.assertEqual(pose.shape, (128, 128, 4))
        self.assertLessEqual(len(sequence.cache), 4)

    def test_render_moves_subject_over_static_background(self):
        project = {"width": 320, "height": 180, "fps": 12, "seconds": 1,
                   "background": {"image": "background.png", "depth": "flat", "camera": "still"},
                   "tracks": [{"atlas": "atlas.png", "columns": 2, "rows": 1,
                               "work_size": 128, "shadow": False,
                               "keys": [{"time": 0, "x": .2, "y": .8, "height": .4},
                                        {"time": 1, "x": .8}]}]}
        path = self.root / "project.json"
        path.write_text(json.dumps(project))
        video = self.root / "movie.mp4"
        gif = self.root / "preview.gif"
        with contextlib.redirect_stdout(io.StringIO()):
            report = studio.render(path, video, gif, threads=2)
        self.assertEqual(report["frames"], 12)
        self.assertEqual(report["pose_counts"], [2])
        self.assertFalse(report["local_video_diffusion_model"])
        cap = cv2.VideoCapture(str(video))
        positions = []
        corners = []
        while True:
            ok, image = cap.read()
            if not ok:
                break
            b, g, r = cv2.split(image)
            ys, xs = np.where((r.astype(float) > g + 50.) & (r > 150))
            self.assertGreater(len(xs), 20)
            positions.append(float(xs.mean()))
            corners.append(image[5, 5].astype(float))
        cap.release()
        self.assertEqual(len(positions), 12)
        self.assertGreater(positions[-1] - positions[0], 150)
        self.assertLess(np.ptp(corners, axis=0).max(), 5)
        with Image.open(gif) as preview:
            self.assertGreater(preview.n_frames, 1)

    def test_new_job_is_explicitly_waiting_for_generated_assets(self):
        directory = self.root / "new_scene"
        with contextlib.redirect_stdout(io.StringIO()):
            studio.new_job(directory, "Котёнок идёт по тропинке")
        request = json.loads((directory / "asset_requests.json").read_text())
        self.assertEqual(request["status"], "awaiting_generated_assets")
        self.assertEqual(len(request["requests"]), 2)
        self.assertTrue((directory / "project.json").exists())
        with self.assertRaises(FileExistsError):
            studio.new_job(directory, "must not overwrite")

    def test_real_generated_atlas_contains_sixteen_distinct_poses(self):
        path = studio.ROOT / "assets/kitten_walk_atlas.webp"
        if not path.exists():
            path = studio.ROOT / "assets/kitten_walk_atlas.png"
        frames = studio.unpack_atlas(path, 4, 4, size=160)
        self.assertEqual(len(frames), 16)
        self.assertTrue(all((frame[..., 3] > 128).mean() > .1 for frame in frames))
        self.assertGreater(np.abs(frames[0].astype(float) - frames[7]).mean(), 2)


if __name__ == "__main__":
    unittest.main()
