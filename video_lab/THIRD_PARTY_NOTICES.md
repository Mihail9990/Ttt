# Components and provenance

## Original engine

MotionForge CPU 0.1.0 and MotionForge Studio 0.2.0 source code are supplied under
the MIT License in LICENSE. The original engine is retained as motionforge.py.

## Relative depth model

- Depth Anything V2 Small, original authors and contributors:
  https://github.com/DepthAnything/Depth-Anything-V2
- Original weights: https://huggingface.co/depth-anything/Depth-Anything-V2-Small
- ONNX INT8 conversion by ONNX Community / Xenova:
  https://huggingface.co/onnx-community/depth-anything-v2-small
- Revision: 4472b7362082ad9968fee890ca0f1e5aca36b93d
- SHA-256: fcf51f1b230362b28690bb9d1809bf0431f29cad20534e3f589bd7285547f20d
- Apache-2.0 license, included in models/LICENSE-APACHE-2.0.txt.
- The unchanged weight file is downloaded separately, not committed to Git.

## Example artwork

The forest background and kitten walking atlas were created for this project
with ChatGPT's built-in image-generation tool on 2026-11-14. Exact prompts are
in prompts/. No third-party photograph or pre-existing named character was
used as a reference. The atlas retains transparency. JPEG/WebP versions are
used for repository size; their asset hashes are recorded in assets/manifest.json.
These images were created externally before the local video render.

## Runtime dependencies

NumPy, Pillow, OpenCV and ONNX Runtime retain their respective licenses and
are installed separately. FFmpeg is an external executable, not redistributed
here. Assets, runtime dependencies and model weights have their own terms;
the source-code MIT License does not override them.
