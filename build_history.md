# whisperTRT-Enhanced — Build History & Changelog
 
> **Format:** [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) · **Versioning:** [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
 
---
 
## Table of Contents
 
1. [Unreleased](#unreleased)
   - [2026-05-24 — Integration Test & Runtime Validation](#2026-05-24--integration-test--runtime-validation)
   - [2026-05-21 — PyTorch OSS Base Image Experiment](#2026-05-21--pytorch-oss-base-image-experiment)
   - [2026-05-11 — Docker Workflow Refinement](#2026-05-11--docker-workflow-refinement)
   - [2026-05-09 — Production Dockerfile & Build Script](#2026-05-09--production-dockerfile--build-script)
   - [2026-05-08 — End-to-End Container Setup Experiment](#2026-05-08--end-to-end-container-setup-experiment)
2. [v0.0.1 — 2026-05-02](#v001--2026-05-02)
---
 
## [Unreleased]
 
---
 
### 2026-05-24 — Integration Test & Runtime Validation
 
**Scope:** Full stack smoke test — build, launch, TRT engine init, audio, and live transcription.
 
#### Summary of Changes
 
| Area | Status | Notes |
|---|---|---|
| Docker image build | ✅ Success | Built from local Dockerfile without errors |
| Container launch | ✅ Success | GPU passthrough confirmed |
| Silero VAD download | ✅ Success | Downloaded to cache on first run |
| Whisper `base.en` model | ✅ Success | ~139 MB downloaded successfully |
| TensorRT engine init | ⚠️ Warning | Default stream warning logged (performance note only) |
| Live transcription | ❌ Failed | `UnboundLocalError` — no ReSpeaker device found |
| Microphone access | ❌ Failed | Host mic in use by another application |
 
#### Test Environment
 
- **Virtualenv:** Activated before running build script
- **Build command:** `sudo bash docker/gpu-build.sh`
- **Image produced:** `whisper-trt-enhanced:latest`
- **GPU passthrough:** `--gpus all`
- **Model backend:** `whisper_trt` with `base.en`
#### Detailed Observations
 
**Build Phase**
 
The Docker image built successfully from the local Dockerfile. All dependency installation steps completed without error. The image was tagged `whisper-trt-enhanced:latest`.
 
**Runtime — VAD & Model Download**
 
On container start, Silero VAD was downloaded to the cache directory. Whisper's `base.en` model (~139 MB) was also fetched and cached successfully.
 
**Runtime — TensorRT Warning**
 
TRT logged a warning about using the default CUDA stream. This is a performance advisory only and does not indicate a functional failure. TensorRT engine build proceeded.
 
**Runtime — Audio & Microphone Failure**
 
ALSA and JACK errors appeared in the log. The live transcription example raised:
 
```
UnboundLocalError: local variable 'device_index' referenced before assignment
```
 
Root cause: `find_respeaker_audio_device_index()` iterates available audio devices and sets `device_index` only if a ReSpeaker device is found. Because the host microphone was in use by another application at the time, the device was not accessible inside the container, the function found nothing, and `device_index` was never assigned.
 
> **Key distinction:** The microphone was confirmed functional on the host — it was simply locked by another application during this test run.
 
#### Root Cause Analysis
 
| Issue | Root Cause | Impact |
|---|---|---|
| `UnboundLocalError` in device discovery | Mic locked by host process; no ReSpeaker found | Live transcription could not start |
| ALSA/JACK errors | Audio device not free when container attached | Device open failed |
| Cache written to `/root/.cache` | Build run with `sudo`; cache path resolves to root's home | Host cache dirs not reused on non-root runs |
 
#### Recommendations & Action Items
 
**Microphone Access**
 
For reliable audio access inside Docker, one of the following is required:
 
- Free the host microphone before starting the container (close any application holding it open).
- Map the host PulseAudio or PipeWire socket into the container:
  ```bash
  -v /run/user/1000/pulse/native:/run/pulse/native \
  -e PULSE_SERVER=unix:/run/pulse/native
  ```
- Ensure the container was started with `--device /dev/snd --group-add audio` (already included in `gpu-build.sh`).
> ⚠️ **Critical:** Audio device permissions **must be set at container creation time**. They cannot be added after attaching to a running container without restarting it.
 
**Cache & Storage**
 
Running `gpu-build.sh` with `sudo` writes caches to `/root/.cache` instead of the user's home directory. Bind-mount host cache directories before starting the container to ensure persistence and avoid re-downloads:
 
```bash
-v $HOME/.cache/whisper:/root/.cache/whisper \
-v $HOME/.cache/whisper_trt:/root/.cache/whisper_trt
```
 
**Next Steps**
 
1. Retry the test with the host microphone freed (no competing applications).
2. Alternatively, configure PulseAudio/PipeWire socket mapping for persistent audio forwarding.
3. Consider running `gpu-build.sh` without `sudo` if cache path ownership causes issues.
---
 
### 2026-05-21 — PyTorch OSS Base Image Experiment
 
**Scope:** Evaluation of `pytorch/pytorch:2.11.0-cuda12.8-cudnn9-devel` as a drop-in replacement for the NVIDIA NGC base image.
 
**Motivation:** Reduce image pull times by leveraging locally cached Docker layers from the OSS PyTorch image, avoiding repeated large downloads of the NGC image.
 
#### Changes Attempted
 
- Replaced base image from `nvcr.io/nvidia/pytorch:25.02-py3` → `pytorch/pytorch:2.11.0-cuda12.8-cudnn9-devel`
- Added `--break-system-packages` to all pip install commands
- Removed `--no-build-isolation` flag from pip commands
#### Build Issues Encountered
 
**Issue 1 — PEP 668 Compliance Error**
 
The OSS PyTorch image enforces the `externally-managed-environment` restriction, which blocks system-wide pip installs by default.
 
- **Resolution:** Added `--break-system-packages` to all `pip install` commands.
**Issue 2 — Build Backend Failure**
 
Using `--no-build-isolation` with pre-built wheel packages caused `wheel_stub.buildapi` import errors, preventing package installation.
 
- **Resolution:** Removed the `--no-build-isolation` flag and allowed standard wheel-based installation.
**Issue 3 — TensorRT Installation Deadlock (Build Abandoned)**
 
During TensorRT dependency resolution, pip stalled attempting to resolve `tensorrt_cu13_libs==10.16.1.11`. The process hung indefinitely and was interrupted (exit code 130).
 
- **Root Cause:** The OSS PyTorch image does not bundle TensorRT. pip attempted to download and build large CUDA 13-variant TensorRT binary packages, which require additional build infrastructure and have extended resolution times.
- **Resolution:** Build abandoned. See recommendation below.
#### Key Findings
 
| Factor | NGC Image (`nvcr.io/nvidia/pytorch`) | OSS Image (`pytorch/pytorch`) |
|---|---|---|
| TensorRT | Pre-installed and configured | Not included; must install via pip |
| CUDA environment | Optimized, purpose-built | General purpose |
| Initial pull size | Large (requires download) | Locally cached (faster start) |
| TensorRT install overhead | None | Very high — large binaries, complex resolution |
| Suitability for this project | ✅ Recommended | ❌ Not recommended |
 
#### Recommendation
 
**Revert to `nvcr.io/nvidia/pytorch:25.02-py3`.** The caching benefit of the OSS image is completely negated by the complexity and time required to install TensorRT from scratch. The NGC image is purpose-built with TensorRT bundled, has a pre-optimized CUDA environment, and installs cleanly with this project's Dockerfile.
 
For teams concerned about repeated large pulls, the recommended approach is to pull the NGC image once and create a local mirror or registry cache — not to substitute a different base image.
 
---
 
### 2026-05-11 — Docker Workflow Refinement
 
**Scope:** Improved developer experience — local source builds, automatic live transcription launch, and repository-aware path resolution.
 
#### Dockerfile Updates
 
| Change | Detail |
|---|---|
| Runtime dependencies added | `openai-whisper`, `pyaudio`, `onnxruntime`, `onnx_graphsurgeon` |
| Local source install | Copies local `torch2trt` and `whisper_trt` source into the image; installs in editable (`-e`) mode |
| Default entrypoint | Now runs `whisper_trt/examples/live_transcription.py` instead of dropping into a shell |
| Environment variables | Pre-sets `base.en` model and `whisper_trt` backend as runtime defaults |
 
**Editable install rationale:** Installing local sources in editable mode means changes to the workspace source are reflected inside the container immediately when the repository is mounted, without requiring a full image rebuild.
 
#### gpu-build.sh Updates
 
| Change | Detail |
|---|---|
| Repository root resolution | Script resolves workspace root automatically from its own location — no hardcoded paths |
| Build context | Builds from workspace root so all local source changes are included in the image |
| Repository mount | Mounts repo into `/workspace` for interactive development access at runtime |
| Auto-launch | Starts live transcription directly with `base.en` and `whisper_trt` backend |
 
#### Usage
 
```bash
# From the repository root
chmod +x docker/gpu-build.sh
./docker/gpu-build.sh
 
# Restart a stopped container (preserves state)
docker start -ai whisper-trt-enhanced-dev
 
# Clean up container
docker rm whisper-trt-enhanced-dev
```
 
---
 
### 2026-05-09 — Production Dockerfile & Build Script
 
**Scope:** First production-ready Docker configuration, incorporating all lessons learned from the 2026-05-08 experiment.
 
#### Dockerfile
 
**Base Image**
 
```
nvcr.io/nvidia/pytorch:25.02-py3
```
 
TensorRT and CUDA 12.8 pre-installed. Selected over alternatives after the dependency experiments documented in the 2026-05-08 entry.
 
**System Dependencies**
 
```
build-essential  cmake  libssl-dev  portaudio19-dev  python3-dev  git  wget
```
 
`portaudio19-dev` and `python3-dev` are required for `pyaudio` compilation.
 
**Key Installation Details**
 
| Package | Version / Flag | Reason |
|---|---|---|
| `setuptools` | Pinned to `70.0.0` | Prevents build isolation failures encountered in experiments |
| `openai-whisper` | `20240927` with `--no-build-isolation` | Resolves metadata/wheel build failures specific to this version |
| `pyaudio` | System portaudio pre-installed | Avoids runtime audio device errors |
| `onnxruntime_gpu` | Latest compatible | TensorRT inference dependency |
| `onnx_graphsurgeon` | Latest compatible | TensorRT graph optimization dependency |
| `torch2trt` | Cloned, then installed | Dependency of `whisper_trt` |
| `whisper_trt` | Cloned, then installed | Core inference library |
 
**Additional Steps**
 
- CUDA availability verification (`torch.cuda.is_available()`) — fails fast if the GPU environment is misconfigured.
- Pre-creates `/root/.cache/whisper` and `/root/.cache/whisper_trt` to ensure bind-mount targets exist.
- Cleans apt cache and removes temporary build directories to reduce final image size.
#### gpu-build.sh
 
**Host pre-flight**
 
Creates `~/.cache/whisper` and `~/.cache/whisper_trt` on the host before launch to ensure bind mounts resolve correctly.
 
**Full container launch flags**
 
```bash
docker run \
  --gpus all \
  --ipc=host \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  --device /dev/snd \
  --group-add audio \
  -v $HOME/.cache/whisper:/root/.cache/whisper \
  -v $HOME/.cache/whisper_trt:/root/.cache/whisper_trt \
  --name whisper-trt-enhanced-dev \
  whisper-trt-enhanced:latest
```
 
| Flag | Purpose |
|---|---|
| `--gpus all` | Full GPU passthrough for CUDA / TensorRT |
| `--ipc=host` | Shared memory for PyTorch dataloaders |
| `--ulimit memlock=-1` | Unlimited locked memory (required for GPU memory operations) |
| `--ulimit stack=67108864` | 64 MB stack size for deep model inference |
| `--device /dev/snd` | Passes host sound device into container |
| `--group-add audio` | Grants container audio group permissions |
| `-v ... whisper` | Bind-mounts host Whisper model cache |
| `-v ... whisper_trt` | Bind-mounts host whisper_trt / TRT engine cache |
| `--name` | Named container for easy restart and management |
 
**Convenience commands provided in script output**
 
```bash
# Restart container (state preserved)
docker start -ai whisper-trt-enhanced-dev
 
# Remove container
docker rm whisper-trt-enhanced-dev
 
# Save current container state to a new image
docker commit whisper-trt-enhanced-dev whisper-trt-enhanced:dev-v1
```
 
#### Key Improvements Over Experiment (2026-05-08)
 
| Problem (2026-05-08) | Fix (2026-05-09) |
|---|---|
| Build isolation failures | `setuptools` pinned to `70.0.0` |
| Audio device errors at runtime | `--device /dev/snd --group-add audio` in launch flags |
| Model cache lost on container removal | Host bind mounts for `/root/.cache/whisper` and `/root/.cache/whisper_trt` |
| No CUDA sanity check | Explicit `torch.cuda.is_available()` verification step in Dockerfile |
| Large ephemeral build artifacts | `apt` cache cleared; temp dirs removed in same RUN layer |
 
---
 
### 2026-05-08 — End-to-End Container Setup Experiment
 
**Scope:** Manual, iterative dependency resolution from a clean NGC PyTorch container to a working whisper_trt runtime. All findings fed directly into the 2026-05-09 production Dockerfile.
 
#### 1. Base Container Launch
 
```bash
docker run \
  --gpus all \
  --ipc=host \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  -it nvcr.io/nvidia/pytorch:25.02-py3 /bin/bash
```
 
CUDA verified inside container:
 
```python
python -c "import torch; print(torch.cuda.is_available())"
# True
```
 
#### 2. Whisper Installation — Issue & Resolution
 
**Symptom:** `pip install openai-whisper==20240927` failed during build metadata / wheel preparation.
 
**Resolution steps:**
 
1. Upgraded packaging tools inside the container.
2. Pinned `setuptools==70.0.0` to avoid version-related build isolation conflicts.
3. Installed with non-isolated build:
```bash
pip install setuptools==70.0.0
pip install --no-build-isolation openai-whisper==20240927
```
 
#### 3. whisper_trt Dependency Chain — Iterative Resolution
 
Each missing dependency was discovered at runtime and resolved in sequence:
 
| Step | Missing Dependency | Resolution |
|---|---|---|
| 1 | `torch2trt` | Cloned repo, ran `python setup.py install` |
| 2 | `pyaudio` | Installed system libs first (`portaudio19-dev python3-dev`), then `pip install pyaudio` |
| 3 | `onnxruntime` | Installed `onnxruntime_gpu` |
| 4 | `onnx_graphsurgeon` | Installed `onnx_graphsurgeon` |
 
After step 4, TensorRT runtime started successfully and model assets began downloading and building.
 
> **Note:** `setup.py install` was used for compatibility during the experiment. It is deprecated. A `pip install .` based flow is preferred for all future work.
 
#### 4. Critical Runtime Lesson — Microphone Access
 
**Symptom:** Live transcription failed with ALSA / device access errors.
 
**Root Cause:** The container was launched without audio device passthrough flags. The container had no visibility into `/dev/snd`.
 
**Lesson:** The container must be launched with:
 
```bash
--device /dev/snd --group-add audio
```
 
Depending on host audio stack, PulseAudio or PipeWire socket forwarding may also be required. This **cannot be fixed after container creation** without restarting.
 
#### 5. Critical Storage Lesson — Model Cache Mounts
 
**Symptom:** Whisper model weights and TensorRT engine artifacts were downloaded into the container's writable layer.
 
**Consequences:**
- Artifacts are lost permanently when the container is removed.
- Container image size grows unnecessarily with each run.
- Models are re-downloaded from scratch on every fresh container start.
**Resolution:** Always bind-mount cache directories at container start time:
 
```bash
-v $HOME/.cache/whisper:/root/.cache/whisper \
-v $HOME/.cache/whisper_trt:/root/.cache/whisper_trt
```
 
#### 6. Recommended Improved Launch Command (post-experiment)
 
```bash
docker run \
  --gpus all \
  --ipc=host \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  --device /dev/snd \
  --group-add audio \
  -v $HOME/.cache/whisper:/root/.cache/whisper \
  -v $HOME/.cache/whisper_trt:/root/.cache/whisper_trt \
  -it nvcr.io/nvidia/pytorch:25.02-py3 /bin/bash
```
 
---
 
## [v0.0.1] — 2026-05-02
 
**Initial release:** Comprehensive installation guide for the whisperTRT-Enhanced project.
 
### Added
 
- Full prerequisites section with hardware and software requirements.
- Manual installation steps for PyTorch, `torch2trt`, and `whisper_trt`.
- Docker-based setup guide using NVIDIA NGC PyTorch containers.
- Troubleshooting reference for common failure modes.
- Links to official documentation and resources.
### Prerequisites
 
| Requirement | Minimum Version / Notes |
|---|---|
| Python | `>= 3.12` |
| NVIDIA GPU | Compute capability `>= 7.0` |
| CUDA Toolkit | `12.8+`, must match PyTorch and TensorRT versions |
| System deps | `build-essential`, `cmake`, `libssl-dev` |
| Disk space | ~5–10 GB |
 
**Key links:**
 
- [PyTorch with CUDA installation](https://pytorch.org/get-started/locally/)
- [TensorRT installation guide](https://docs.nvidia.com/deeplearning/tensorrt/install-guide/index.html)
- [uv package manager](https://docs.astral.sh/uv/getting-started/installation/)
- [NGC PyTorch containers](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/pytorch)
### Manual Installation
 
**Step 1 — Install PyTorch with CUDA**
 
```bash
uv pip install torch torchvision torchaudio \
  --index-url https://download.pytorch.org/whl/cu128
 
# Verify
python -c "import torch; print(torch.cuda.is_available())"
```
 
**Step 2 — Clone repositories**
 
```bash
git clone https://github.com/NVIDIA-AI-IOT/whisper_trt.git
git clone https://github.com/NVIDIA-AI-IOT/torch2trt.git
```
 
**Step 3 — Install torch2trt**
 
```bash
cd torch2trt
uv run setup.py install
 
# Optional: build C++ plugins
cmake -B build . && cmake --build build --target install && sudo ldconfig
```
 
If TensorRT is missing, follow the [NVIDIA TensorRT install guide](https://docs.nvidia.com/deeplearning/tensorrt/install-guide/index.html) before proceeding.
 
**Step 4 — Install whisper_trt**
 
```bash
cd ../whisper_trt
 
# openai-whisper version 20240927 is required
# See: https://github.com/NVIDIA-AI-IOT/whisper_trt/issues/12#issuecomment-2459897517
uv pip install openai-whisper==20240927
uv run setup.py install
```
 
**Step 5 — Verify with an example**
 
```bash
python examples/transcribe.py tiny.en <audio_file>
```
 
### Docker Setup (Recommended)
 
Docker is the preferred installation method for a reproducible, pre-configured environment.
 
**Pull the NGC image:**
 
```bash
docker pull nvcr.io/nvidia/pytorch:25.02-py3
```
 
**Run the container:**
 
```bash
docker run --gpus all -it nvcr.io/nvidia/pytorch:25.02-py3 /bin/bash
```
 
**Install inside the container:**
 
```bash
pip install openai-whisper==20240927
git clone https://github.com/NVIDIA-AI-IOT/whisper_trt.git
cd whisper_trt && python setup.py install
```
 
### Troubleshooting Reference
 
| Symptom | Likely Cause | Resolution |
|---|---|---|
| `TensorRT not found` | TRT libs not on `LD_LIBRARY_PATH` | Follow NVIDIA guide; add TRT lib path to env |
| Version mismatch errors | Incompatible CUDA / PyTorch / TRT | Ensure all three share the same CUDA major version |
| Build failures | `cmake` or CUDA not in `PATH` | Verify with `which cmake` and `nvcc --version` |
| Slow first run | TRT engine building on first inference | Expected — engine is cached after first build |
| Jetson-specific failures | Desktop TRT package used on Jetson | Use JetPack containers; do not mix desktop and Jetson TRT |
 
---
 
*Maintained by the whisperTRT-Enhanced team. For issues, see the project repository.*