#!/usr/bin/env python3
"""MotionForge Studio: externally generated image poses + CPU animation/rendering.

Image creation is performed by ChatGPT's image-generation tool. This program
loads those assets, interpolates RGBA poses, animates tracks and exports video.
It does not contain or claim to train a local video diffusion model.
"""
from __future__ import annotations

import argparse
from collections import OrderedDict
import json
import math
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time

import cv2
import numpy as np
from PIL import Image, ImageOps

import motionforge as core

ROOT = Path(__file__).resolve().parent
VERSION = "0.3.0"


def load_rgba(path):
    if not Path(path).is_file():
        raise core.EngineError(f"Asset not found: {path}")
    with Image.open(path) as source:
        rgba = np.asarray(ImageOps.exif_transpose(source).convert("RGBA")).copy()
    # Some generated transparent images retain an almost transparent color matte.
    rgba[rgba[..., 3] < 8] = 0
    return rgba


def unpack_atlas(path, columns, rows, count=None, size=320, register_feet=True):
    """Unpack exact normalized grid cells, handling non-divisible atlas sizes."""
    columns = int(core.number(columns, "columns", 1, 16))
    rows = int(core.number(rows, "rows", 1, 16))
    count = int(core.number(count or columns * rows, "count", 1, columns * rows))
    if count > 72:
        raise core.EngineError("A sprite track supports at most 72 poses.")
    rgba = load_rgba(path)
    h, w = rgba.shape[:2]
    if w < columns * 16 or h < rows * 16:
        raise core.EngineError("Atlas cells are too small.")
    if float((rgba[..., 3] < 16).mean()) < .02:
        raise core.EngineError("Sprite atlases need a transparent background.")
    cells, bboxes = [], []
    for index in range(count):
        row, col = divmod(index, columns)
        cell = rgba[round(row * h / rows):round((row+1) * h / rows),
                    round(col * w / columns):round((col+1) * w / columns)].copy()
        ys, xs = np.where(cell[..., 3] > 40)
        if not len(xs):
            raise core.EngineError(f"Atlas cell {index + 1} has no visible subject.")
        cells.append(cell)
        bboxes.append((int(xs.min()), int(ys.min()), int(xs.max())+1, int(ys.max())+1))
    typical_height = float(np.median([b[3] - b[1] for b in bboxes]))
    scale = min(size * .80 / typical_height, size * .92 / max(c.shape[1] for c in cells))
    result = []
    for cell, box in zip(cells, bboxes):
        # Use one scale for every pose, rather than changing its size per frame.
        # Horizontal registration stays fixed to preserve the actual limb motion.
        cy = box[3] if register_feet else cell.shape[0] * .9
        matrix = np.float32([[scale, 0, size * .5 - cell.shape[1] * .5 * scale],
                             [0, scale, size * .90 - cy * scale]])
        registered = cv2.warpAffine(cell, matrix, (size, size), flags=cv2.INTER_CUBIC,
                                     borderMode=cv2.BORDER_CONSTANT, borderValue=0)
        registered[..., :3][registered[..., 3] < 8] = 0
        result.append(registered)
    return result


def premultiply(rgba):
    result = rgba.astype(np.float32) / 255
    result[..., :3] *= result[..., 3:4]
    return result


class AlphaFlow:
    """Interpolate related poses in premultiplied RGBA, including the silhouette."""

    def __init__(self, first, second):
        self.first, self.second = premultiply(first), premultiply(second)
        h, w = first.shape[:2]
        self.yy, self.xx = np.mgrid[:h, :w].astype(np.float32)
        images = []
        for image in (self.first, self.second):
            composed = np.clip(image[..., :3] + .12 * (1 - image[..., 3:4]), 0, 1)
            images.append(cv2.cvtColor((composed * 255).astype(np.uint8), cv2.COLOR_RGB2GRAY))
        dis = cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM)
        self.forward = dis.calc(images[0], images[1], None)
        self.backward = dis.calc(images[1], images[0], None)

    def render(self, weight):
        p = float(np.clip(weight, 0, 1))
        if p <= 0:
            return self.first.copy()
        if p >= 1:
            return self.second.copy()
        mx0, my0, mx1, my1 = self.xx.copy(), self.yy.copy(), self.xx.copy(), self.yy.copy()
        for _ in range(3):
            f = cv2.remap(self.forward, mx0, my0, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
            b = cv2.remap(self.backward, mx1, my1, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
            mx0, my0 = self.xx - p * f[..., 0], self.yy - p * f[..., 1]
            mx1, my1 = self.xx - (1-p) * b[..., 0], self.yy - (1-p) * b[..., 1]
        a = cv2.remap(self.first, mx0, my0, cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
        b = cv2.remap(self.second, mx1, my1, cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
        result = cv2.addWeighted(a, 1-p, b, p, 0)
        # Clipping premultiplied RGB to alpha prevents colored transparent fringes.
        result[..., :3] = np.minimum(result[..., :3], result[..., 3:4])
        return np.clip(result, 0, 1)


class PoseSequence:
    def __init__(self, specification, base):
        work_size = int(core.number(specification.get("work_size", 320), "work_size", 128, 640))
        if "atlas" in specification:
            self.frames = unpack_atlas(core.resolve_path(specification["atlas"], base),
                                       specification.get("columns", 4), specification.get("rows", 4),
                                       specification.get("count"), work_size,
                                       specification.get("register_feet", True))
        elif "frames" in specification:
            paths = specification["frames"]
            if not isinstance(paths, list) or not 1 <= len(paths) <= 72:
                raise core.EngineError("frames must list between 1 and 72 transparent images.")
            self.frames = [core.fit_cover(load_rgba(core.resolve_path(path, base)), work_size, work_size)
                           for path in paths]
        elif "image" in specification:
            self.frames = [core.fit_cover(load_rgba(core.resolve_path(specification["image"], base)), work_size, work_size)]
        else:
            raise core.EngineError("A track needs atlas, frames or image.")
        self.fps = core.number(specification.get("pose_fps", 8), "pose_fps", .1, 60)
        self.loop = bool(specification.get("loop", True))
        self.offset = core.number(specification.get("pose_offset", 0), "pose_offset", 0, 10000)
        self.interpolation = specification.get("interpolation", "flow")
        if self.interpolation not in ("flow", "blend", "nearest"):
            raise core.EngineError("interpolation must be flow, blend or nearest.")
        self.cache = OrderedDict()
        self.pairs_computed = 0

    def sample(self, seconds):
        if len(self.frames) == 1:
            return premultiply(self.frames[0])
        phase = max(0., seconds * self.fps + self.offset)
        if self.loop:
            phase %= len(self.frames)
        else:
            phase = min(phase, len(self.frames) - 1)
        first = int(phase)
        second = (first+1) % len(self.frames) if self.loop else min(first+1, len(self.frames)-1)
        weight = phase - first
        if self.interpolation == "nearest":
            return premultiply(self.frames[first if weight < .5 else second])
        if self.interpolation == "blend":
            return cv2.addWeighted(premultiply(self.frames[first]), 1-weight,
                                    premultiply(self.frames[second]), weight, 0)
        key = (first, second)
        if key not in self.cache:
            self.cache[key] = AlphaFlow(self.frames[first], self.frames[second])
            self.pairs_computed += 1
            while len(self.cache) > 4:
                self.cache.popitem(last=False)
        self.cache.move_to_end(key)
        return self.cache[key].render(weight)


def transform_at(keys, seconds):
    first = keys[0]
    second = keys[-1]
    if seconds <= first["time"]:
        return first
    if seconds >= second["time"]:
        return second
    for a, b in zip(keys, keys[1:]):
        if a["time"] <= seconds <= b["time"]:
            p = (seconds - a["time"]) / (b["time"] - a["time"])
            if b.get("ease", "linear") == "smooth":
                p = core.smoothstep(p)
            return {key: a[key] + (b[key] - a[key]) * p
                    for key in ("x", "y", "height", "rotation", "opacity")}
    return second


class Track:
    def __init__(self, specification, base, duration):
        self.poses = PoseSequence(specification, base)
        self.start = core.number(specification.get("start", 0), "track start", 0, duration)
        self.end = core.number(specification.get("end", duration), "track end", self.start, duration)
        self.shadow = bool(specification.get("shadow", True))
        keys = specification.get("keys", [{"time": 0, "x": .5, "y": .85, "height": .4}])
        if not isinstance(keys, list) or not keys or not all(isinstance(k, dict) for k in keys):
            raise core.EngineError("keys must be a nonempty list of transform objects.")
        self.keys = []
        previous = dict(x=.5, y=.85, height=.4, rotation=0, opacity=1)
        for key in keys:
            resolved = {"time": core.number(key.get("time", 0), "key time", 0, duration),
                        "ease": key.get("ease", "linear")}
            for name, minimum, maximum in [("x", -2, 3), ("y", -2, 3), ("height", .01, 3),
                                           ("rotation", -720, 720), ("opacity", 0, 1)]:
                resolved[name] = core.number(key.get(name, previous[name]), name, minimum, maximum)
            if self.keys and resolved["time"] <= self.keys[-1]["time"]:
                raise core.EngineError("Transform key times must strictly increase.")
            if resolved["ease"] not in ("linear", "smooth"):
                raise core.EngineError("Transform easing must be linear or smooth.")
            self.keys.append(resolved)
            previous = resolved

    def composite(self, background, seconds):
        if seconds < self.start or seconds > self.end:
            return background
        h, w = background.shape[:2]
        pose = transform_at(self.keys, seconds)
        if pose["opacity"] == 0:
            return background
        rgba = self.poses.sample(seconds - self.start)
        sh, sw = rgba.shape[:2]
        scale = h * pose["height"] / sh
        radians = math.radians(pose["rotation"])
        c, s = math.cos(radians) * scale, math.sin(radians) * scale
        ax, ay = sw * .5, sh * .90
        x, y = pose["x"] * w, pose["y"] * h
        matrix = np.float32([[c, -s, x - c*ax + s*ay], [s, c, y - s*ax - c*ay]])
        if self.shadow:
            rx, ry = max(2., h * pose["height"] * .28), max(2., h * pose["height"] * .035)
            left, right = max(0, int(x - rx*2)), min(w, int(x + rx*2 + 1))
            top, bottom = max(0, int(y - ry*2)), min(h, int(y + ry*2 + 1))
            if left < right and top < bottom:
                yy, xx = np.mgrid[top:bottom, left:right]
                shadow = np.exp(-((xx-x)/rx)**2*2 - ((yy-y)/ry)**2*2) * .30 * pose["opacity"]
                background[top:bottom, left:right] *= 1-shadow[..., None]
        layer = cv2.warpAffine(rgba, matrix, (w, h), flags=cv2.INTER_LINEAR,
                                borderMode=cv2.BORDER_CONSTANT, borderValue=0)
        layer *= pose["opacity"]
        alpha = np.clip(layer[..., 3:4], 0, 1)
        background *= 1-alpha
        background += layer[..., :3]
        return background


class Dust:
    def __init__(self, count, width, height):
        rng = np.random.default_rng(127)
        self.particles = rng.random((count, 6))
        self.width, self.height = width, height

    def apply(self, frame, seconds):
        overlay = np.zeros_like(frame)
        for x, y, speed, phase, size, brightness in self.particles:
            px = int((x + seconds * (.004 + speed * .005)) % 1 * self.width)
            py = int((y * .8 + math.sin(seconds * .7 + phase*6.28) * .014) * self.height)
            radius = max(1, int(1 + size*2))
            glow = (.3 + brightness*.5) * (.65 + .35*math.sin(seconds*1.7+phase*6.28))
            cv2.circle(overlay, (px, py), radius, (glow, glow*.78, glow*.35), -1)
        frame += cv2.GaussianBlur(overlay, (0, 0), .7)
        return np.clip(frame, 0, 1)


def gif_preview(video, output, seconds=4, width=480, fps=12):
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    filters = (f"fps={fps},scale={width}:-1:flags=lanczos,split[a][b];"
               "[a]palettegen=max_colors=160:stats_mode=diff[p];"
               "[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle")
    command = [shutil.which("ffmpeg") or "ffmpeg", "-v", "error", "-y", "-t", str(seconds),
               "-i", str(video), "-filter_complex", filters, "-filter_complex_threads", "2",
               "-threads", "2", "-loop", "0", str(output)]
    completed = subprocess.run(command, capture_output=True, timeout=60)
    if completed.returncode:
        output.unlink(missing_ok=True)
        raise core.EngineError("GIF preview failed: " + completed.stderr.decode(errors="replace")[-1000:])
    return output


def render(project_path, output, preview_gif=None, threads=4):
    started = time.perf_counter()
    project_path = Path(project_path).resolve()
    try:
        project = json.loads(project_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise core.EngineError(f"Cannot read project: {exc}") from exc
    if not isinstance(project, dict):
        raise core.EngineError("Project root must be an object.")
    base = project_path.parent
    width, height, fps = core.validate_video(project.get("width", 1280), project.get("height", 720), project.get("fps", 24))
    duration = core.number(project.get("seconds", 8), "seconds", .1, 600)
    threads = int(core.number(threads, "threads", 1, 8))
    cv2.setNumThreads(threads)
    frames = max(2, round(duration * fps))
    background_spec = project.get("background")
    if not isinstance(background_spec, dict):
        raise core.EngineError("Project needs a background object.")
    estimator = core.DepthEstimator(threads=threads, input_size=project.get("depth_size", 392), cache=ROOT / "cache")
    background = core.Scene(background_spec, base, width, height, estimator)
    track_specs = project.get("tracks", [])
    if not isinstance(track_specs, list) or len(track_specs) > 6 or not all(isinstance(t, dict) for t in track_specs):
        raise core.EngineError("tracks must be a list of up to six objects.")
    tracks = [Track(spec, base, duration) for spec in track_specs]
    dust = Dust(int(core.number(project.get("dust", 0), "dust", 0, 100)), width, height)
    audio = core.resolve_path(project["audio"], base) if project.get("audio") else None
    writer = core.VideoWriter(output, width, height, fps, frames, threads, audio)
    success = False
    core.log(f"Rendering {len(tracks)} character/object tracks, {frames} frames, CPU only...")
    try:
        for frame_number in range(frames):
            seconds = frame_number / fps
            frame = background.render(frame_number / max(1, frames-1)).astype(np.float32) / 255
            frame = dust.apply(frame, seconds)
            for track in tracks:
                frame = track.composite(frame, seconds)
            writer.write(np.clip(frame * 255, 0, 255).astype(np.uint8))
            if frame_number % max(1, fps*2) == 0:
                core.log(f"  {frame_number+1}/{frames}")
        success = True
    finally:
        writer.close(success)
    render_seconds = time.perf_counter() - started
    report = {"engine": "MotionForge Studio", "version": VERSION, "mode": "generated-poses-cpu-compositor",
              "title": project.get("title", project_path.stem), "width": width, "height": height,
              "fps": fps, "frames": frames, "duration_seconds": frames / fps,
              "tracks": len(tracks), "pose_counts": [len(t.poses.frames) for t in tracks],
              "optical_flow_pairs_computed": sum(t.poses.pairs_computed for t in tracks),
              "neural_depth_inferences": estimator.inferences, "neural_depth_cache_hits": estimator.cache_hits,
              "render_seconds": round(render_seconds, 3),
              "peak_renderer_rss_mb": round(core.peak_rss_mb() or 0, 2),
              "peak_encoder_rss_mb": round(core.child_peak_rss_mb() or 0, 2),
              "image_generation": "External ChatGPT image generation; assets supplied before rendering",
              "local_video_diffusion_model": False, "video_bytes": Path(output).stat().st_size}
    if preview_gif:
        gif_preview(output, preview_gif, seconds=min(4, frames/fps))
        report["preview_gif_bytes"] = Path(preview_gif).stat().st_size
    Path(output).with_suffix(".report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return report


def new_job(destination, brief):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=False)
    for name in ("assets", "prompts", "output"):
        (destination / name).mkdir()
    (destination / "brief.txt").write_text(brief + "\n", encoding="utf-8")
    requests = {"brief": brief, "provider": "ChatGPT built-in image generation, invoked by the assistant",
                "requests": [{"id": "background", "output": "assets/background.png", "transparent": False,
                              "instruction": "One background plate with room for the action; no main character."},
                             {"id": "poses", "output": "assets/poses.png", "transparent": True,
                              "instruction": "One exact 4x4 animation atlas; same character, chronological poses, transparent background."}],
                "status": "awaiting_generated_assets"}
    (destination / "asset_requests.json").write_text(json.dumps(requests, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    project = {"title": destination.name, "width": 1280, "height": 720, "fps": 24, "seconds": 8,
               "background": {"image": "assets/background.png", "depth": "auto", "camera": "drift", "strength": .2},
               "tracks": [{"atlas": "assets/poses.png", "columns": 4, "rows": 4, "pose_fps": 8,
                           "keys": [{"time": 0, "x": .2, "y": .85, "height": .4},
                                    {"time": 8, "x": .8, "y": .85, "height": .4}]}]}
    (destination / "project.json").write_text(json.dumps(project, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(destination.resolve())


def doctor():
    import onnxruntime as ort
    info = {"platform": platform.platform(), "python": platform.python_version(),
            "opencv": cv2.__version__, "onnxruntime": ort.__version__,
            "ffmpeg": shutil.which("ffmpeg"), "depth_model_present": core.MODEL.is_file(),
            "render_provider": "CPUExecutionProvider", "gpu_required": False}
    print(json.dumps(info, indent=2))
    return 0 if info["ffmpeg"] else 2


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", action="version", version=f"MotionForge Studio {VERSION}")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("doctor")
    sub.add_parser("setup")
    job = sub.add_parser("new-job")
    job.add_argument("directory", type=Path)
    job.add_argument("--brief", required=True)
    run = sub.add_parser("render")
    run.add_argument("project", type=Path)
    run.add_argument("--output", type=Path, required=True)
    run.add_argument("--gif", type=Path)
    run.add_argument("--threads", type=int, default=4)
    args = parser.parse_args(argv)
    try:
        if args.command == "doctor":
            return doctor()
        if args.command == "setup":
            print(core.setup_model())
        elif args.command == "new-job":
            new_job(args.directory, args.brief)
        else:
            render(args.project, args.output, args.gif, args.threads)
        return 0
    except (core.EngineError, OSError, ValueError, cv2.error, subprocess.TimeoutExpired) as exc:
        core.log(f"Error: {exc}")
        return 2
    except KeyboardInterrupt:
        core.log("Cancelled; incomplete video removed.")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
