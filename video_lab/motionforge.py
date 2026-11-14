#!/usr/bin/env python3
"""MotionForge CPU: image-conditioned 2.5D animation, streamed to MP4.

The neural network estimates relative depth. Camera motion, region effects and
keyframe interpolation are deterministic image transformations, not a trained
video diffusion model. See README_RU.md for limitations and examples.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
import uuid

import cv2
import numpy as np
from PIL import Image, ImageOps

VERSION = "0.1.0"
ROOT = Path(__file__).resolve().parent
MODEL = ROOT / "models" / "depth_anything_v2_small_int8.onnx"
MODEL_SHA256 = "fcf51f1b230362b28690bb9d1809bf0431f29cad20534e3f589bd7285547f20d"
MODEL_REVISION = "4472b7362082ad9968fee890ca0f1e5aca36b93d"
MODEL_URL = ("https://huggingface.co/onnx-community/depth-anything-v2-small/resolve/"
             + MODEL_REVISION + "/onnx/model_quantized.onnx")
CAMERAS = ("drift", "push", "rise", "orbit", "loop", "still")


class EngineError(Exception):
    """A useful error that can be displayed without a Python traceback."""


def log(message):
    print(message, file=sys.stderr, flush=True)


def file_hash(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def setup_model(path=MODEL):
    path = Path(path)
    if path.is_file() and file_hash(path) == MODEL_SHA256:
        return path
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".download")
    log("Downloading the 27.3 MB depth model (one-time setup)...")
    try:
        with urllib.request.urlopen(MODEL_URL, timeout=60) as source, temporary.open("wb") as target:
            shutil.copyfileobj(source, target, length=1024 * 1024)
        if file_hash(temporary) != MODEL_SHA256:
            raise EngineError("Model checksum mismatch. Remove the download and run setup again.")
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)
    return path


def smoothstep(p):
    p = float(np.clip(p, 0, 1))
    return p * p * (3 - 2 * p)


def number(value, name, minimum, maximum):
    if isinstance(value, bool):
        raise EngineError(f"{name} must be a number.")
    try:
        result = float(value)
    except (ValueError, TypeError):
        raise EngineError(f"{name} must be a number.") from None
    if not math.isfinite(result) or not minimum <= result <= maximum:
        raise EngineError(f"{name} must be between {minimum} and {maximum}.")
    return result


def validate_video(width, height, fps):
    width = number(width, "width", 64, 1920)
    height = number(height, "height", 64, 1920)
    fps = number(fps, "fps", 1, 60)
    if width % 2 or height % 2 or fps != int(fps):
        raise EngineError("Use even pixel dimensions and an integer frame rate.")
    if width * height > 1920 * 1080:
        raise EngineError("This CPU engine limits output to 2,073,600 pixels per frame.")
    return int(width), int(height), int(fps)


def resolve_path(value, base):
    if not isinstance(value, str) or not value.strip():
        raise EngineError("An image, depth map, mask or audio path is missing.")
    candidate = Path(value).expanduser()
    return candidate.resolve() if candidate.is_absolute() else (base / candidate).resolve()


def load_rgb(path):
    path = Path(path)
    if not path.is_file():
        raise EngineError(f"Image not found: {path}")
    try:
        with Image.open(path) as image:
            image = ImageOps.exif_transpose(image)
            if "A" in image.getbands() or "transparency" in image.info:
                rgba = image.convert("RGBA")
                background = Image.new("RGBA", rgba.size, (20, 24, 30, 255))
                image = Image.alpha_composite(background, rgba)
            return np.asarray(image.convert("RGB")).copy()
    except (OSError, ValueError) as exc:
        raise EngineError(f"Cannot decode image {path.name}: {exc}") from exc


def fit_cover(image, width, height):
    h, w = image.shape[:2]
    scale = max(width / w, height / h)
    rw, rh = max(width, round(w * scale)), max(height, round(h * scale))
    interpolation = cv2.INTER_AREA if scale < 1 else cv2.INTER_CUBIC
    resized = cv2.resize(image, (rw, rh), interpolation=interpolation)
    x, y = (rw - width) // 2, (rh - height) // 2
    return np.ascontiguousarray(resized[y:y + height, x:x + width])


class DepthEstimator:
    """Quantized Depth Anything V2 Small, explicitly using the CPU provider."""

    def __init__(self, model=MODEL, threads=4, input_size=392, cache=None):
        self.model = Path(model)
        self.threads = int(number(threads, "threads", 1, 8))
        self.input_size = int(number(input_size, "depth_size", 140, 700))
        self.cache = Path(cache) if cache else None
        self.session = None
        self.inferences = 0
        self.cache_hits = 0
        self.seconds = 0.0

    def _load(self):
        if self.session is not None:
            return
        if not self.model.is_file():
            raise EngineError("Depth model is missing. Run: python motionforge.py setup")
        if file_hash(self.model) != MODEL_SHA256:
            raise EngineError("Depth model checksum mismatch; run setup to restore it.")
        try:
            import onnxruntime as ort
        except ImportError:
            raise EngineError("Install dependencies: python -m pip install -r requirements.txt") from None
        options = ort.SessionOptions()
        options.intra_op_num_threads = self.threads
        options.inter_op_num_threads = 1
        options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        self.session = ort.InferenceSession(str(self.model), sess_options=options,
                                            providers=["CPUExecutionProvider"])

    def predict(self, rgb):
        h, w = rgb.shape[:2]
        key = hashlib.sha256(rgb.tobytes() +
                             f"{MODEL_SHA256}:{self.input_size}".encode()).hexdigest()
        cached = self.cache / f"depth-{key}.npy" if self.cache else None
        if cached and cached.exists():
            try:
                result = np.load(cached, allow_pickle=False)
                if result.shape == (h, w) and np.isfinite(result).all():
                    self.cache_hits += 1
                    return result.astype(np.float32)
            except (OSError, ValueError):
                pass
        self._load()
        start = time.perf_counter()
        # Keep aspect ratio; use multiples of the ViT patch size (14).
        scale = self.input_size / max(h, w)
        nh, nw = max(140, round(h * scale / 14) * 14), max(140, round(w * scale / 14) * 14)
        resized = cv2.resize(rgb, (nw, nh), interpolation=cv2.INTER_CUBIC)
        tensor = resized.astype(np.float32) / 255.0
        tensor = (tensor - np.array([.485, .456, .406], np.float32)) / np.array([.229, .224, .225], np.float32)
        tensor = np.ascontiguousarray(tensor.transpose(2, 0, 1)[None])
        raw = self.session.run(None, {self.session.get_inputs()[0].name: tensor})[0].squeeze()
        if raw.ndim != 2 or not np.isfinite(raw).all():
            raise EngineError("The depth model returned an invalid depth map.")
        raw = cv2.resize(raw, (w, h), interpolation=cv2.INTER_CUBIC)
        lo, hi = np.percentile(raw, [2, 98])
        depth = np.clip((raw - lo) / max(float(hi - lo), 1e-6), 0, 1).astype(np.float32)
        # Edge-preserving filtering reduces stepping from int8 depth inference.
        depth = cv2.bilateralFilter(depth, 9, .06, 5)
        if cached:
            cached.parent.mkdir(parents=True, exist_ok=True)
            temporary = cached.with_name(cached.name + ".tmp")
            with temporary.open("wb") as output:
                np.save(output, depth, allow_pickle=False)
            temporary.replace(cached)
        self.inferences += 1
        self.seconds += time.perf_counter() - start
        return depth


def region_mask(region, width, height, base):
    if "mask" in region:
        path = resolve_path(region["mask"], base)
        if not path.is_file():
            raise EngineError(f"Region mask not found: {path}")
        with Image.open(path) as source:
            mask = np.asarray(source.convert("L"))
        mask = fit_cover(mask, width, height).astype(np.float32) / 255
    else:
        rect = region.get("rect", [0, 0, 1, 1])
        if not isinstance(rect, (list, tuple)) or len(rect) != 4:
            raise EngineError("A region rect requires [left, top, right, bottom].")
        l, t, r, b = [number(v, "region rect coordinate", 0, 1) for v in rect]
        if l >= r or t >= b:
            raise EngineError("Region rectangles must have positive area.")
        mask = np.zeros((height, width), np.float32)
        mask[round(t * height):round(b * height), round(l * width):round(r * width)] = 1
    feather = max(1, min(width, height) * .012)
    return cv2.GaussianBlur(mask, (0, 0), feather)


class Scene:
    def __init__(self, shot, base, width, height, estimator):
        self.width, self.height = width, height
        self.rgb = fit_cover(load_rgb(resolve_path(shot.get("image"), base)), width, height)
        depth_source = shot.get("depth", "auto")
        if depth_source == "auto":
            self.depth = estimator.predict(self.rgb)
        elif depth_source == "flat":
            self.depth = np.full((height, width), .5, np.float32)
        else:
            depth_path = resolve_path(depth_source, base)
            if not depth_path.is_file():
                raise EngineError(f"Depth map not found: {depth_path}")
            with Image.open(depth_path) as source:
                depth = np.asarray(source).astype(np.float32)
            if depth.ndim != 2:
                raise EngineError("Use a single-channel depth map; white means near.")
            depth = fit_cover(depth, width, height)
            self.depth = (depth - depth.min()) / max(float(np.ptp(depth)), 1e-6)
        self.camera = shot.get("camera", "drift")
        if self.camera not in CAMERAS:
            raise EngineError(f"Unknown camera '{self.camera}'. Choose from: {', '.join(CAMERAS)}")
        self.strength = number(shot.get("strength", .65), "strength", 0, 1)
        focus = shot.get("focus", [.5, .5])
        if not isinstance(focus, (list, tuple)) or len(focus) != 2:
            raise EngineError("focus requires [x, y] in normalized image coordinates.")
        self.focus = [number(v, "focus coordinate", 0, 1) for v in focus]
        self.yy, self.xx = np.mgrid[:height, :width].astype(np.float32)
        self.regions = []
        for region in shot.get("regions", []):
            if region.get("kind") not in ("water", "wind"):
                raise EngineError("Region kind must be 'water' or 'wind'.")
            self.regions.append((region["kind"], region_mask(region, width, height, base),
                                 number(region.get("amplitude", 1.2), "amplitude", 0, 6),
                                 number(region.get("cycles", 3), "cycles", .1, 30)))

    def render(self, progress):
        p, s = float(progress), self.strength
        q = smoothstep(p)
        tx = ty = 0.0
        zoom = 1.065 + .035 * s
        if self.camera == "drift":
            tx = (q - .5) * .05 * self.width * s
            ty = (q - .5) * .009 * self.height * s
            zoom += .035 * s * q
        elif self.camera == "push":
            zoom += .085 * s * q
        elif self.camera == "rise":
            ty = (q - .5) * .05 * self.height * s
            zoom += .035 * s * q
        elif self.camera == "orbit":
            tx = math.sin((q - .5) * math.pi) * .024 * self.width * s
            ty = math.cos((q - .5) * math.pi) * .007 * self.height * s
            zoom += .035 * s * math.sin(math.pi * q)
        elif self.camera == "loop":
            tx = math.sin(2 * math.pi * p) * .02 * self.width * s
            ty = math.cos(2 * math.pi * p) * .009 * self.height * s
            zoom += .015 * s * (1 - math.cos(2 * math.pi * p))
        elif self.camera == "still":
            zoom = 1.0
        if s == 0:
            zoom, tx, ty = 1.0, 0.0, 0.0
        cx, cy = self.width * self.focus[0], self.height * self.focus[1]
        base_x, base_y = (self.xx - cx) / zoom + cx, (self.yy - cy) / zoom + cy
        # Inverse depth-aware warp; two fixed-point steps keep depth edges aligned.
        map_x, map_y = base_x.copy(), base_y.copy()
        if tx or ty:
            for _ in range(2):
                local_depth = cv2.remap(self.depth, map_x, map_y, cv2.INTER_LINEAR,
                                         borderMode=cv2.BORDER_REPLICATE)
                parallax = .30 + .80 * local_depth
                map_x = base_x - tx * parallax
                map_y = base_y - ty * parallax
        for kind, mask, amplitude, cycles in self.regions:
            phase = p * 2 * math.pi * cycles
            if kind == "water":
                map_x += mask * amplitude * np.sin(self.yy * .105 + phase)
                map_y += mask * amplitude * .25 * np.cos(self.xx * .032 + phase)
            else:
                map_x += mask * amplitude * np.sin(self.yy * .019 + phase)
        # Crop margin above normally prevents border sampling; replicate is a safety net.
        return cv2.remap(self.rgb, map_x, map_y, cv2.INTER_LINEAR,
                          borderMode=cv2.BORDER_REPLICATE)


def child_peak_rss_mb():
    try:
        import resource
        scale = 1024 * 1024 if sys.platform == "darwin" else 1024
        return resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss / scale
    except ImportError:
        return None


def peak_rss_mb():
    try:
        import resource
        scale = 1024 * 1024 if sys.platform == "darwin" else 1024
        return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / scale
    except ImportError:
        return None


class VideoWriter:
    def __init__(self, output, width, height, fps, frames, threads=4, audio=None):
        executable = shutil.which("ffmpeg")
        if not executable:
            raise EngineError("FFmpeg is missing. Install FFmpeg and add it to PATH.")
        self.output = Path(output).resolve()
        if self.output.suffix.lower() != ".mp4":
            raise EngineError("Use an .mp4 output filename.")
        self.output.parent.mkdir(parents=True, exist_ok=True)
        self.temporary = self.output.with_name(f".{self.output.stem}-{uuid.uuid4().hex}.partial.mp4")
        self.width, self.height, self.expected, self.written = width, height, frames, 0
        self.stderr = tempfile.TemporaryFile()
        command = [executable, "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo",
                   "-pix_fmt", "rgb24", "-s:v", f"{width}x{height}", "-r", str(fps), "-i", "pipe:0"]
        if audio:
            if not Path(audio).is_file():
                self.stderr.close()
                raise EngineError(f"Audio not found: {audio}")
            command += ["-i", str(audio), "-map", "0:v:0", "-map", "1:a:0", "-af", "apad",
                        "-c:a", "aac", "-b:a", "160k"]
        command += ["-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-threads", str(threads),
                    "-pix_fmt", "yuv420p", "-t", f"{frames / fps:.9f}", "-movflags", "+faststart",
                    str(self.temporary)]
        self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                         stderr=self.stderr)

    def write(self, rgb):
        if rgb.shape != (self.height, self.width, 3) or rgb.dtype != np.uint8:
            raise EngineError("Renderer produced an invalid video frame.")
        try:
            self.process.stdin.write(np.ascontiguousarray(rgb).tobytes())
        except (BrokenPipeError, OSError):
            raise EngineError("FFmpeg stopped unexpectedly. Check the encoder and free disk space.") from None
        self.written += 1

    def close(self, success):
        try:
            if success:
                try:
                    self.process.stdin.close()
                except BrokenPipeError:
                    pass
                try:
                    code = self.process.wait(timeout=45)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait()
                    raise EngineError("FFmpeg did not finish within 45 seconds.") from None
                if code or self.written != self.expected:
                    self.stderr.seek(0)
                    detail = self.stderr.read().decode(errors="replace")[-2000:]
                    raise EngineError(f"Video export failed ({self.written}/{self.expected} frames): {detail}")
                self.temporary.replace(self.output)
            else:
                self.process.kill()
                self.process.stdin.close()
                self.process.wait()
        finally:
            self.stderr.close()
            self.temporary.unlink(missing_ok=True)


def write_report(output, info, start):
    report = dict(info)
    report.update(engine="MotionForge CPU", version=VERSION, output=str(Path(output).resolve()),
                  wall_seconds=round(time.perf_counter() - start, 3),
                  peak_process_rss_mb=round(peak_rss_mb() or 0, 2),
                  peak_encoder_rss_mb=round(child_peak_rss_mb() or 0, 2))
    report["output_bytes"] = Path(output).stat().st_size
    sidecar = Path(output).with_suffix(".report.json")
    sidecar.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, ensure_ascii=False), flush=True)
    return report


def render_project(project, output, base=ROOT, model=MODEL, threads=4, cache=None):
    start = time.perf_counter()
    base = Path(base).resolve()
    width, height, fps = validate_video(project.get("width", 1280), project.get("height", 720), project.get("fps", 24))
    threads = int(number(threads, "threads", 1, 8))
    cv2.setNumThreads(threads)
    shots = project.get("shots")
    if not isinstance(shots, list) or not shots or len(shots) > 100:
        raise EngineError("A project needs between 1 and 100 shots.")
    if any(not isinstance(shot, dict) for shot in shots):
        raise EngineError("Each shot must be a JSON object.")
    default_transition = number(project.get("transition", .5), "transition", 0, 5)
    starts, lengths, overlaps = [], [], []
    for i, shot in enumerate(shots):
        count = max(2, round(number(shot.get("seconds", 6), "shot seconds", .1, 600) * fps))
        lengths.append(count)
        starts.append(0 if i == 0 else starts[-1] + lengths[-2] - overlaps[-1])
        transition = number(shot.get("transition", default_transition), "transition", 0, 5)
        if i < len(shots) - 1:
            following = max(2, round(number(shots[i+1].get("seconds", 6), "shot seconds", .1, 600) * fps))
            overlaps.append(min(round(transition * fps), (count - 1) // 2, (following - 1) // 2))
        else:
            overlaps.append(0)
    frames = starts[-1] + lengths[-1]
    estimator = DepthEstimator(model, threads, project.get("depth_size", 392), cache)
    active = {0: Scene(shots[0], base, width, height, estimator)}
    audio = resolve_path(project["audio"], base) if project.get("audio") else None
    writer = VideoWriter(output, width, height, fps, frames, threads, audio)
    success = False
    current = 0
    log(f"Rendering {frames} frames at {width}x{height}, {fps} fps on CPU...")
    try:
        for index in range(frames):
            while current < len(shots) - 1 and index >= starts[current] + lengths[current]:
                active.pop(current, None)
                current += 1
            if current not in active:
                active[current] = Scene(shots[current], base, width, height, estimator)
            local = index - starts[current]
            frame = active[current].render(local / max(lengths[current] - 1, 1))
            next_shot = current + 1
            if next_shot < len(shots) and index >= starts[next_shot]:
                if next_shot not in active:
                    active[next_shot] = Scene(shots[next_shot], base, width, height, estimator)
                next_local = index - starts[next_shot]
                other = active[next_shot].render(next_local / max(lengths[next_shot] - 1, 1))
                weight = smoothstep((next_local + 1) / (overlaps[current] + 1))
                frame = cv2.addWeighted(frame, 1 - weight, other, weight, 0)
            writer.write(frame)
            if index % max(fps * 2, 1) == 0:
                log(f"  {index + 1}/{frames}")
        success = True
    finally:
        writer.close(success)
    return write_report(output, {"mode": "depth-camera", "width": width, "height": height,
                                 "fps": fps, "frames": frames, "duration_seconds": frames / fps,
                                 "shots": len(shots), "neural_depth_inferences": estimator.inferences,
                                 "depth_cache_hits": estimator.cache_hits,
                                 "depth_inference_seconds": round(estimator.seconds, 3),
                                 "model_sha256": MODEL_SHA256 if any(s.get("depth", "auto") == "auto" for s in shots) else None,
                                 "generates_new_poses": False}, start)


class KeyframePair:
    """Bidirectional DIS optical flow; requires related views of the same scene."""

    def __init__(self, first, second):
        self.first, self.second = first, second
        h, w = first.shape[:2]
        self.yy, self.xx = np.mgrid[:h, :w].astype(np.float32)
        scale = min(1., 640. / max(w, h))
        sw, sh = max(32, round(w * scale)), max(32, round(h * scale))
        gray0 = cv2.cvtColor(cv2.resize(first, (sw, sh)), cv2.COLOR_RGB2GRAY)
        gray1 = cv2.cvtColor(cv2.resize(second, (sw, sh)), cv2.COLOR_RGB2GRAY)
        dis = cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM)
        forward = dis.calc(gray0, gray1, None)
        backward = dis.calc(gray1, gray0, None)
        factor = np.array([w / sw, h / sh], np.float32)
        self.forward = cv2.resize(forward, (w, h)) * factor
        self.backward = cv2.resize(backward, (w, h)) * factor
        back_at_forward = cv2.remap(self.backward, self.xx + self.forward[..., 0],
                                     self.yy + self.forward[..., 1], cv2.INTER_LINEAR,
                                     borderMode=cv2.BORDER_REPLICATE)
        forward_at_back = cv2.remap(self.forward, self.xx + self.backward[..., 0],
                                     self.yy + self.backward[..., 1], cv2.INTER_LINEAR,
                                     borderMode=cv2.BORDER_REPLICATE)
        self.conf0 = np.exp(-.2 * np.linalg.norm(self.forward + back_at_forward, axis=2)).astype(np.float32)
        self.conf1 = np.exp(-.2 * np.linalg.norm(self.backward + forward_at_back, axis=2)).astype(np.float32)

    def render(self, progress):
        p = float(np.clip(progress, 0, 1))
        if p <= 0:
            return self.first.copy()
        if p >= 1:
            return self.second.copy()
        mx0, my0, mx1, my1 = self.xx.copy(), self.yy.copy(), self.xx.copy(), self.yy.copy()
        for _ in range(3):
            f = cv2.remap(self.forward, mx0, my0, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
            b = cv2.remap(self.backward, mx1, my1, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
            mx0, my0 = self.xx - p * f[..., 0], self.yy - p * f[..., 1]
            mx1, my1 = self.xx - (1 - p) * b[..., 0], self.yy - (1 - p) * b[..., 1]
        a = cv2.remap(self.first, mx0, my0, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE).astype(np.float32)
        b = cv2.remap(self.second, mx1, my1, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE).astype(np.float32)
        ca = cv2.remap(self.conf0, mx0, my0, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
        cb = cv2.remap(self.conf1, mx1, my1, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
        wa = ((1 - p) * np.maximum(ca, .05))[..., None]
        wb = (p * np.maximum(cb, .05))[..., None]
        return np.clip((a * wa + b * wb) / (wa + wb), 0, 255).astype(np.uint8)


def render_keyframes(images, output, seconds=6, width=1280, height=720, fps=24, threads=4, audio=None):
    start = time.perf_counter()
    width, height, fps = validate_video(width, height, fps)
    seconds = number(seconds, "seconds", .1, 600)
    threads = int(number(threads, "threads", 1, 8))
    if not 2 <= len(images) <= 100:
        raise EngineError("Keyframe mode requires between 2 and 100 related images.")
    cv2.setNumThreads(threads)
    frames = max(2, round(seconds * fps))
    writer = VideoWriter(output, width, height, fps, frames, threads, audio)
    pair, pair_number = None, -1
    success = False
    log("Interpolating keyframes with CPU optical flow. Large pose changes may create artifacts.")
    try:
        for i in range(frames):
            position = i / (frames - 1) * (len(images) - 1)
            segment = min(int(position), len(images) - 2)
            if segment != pair_number:
                log(f"  Preparing pair {segment + 1}/{len(images) - 1}")
                first = fit_cover(load_rgb(images[segment]), width, height)
                second = fit_cover(load_rgb(images[segment+1]), width, height)
                pair = KeyframePair(first, second)
                pair_number = segment
            writer.write(pair.render(position - segment))
        success = True
    finally:
        writer.close(success)
    return write_report(output, {"mode": "keyframe-optical-flow", "width": width, "height": height,
                                 "fps": fps, "frames": frames, "duration_seconds": frames / fps,
                                 "keyframes": len(images), "generates_new_poses": False}, start)


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--version", action="version", version=f"MotionForge CPU {VERSION}")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("setup", help="Download/check the 27.3 MB neural depth model.")
    render = sub.add_parser("render", help="Animate an image or render a JSON shot list.")
    source = render.add_mutually_exclusive_group(required=True)
    source.add_argument("--image", type=Path)
    source.add_argument("--project", type=Path)
    render.add_argument("--output", type=Path, required=True)
    render.add_argument("--seconds", type=float, default=8)
    render.add_argument("--camera", choices=CAMERAS, default="drift")
    render.add_argument("--strength", type=float, default=.65)
    render.add_argument("--depth", default="auto", help="auto, flat, or a grayscale depth-map path")
    render.add_argument("--depth-size", type=int, default=392)
    render.add_argument("--model", type=Path, default=MODEL)
    render.add_argument("--cache", type=Path, default=ROOT / ".cache")
    morph = sub.add_parser("morph", help="Interpolate related keyframes using bidirectional optical flow.")
    morph.add_argument("--images", nargs="+", type=Path, required=True)
    morph.add_argument("--output", type=Path, required=True)
    morph.add_argument("--seconds", type=float, default=6)
    for command in (render, morph):
        command.add_argument("--width", type=int, default=1280)
        command.add_argument("--height", type=int, default=720)
        command.add_argument("--fps", type=int, default=24)
        command.add_argument("--threads", type=int, default=4)
        command.add_argument("--audio", type=Path)
    depth = sub.add_parser("depth", help="Export the model's relative depth map (16-bit PNG).")
    depth.add_argument("--image", type=Path, required=True)
    depth.add_argument("--output", type=Path, required=True)
    depth.add_argument("--depth-size", type=int, default=392)
    depth.add_argument("--threads", type=int, default=4)
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        if args.command == "setup":
            print(setup_model())
        elif args.command == "depth":
            rgb = load_rgb(args.image)
            depth = DepthEstimator(threads=args.threads, input_size=args.depth_size).predict(rgb)
            if args.output.suffix.lower() != ".png":
                raise EngineError("Depth output must be a .png file.")
            args.output.parent.mkdir(parents=True, exist_ok=True)
            Image.fromarray((depth * 65535).astype(np.uint16)).save(args.output)
            print(args.output.resolve())
        elif args.command == "morph":
            render_keyframes(args.images, args.output, args.seconds, args.width, args.height,
                             args.fps, args.threads, args.audio)
        else:
            if args.project:
                base = args.project.resolve().parent
                try:
                    project = json.loads(args.project.read_text(encoding="utf-8"))
                except (OSError, ValueError) as exc:
                    raise EngineError(f"Cannot read project: {exc}") from exc
                if not isinstance(project, dict):
                    raise EngineError("The project root must be a JSON object.")
            else:
                base = Path.cwd()
                project = {"width": args.width, "height": args.height, "fps": args.fps,
                           "depth_size": args.depth_size,
                           "shots": [{"image": str(args.image.resolve()), "seconds": args.seconds,
                                      "camera": args.camera, "strength": args.strength, "depth": args.depth}]}
            if args.audio:
                project["audio"] = str(args.audio.resolve())
            render_project(project, args.output, base, args.model, args.threads, args.cache)
        return 0
    except (EngineError, OSError, ValueError, cv2.error) as exc:
        log(f"Error: {exc}")
        return 2
    except KeyboardInterrupt:
        log("Cancelled; incomplete video removed.")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
