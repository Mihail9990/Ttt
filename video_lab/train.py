#!/usr/bin/env python3
"""Continuous train-window travel: spatially joined outpaintings, no scene fades."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import time

import cv2
import numpy as np
from PIL import Image, ImageDraw

import motionforge as core

ROOT = Path(__file__).resolve().parent
VERSION = "0.3.0"


def register_neighbor(previous, following):
    """Find the shared geography on the right/left sides of neighboring plates."""
    h, w = previous.shape[:2]
    left_offset = round(w * .5)
    detector = cv2.ORB_create(nfeatures=6000, fastThreshold=8)
    ka, da = detector.detectAndCompute(cv2.cvtColor(previous[:, left_offset:], cv2.COLOR_RGB2GRAY), None)
    kb, db = detector.detectAndCompute(cv2.cvtColor(following[:, :round(following.shape[1] * .55)], cv2.COLOR_RGB2GRAY), None)
    if da is None or db is None or len(da) < 2 or len(db) < 2:
        raise core.EngineError("No shared landscape details. Generate an overlapping continuation first.")
    matches = cv2.BFMatcher(cv2.NORM_HAMMING).knnMatch(db, da, k=2)
    good = [pair[0] for pair in matches if len(pair) == 2 and pair[0].distance < .75 * pair[1].distance]
    if len(good) < 24:
        raise core.EngineError("Neighboring landscapes do not share enough matching details.")
    a = np.float32([[ka[m.trainIdx].pt[0] + left_offset, ka[m.trainIdx].pt[1]] for m in good])
    b = np.float32([kb[m.queryIdx].pt for m in good])
    matrix, inliers = cv2.estimateAffinePartial2D(b, a, method=cv2.RANSAC,
                                                ransacReprojThreshold=3, maxIters=5000)
    if matrix is None or inliers is None or int(inliers.sum()) < 24:
        raise core.EngineError("A reliable spatial join could not be established.")
    scale = math.hypot(matrix[0, 0], matrix[1, 0])
    angle = math.degrees(math.atan2(matrix[1, 0], matrix[0, 0]))
    keep = inliers.ravel().astype(bool)
    if abs(scale-1) < .0006 and abs(angle) < .02:
        # Exact overlapping crops should not acquire a resampling blur from
        # tiny ORB localization errors. Validate the actual shared pixels.
        translation = np.round(np.median(a[keep]-b[keep], axis=0))
        tx, ty = map(int, translation)
        x0, x1 = max(0,tx), min(w,tx+following.shape[1])
        y0, y1 = max(0,ty), min(h,ty+following.shape[0])
        shared_a = previous[y0:y1:4,x0:x1:4].astype(np.float32)
        shared_b = following[y0-ty:y1-ty:4,x0-tx:x1-tx:4].astype(np.float32)
        residual = shared_a-shared_b
        residual -= np.median(residual,axis=(0,1))
        if residual.size and np.percentile(np.abs(residual),95) < 1.5:
            matrix = np.array([[1., 0., translation[0]], [0., 1., translation[1]]])
            scale, angle = 1., 0.
    if not (.85 <= scale <= 1.15 and abs(angle) < 3 and .3*w < matrix[0, 2] < .9*w
            and abs(matrix[1, 2]) < h * .15):
        raise core.EngineError("The continuation changed scale or viewpoint too much for a safe join.")
    predicted = b[keep] @ matrix[:, :2].T + matrix[:, 2]
    error = np.linalg.norm(predicted - a[keep], axis=1)
    report = {"matches": len(good), "inliers": int(keep.sum()),
              "median_alignment_error_pixels": round(float(np.median(error)), 3),
              "scale": round(scale, 6), "rotation_degrees": round(angle, 5),
              "matrix": matrix.tolist()}
    affine = np.eye(3, dtype=np.float64)
    affine[:2] = matrix
    return affine, report


def low_error_seam(first, second):
    """A vertical minimum-error seam avoids superimposing misaligned objects."""
    diff = np.abs(first.astype(np.float32) - second.astype(np.float32)).mean(axis=2)
    h, w = diff.shape
    center = np.linspace(-1, 1, w, dtype=np.float32)
    diff += 1.5 * center[None, :] ** 2
    cumulative = diff[0].copy()
    parent = np.zeros((h, w), np.int8)
    for y in range(1, h):
        candidates = np.stack([np.r_[np.inf, cumulative[:-1]], cumulative,
                                np.r_[cumulative[1:], np.inf]])
        choice = candidates.argmin(axis=0)
        parent[y] = choice.astype(np.int8) - 1
        cumulative = diff[y] + candidates[choice, np.arange(w)]
    seam = np.empty(h, np.int32)
    seam[-1] = int(cumulative.argmin())
    for y in range(h-1, 0, -1):
        seam[y-1] = seam[y] + int(parent[y, seam[y]])
    return seam


def build_panorama(paths, height=720):
    if not 2 <= len(paths) <= 20:
        raise core.EngineError("Use between 2 and 20 overlapping landscape sections.")
    images = []
    for path in paths:
        rgb = core.load_rgb(path)
        width = round(rgb.shape[1] * height / rgb.shape[0])
        images.append(cv2.resize(rgb, (width, height), interpolation=cv2.INTER_AREA))
    panorama = images[0].copy()
    cumulative = np.eye(3, dtype=np.float64)
    reports = []
    for index in range(1, len(images)):
        pair, report = register_neighbor(images[index-1], images[index])
        cumulative = cumulative @ pair
        source = images[index]
        corners = np.array([[0, 0, 1], [source.shape[1]-1, 0, 1],
                            [0, height-1, 1], [source.shape[1]-1, height-1, 1]], np.float64)
        transformed = corners @ cumulative.T
        new_width = max(panorama.shape[1], int(np.ceil(transformed[:, 0].max()))+1)
        if new_width > 30000:
            raise core.EngineError("Split routes wider than 30,000 pixels into separate render jobs.")
        warped = cv2.warpAffine(source, cumulative[:2], (new_width, height),
                                 flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REFLECT_101)
        old_width = panorama.shape[1]
        overlap_start = max(0, int(np.ceil(transformed[[0, 2], 0].max())) + 6)
        overlap_end = old_width - 6
        overlap_width = overlap_end - overlap_start
        if overlap_width < 96:
            raise core.EngineError("The continuation has insufficient usable overlap.")
        # Match exposure from corresponding real pixels; cap the correction.
        a = panorama[:, overlap_start:overlap_end]
        b = warped[:, overlap_start:overlap_end]
        offset = np.clip(np.median(a[20:-20].astype(float)-b[20:-20].astype(float), axis=(0, 1)), -12, 12)
        warped = np.clip(warped.astype(np.float32)+offset, 0, 255).astype(np.uint8)
        inner_left = overlap_start + int(overlap_width * .15)
        inner_right = overlap_end - int(overlap_width * .15)
        seam = low_error_seam(panorama[:, inner_left:inner_right], warped[:, inner_left:inner_right]) + inner_left
        x = np.arange(overlap_start, old_width, dtype=np.float32)[None, :]
        # Feather only a narrow spatial seam, once when constructing the world.
        # There is no full-screen time crossfade during video playback.
        weight = np.clip((x-seam[:, None]+10)/20, 0, 1)
        weight = weight * weight * (3-2*weight)
        result = warped
        result[:, :overlap_start] = panorama[:, :overlap_start]
        result[:, overlap_start:old_width] = np.clip(
            panorama[:, overlap_start:].astype(np.float32) * (1-weight[..., None]) +
            warped[:, overlap_start:old_width].astype(np.float32) * weight[..., None], 0, 255).astype(np.uint8)
        panorama = result
        report.update(section=index+1, world_transform=cumulative.tolist(),
                      overlap_start=overlap_start, overlap_end=overlap_end,
                      seam_x_median=round(float(np.median(seam)), 2),
                      exposure_offset=offset.tolist())
        reports.append(report)
    return panorama, {"engine": "MotionForge Train", "version": VERSION,
                       "width": panorama.shape[1], "height": height,
                       "sections": len(images), "joins": reports, "time_crossfades": 0}


class CameraPath:
    """Monotone cubic Hermite path, continuous in position and speed at markers."""
    def __init__(self, keys, duration):
        self.times = np.array([core.number(k["time"], "camera time", 0, duration) for k in keys], float)
        self.values = np.array([core.number(k["u"], "camera u", 0, 1) for k in keys], float)
        if len(keys) < 2 or np.any(np.diff(self.times) <= 0) or np.any(np.diff(self.values) < 0):
            raise core.EngineError("Camera times must increase; camera positions cannot move backward.")
        if self.times[0] != 0 or self.times[-1] != duration:
            raise core.EngineError("Camera keys must begin at 0 and end at the video duration.")
        delta = np.diff(self.values) / np.diff(self.times)
        self.tangents = np.r_[delta[0], np.zeros(len(keys)-2), delta[-1]]
        for i in range(1, len(keys)-1):
            before, after = delta[i-1], delta[i]
            if before > 0 and after > 0:
                self.tangents[i] = 2*before*after/(before+after)

    def at(self, seconds):
        t = float(np.clip(seconds, self.times[0], self.times[-1]))
        i = min(int(np.searchsorted(self.times, t, side="right"))-1, len(self.times)-2)
        i = max(0, i)
        interval = self.times[i+1] - self.times[i]
        p = (t-self.times[i])/interval
        return float((2*p**3-3*p**2+1)*self.values[i] + (p**3-2*p**2+p)*interval*self.tangents[i]
                     + (-2*p**3+3*p**2)*self.values[i+1] + (p**3-p**2)*interval*self.tangents[i+1])


class WindowView:
    def __init__(self, panorama, width, height, keys, duration, foreground=True, window=True):
        self.width, self.height = width, height
        if panorama.shape[0] != height:
            factor = height/panorama.shape[0]
            panorama = cv2.resize(panorama, (round(panorama.shape[1]*factor), height), interpolation=cv2.INTER_CUBIC)
        if panorama.shape[1] <= width+8:
            raise core.EngineError("Panorama must be wider than the video frame.")
        self.panorama = panorama
        self.distance = panorama.shape[1] - width - 4
        self.path = CameraPath(keys, duration)
        self.yy, self.xx = np.mgrid[:height, :width].astype(np.float32)
        self.foreground = foreground
        self.window = window
        # The close verge uses repeated grass texture only. Distant geography
        # traverses the joined panorama once and never loops or changes by fade.
        self.verge_height = max(24, round(height*.12))
        self.verge = cv2.GaussianBlur(panorama[-self.verge_height:], (17, 1), 0)
        self.verge_y, self.verge_x = np.mgrid[:self.verge_height, :width].astype(np.float32)
        self.verge_alpha = np.linspace(0, .88, self.verge_height, dtype=np.float32)[:, None, None] ** 1.4
        mask = Image.new("L", (width, height), 0)
        draw = ImageDraw.Draw(mask)
        border = max(12, round(height*.027))
        self.border = border
        draw.rounded_rectangle((border, border, width-border-1, height-border*2-1),
                               radius=round(height*.055), fill=255)
        self.mask = np.asarray(mask).astype(np.float32)[..., None]/255
        metal = np.zeros((height, width, 3), np.float32)
        metal[:] = (21, 27, 30)
        for row in range(height-border*2, height):
            p = (row-(height-border*2))/max(1,border*2)
            metal[row] = np.array([42, 47, 49]) * (.65 + .5*math.sin(math.pi*p))
        # Fine bevel around a fixed train window; no burned-in text or controls.
        rim = Image.fromarray(metal.astype(np.uint8))
        rd = ImageDraw.Draw(rim)
        rd.rounded_rectangle((border-3, border-3, width-border+2, height-border*2+2),
                             radius=round(height*.055)+3, outline=(92, 99, 97), width=3)
        self.metal = np.asarray(rim).astype(np.float32)
        stripe = np.exp(-((self.xx/self.width + self.yy/self.height*.22 - .16)/.075)**2)
        self.reflection = (stripe*.014)[..., None].astype(np.float32)

    def render(self, seconds):
        offset = 2 + self.distance * self.path.at(seconds)
        vibration = .50*math.sin(seconds*19) + .23*math.sin(seconds*31)
        view = cv2.remap(self.panorama, self.xx+offset, self.yy+vibration, cv2.INTER_LINEAR,
                          borderMode=cv2.BORDER_REFLECT_101).astype(np.float32)
        if self.foreground:
            close_x = (self.verge_x+offset*4.5+seconds*38) % self.verge.shape[1]
            close = cv2.remap(self.verge, close_x, self.verge_y, cv2.INTER_LINEAR,
                               borderMode=cv2.BORDER_WRAP).astype(np.float32)
            view[-self.verge_height:] *= 1-self.verge_alpha
            view[-self.verge_height:] += close*self.verge_alpha
        if self.window:
            view = view*(1-self.reflection) + np.array([205, 220, 229], np.float32)*self.reflection
            view = view*self.mask + self.metal*(1-self.mask)
        return np.clip(view, 0, 255).astype(np.uint8)


def read_project(path):
    path = Path(path).resolve()
    try:
        project = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise core.EngineError(f"Cannot read train project: {exc}") from exc
    if not isinstance(project, dict):
        raise core.EngineError("Train project root must be an object.")
    return project, path.parent


def build(project_path):
    project, base = read_project(project_path)
    width, height, fps = core.validate_video(project.get("width",1280), project.get("height",720), project.get("fps",24))
    paths = [core.resolve_path(p, base) for p in project["sections"]]
    panorama, report = build_panorama(paths, height)
    output = core.resolve_path(project["panorama"], base)
    output.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(panorama).save(output, quality=95, subsampling=0, optimize=True)
    output.with_suffix(".registration.json").write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return report


def render(project_path, output, threads=4):
    started = time.perf_counter()
    project, base = read_project(project_path)
    width, height, fps = core.validate_video(project.get("width",1280), project.get("height",720), project.get("fps",24))
    duration = core.number(project.get("seconds",84), "seconds", .1, 600)
    cv2.setNumThreads(int(core.number(threads, "threads", 1, 8)))
    panorama = core.load_rgb(core.resolve_path(project["panorama"], base))
    keys = project.get("camera_keys", [{"time":0,"u":0},{"time":duration,"u":1}])
    scene = WindowView(panorama, width, height, keys, duration,
                       project.get("foreground",True), project.get("window",True))
    count = max(2, round(duration*fps))
    writer = core.VideoWriter(output, width, height, fps, count, threads)
    success = False
    core.log(f"Continuous train view: {count} frames, {duration}s, {width}x{height}")
    try:
        for i in range(count):
            writer.write(scene.render(i/fps))
            if i % (fps*10) == 0:
                core.log(f"  {i//fps}/{duration:g} seconds")
        success = True
    finally:
        writer.close(success)
    report = {"engine":"MotionForge Train", "version":VERSION, "title":project.get("title","Train view"),
              "width":width,"height":height,"fps":fps,"frames":count,"duration_seconds":count/fps,
              "world_width":scene.panorama.shape[1],"sections":len(project.get("sections",[])),
              "camera_keys":keys,"time_crossfades":0,"landscape_loops":0,
              "near_verge_texture_loops":bool(project.get("foreground",True)),
              "render_seconds":round(time.perf_counter()-started,3),
              "peak_renderer_rss_mb":round(core.peak_rss_mb() or 0,2),
              "peak_encoder_rss_mb":round(core.child_peak_rss_mb() or 0,2),
              "video_bytes":Path(output).stat().st_size}
    Path(output).with_suffix(".report.json").write_text(json.dumps(report,indent=2,ensure_ascii=False)+"\n", encoding="utf-8")
    print(json.dumps(report,indent=2,ensure_ascii=False))
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command",required=True)
    prep = sub.add_parser("build")
    prep.add_argument("project",type=Path)
    run = sub.add_parser("render")
    run.add_argument("project",type=Path)
    run.add_argument("--output",type=Path,required=True)
    run.add_argument("--threads",type=int,default=4)
    args = parser.parse_args(argv)
    try:
        if args.command == "build":build(args.project)
        else:render(args.project,args.output,args.threads)
        return 0
    except (core.EngineError,OSError,ValueError,KeyError,cv2.error) as exc:
        core.log(f"Error: {exc}")
        return 2
    except KeyboardInterrupt:
        core.log("Cancelled; incomplete video removed.")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
