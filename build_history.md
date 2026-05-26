# whisperTRT-Enhanced — Build History & Changelog
 
> **Format:** [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) · **Versioning:** [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
 
---
 
## Table of Contents
 
1. [Unreleased](#unreleased)
   - [2026-05-26 — Audio Device Detection Overhaul & Container Name Conflict](#2026-05-26--audio-device-detection-overhaul--container-name-conflict)
   - [2026-05-24 — Integration Test & Runtime Validation](#2026-05-24--integration-test--runtime-validation)
   - [2026-05-21 — PyTorch OSS Base Image Experiment](#2026-05-21--pytorch-oss-base-image-experiment)
   - [2026-05-11 — Docker Workflow Refinement](#2026-05-11--docker-workflow-refinement)
   - [2026-05-09 — Production Dockerfile & Build Script](#2026-05-09--production-dockerfile--build-script)
   - [2026-05-08 — End-to-End Container Setup Experiment](#2026-05-08--end-to-end-container-setup-experiment)
2. [v0.0.1 — 2026-05-02](#v001--2026-05-02)
---
 
## [Unreleased]
 
---
 
### 2026-05-26 — Audio Device Detection Overhaul & Container Name Conflict
 
**Scope:** Root-cause analysis and full fix for the `UnboundLocalError` introduced in 2026-05-24. Robustified audio device discovery, added an environment-variable override, added a `--list-devices` CLI flag, and updated `gpu-build.sh` to forward the override into the container. Build succeeded; `docker run` exited with code 125 (container name conflict — not tested today; scheduled for 2026-05-27).
 
#### Summary of Changes
 
| Area | Status | Notes |
|---|---|---|
| Docker image build | ✅ Success | Rebuilt cleanly from local Dockerfile |
| `find_respeaker_audio_device_index()` fix | ✅ Applied | `UnboundLocalError` eliminated; broadened matching; fallback added |
| `AUDIO_DEVICE_INDEX` env override | ✅ Applied | Bypass detection entirely via env var |
| `--list-devices` CLI flag | ✅ Applied | Enumerate devices and exit without starting transcription |
| `gpu-build.sh` env passthrough | ✅ Applied | `AUDIO_DEVICE_INDEX` forwarded to `docker run -e` if set on host |
| Container launch (`docker run`) | ❌ Exit 125 | Name conflict — `whisper-trt-enhanced-dev` still exists from 2026-05-24 |
| Live transcription end-to-end | ⏳ Deferred | Will test 2026-05-27 after removing stale container |
 
---
 
#### Root-Cause Analysis — `UnboundLocalError`
 
The crash from 2026-05-24 was reproduced and diagnosed precisely. The original implementation of `find_respeaker_audio_device_index()` in `whisper_trt/examples/live_transcription.py` was:
 
```python
def find_respeaker_audio_device_index():
    p = pyaudio.PyAudio()
    info = p.get_host_api_info_by_index(0)
    num_devices = info.get("deviceCount")
 
    for i in range(num_devices):
        device_info = p.get_device_info_by_host_api_device_index(0, i)
        if "respeaker" in device_info.get("name").lower():
            device_index = i   # ← only assigned inside this branch
 
    return device_index        # ← UnboundLocalError if no match
```
 
**Two separate bugs:**
 
1. **`device_index` never initialised before the loop.** Python requires a variable to be assigned before it is read. Because `device_index` is only written inside the `if "respeaker"` branch, any run where no device name contains `"respeaker"` leaves it completely unbound. `return device_index` then raises `UnboundLocalError`.
 
2. **`PyAudio` instance `p` is never terminated.** `p.terminate()` was absent, leaking the underlying PortAudio session on every call.
 
**Why a standard headset triggers this:** A standard USB headset or built-in microphone is enumerated by ALSA/PortAudio under names such as `"USB Audio Device"`, `"HDA Intel PCH"`, `"pulse"`, or `"default"` — none of which contain the substring `"respeaker"`. The branch is therefore never entered, `device_index` stays unbound, and the crash follows.
 
---
 
#### Fix Applied — `find_respeaker_audio_device_index()` (full rewrite)
 
File: `whisper_trt/examples/live_transcription.py`
 
**New keyword list** defined at module level (checked against the lower-cased device name; first match wins):
 
```python
_AUDIO_MATCH_KEYWORDS = (
    "respeaker", "usb", "microphone", "mic",
    "headset", "headphone", "default", "input",
)
```
 
**Resolution order inside the function:**
 
| Priority | Source | Behaviour |
|---|---|---|
| 1 | `AUDIO_DEVICE_INDEX` env var | Parse as `int` and return immediately; raise `RuntimeError` if not a valid integer |
| 2 | Keyword match | First input device (`maxInputChannels > 0`) whose name contains any keyword |
| 3 | Fallback | First device with `maxInputChannels > 0`, regardless of name |
| 4 | Failure | `RuntimeError` printing a numbered list of all input devices with index, name, and channel count |
 
**Additional fixes in the same rewrite:**
- `device_index = None` and `first_input_index = None` initialised before the loop — `UnboundLocalError` is impossible.
- `p.terminate()` called in a `finally` block — PortAudio session is always released.
- `input_device_descriptions` list built during the scan and included verbatim in the `RuntimeError` message so the user can immediately see which indices are valid.
 
**New function in full:**
 
```python
def find_respeaker_audio_device_index():
    """Return the best matching audio input device index.
 
    Resolution order
    ----------------
    1. AUDIO_DEVICE_INDEX environment variable (integer override).
    2. First input device whose name contains a keyword from
       _AUDIO_MATCH_KEYWORDS (case-insensitive).
    3. First device that reports maxInputChannels > 0.
    4. RuntimeError listing every available input device.
    """
    env_val = os.environ.get("AUDIO_DEVICE_INDEX")
    if env_val is not None:
        try:
            return int(env_val)
        except ValueError:
            raise RuntimeError(
                f"AUDIO_DEVICE_INDEX='{env_val}' is not a valid integer."
            )
 
    p = pyaudio.PyAudio()
    try:
        info = p.get_host_api_info_by_index(0)
        num_devices = info.get("deviceCount")
 
        device_index = None        # explicit keyword match
        first_input_index = None   # fallback: first device with input channels
        input_device_descriptions = []
 
        for i in range(num_devices):
            device_info = p.get_device_info_by_host_api_device_index(0, i)
            name = device_info.get("name", "")
            max_input_ch = int(device_info.get("maxInputChannels", 0))
 
            if max_input_ch > 0:
                input_device_descriptions.append(
                    f"  [{i}] {name!r}  (inputs: {max_input_ch})"
                )
                if first_input_index is None:
                    first_input_index = i
                if device_index is None:
                    if any(kw in name.lower() for kw in _AUDIO_MATCH_KEYWORDS):
                        device_index = i
 
        # Fallback: any device that has at least one input channel
        if device_index is None:
            device_index = first_input_index
 
        if device_index is None:
            device_list = "\n".join(input_device_descriptions) or "  (none found)"
            raise RuntimeError(
                "No audio input device could be found.\n"
                "Available input devices:\n"
                f"{device_list}\n\n"
                "Set the AUDIO_DEVICE_INDEX environment variable to the desired "
                "device index, e.g.:\n"
                "  docker run -e AUDIO_DEVICE_INDEX=0 ..."
            )
 
        return device_index
    finally:
        p.terminate()
```
 
---
 
#### New Feature — `AUDIO_DEVICE_INDEX` Environment Variable Override
 
When the automatic detection still fails (e.g. unusual device name, multi-sound-card system, ALSA enumeration order changes between runs), the user can hard-pin the device index at container start without rebuilding or editing source:
 
```bash
# Force device index 0
docker run -e AUDIO_DEVICE_INDEX=0 ... python whisper_trt/examples/live_transcription.py base.en
 
# Via gpu-build.sh on the host (see below)
AUDIO_DEVICE_INDEX=0 sudo bash docker/gpu-build.sh
```
 
The env var is read at the very top of `find_respeaker_audio_device_index()`, before PyAudio is even initialised. An invalid (non-integer) value raises an immediate `RuntimeError` with a clear message rather than producing a confusing downstream crash.
 
---
 
#### New Feature — `--list-devices` CLI Flag
 
A `--list-devices` flag was added to the `argparse` block in `live_transcription.py`. It enumerates every PortAudio input device and exits cleanly — no model is loaded, no TRT engine is touched.
 
```bash
# Run inside the container
python whisper_trt/examples/live_transcription.py --list-devices
 
# Or via docker run directly (no GPU or audio stream needed)
docker run --rm \
    --device /dev/snd \
    --group-add audio \
    whisper-trt-enhanced:latest \
    python whisper_trt/examples/live_transcription.py --list-devices
```
 
Example output:
 
```
Available PyAudio input devices:
  [0] 'USB Audio Device: - (hw:1,0)'  (inputs: 2)
  [1] 'HDA Intel PCH: ALC256 Analog (hw:0,0)'  (inputs: 2)
  [2] 'default'  (inputs: 32)
  [3] 'pulse'  (inputs: 32)
```
 
Use the index shown here with `AUDIO_DEVICE_INDEX` or `-e AUDIO_DEVICE_INDEX=<n>` in `docker run`.
 
The `model` positional argument was changed to `nargs="?"` so `--list-devices` can be invoked alone without supplying a model name. If `--list-devices` is not passed and `model` is omitted, `argparse` exits with a clear error.
 
---
 
#### `gpu-build.sh` Update — `AUDIO_DEVICE_INDEX` Passthrough
 
File: `docker/gpu-build.sh`
 
The following block was inserted immediately before `docker run`:
 
```bash
# Optionally forward AUDIO_DEVICE_INDEX so the host can override device
# selection without rebuilding the image, e.g.:
#   AUDIO_DEVICE_INDEX=1 sudo bash docker/gpu-build.sh
AUDIO_DEVICE_INDEX_ARG=()
if [ -n "${AUDIO_DEVICE_INDEX+x}" ]; then
    AUDIO_DEVICE_INDEX_ARG=(-e "AUDIO_DEVICE_INDEX=${AUDIO_DEVICE_INDEX}")
fi
```
 
And `"${AUDIO_DEVICE_INDEX_ARG[@]}"` was spliced into the `docker run` argument list:
 
```bash
docker run \
    --gpus all \
    ...
    --name "${CONTAINER_NAME}-dev" \
    "${AUDIO_DEVICE_INDEX_ARG[@]}" \   # ← injected here; empty when not set
    -it \
    "${IMAGE_NAME}" \
    python whisper_trt/examples/live_transcription.py "${MODEL_NAME}" --backend "${BACKEND_NAME}"
```
 
The `${VAR+x}` test (rather than `-n "${VAR}"`) correctly distinguishes between "variable is unset" and "variable is set but empty", so passing `AUDIO_DEVICE_INDEX=0` (a falsy integer value) is forwarded correctly.
 
---
 
#### Runtime Failure — Exit Code 125 (Container Name Conflict)
 
After the image built successfully, `docker run` exited immediately with code **125**. Exit code 125 is returned by the Docker CLI itself (before the container process starts) and almost always means one of two things:
 
| Code 125 cause | How to identify | Fix |
|---|---|---|
| Container name already in use | `docker ps -a \| grep whisper-trt-enhanced-dev` shows an existing stopped container | `docker rm whisper-trt-enhanced-dev` |
| Unknown `docker run` flag | Docker prints `unknown flag:` to stderr | Check the `docker run` argument list |
 
**Most likely cause here:** The container `whisper-trt-enhanced-dev` was created during the 2026-05-24 test run and was never removed. The 2026-05-24 entry confirms the run ended with a Python crash inside the container; the container stopped but was not cleaned up. `gpu-build.sh` uses `--name "${CONTAINER_NAME}-dev"` which hardcodes the name; Docker refuses to create a second container with the same name.
 
**Verify and fix before next test:**
 
```bash
# Check for the stale container
docker ps -a | grep whisper-trt-enhanced-dev
 
# Remove it
docker rm whisper-trt-enhanced-dev
 
# Optionally also clean dangling images to reclaim disk space
docker image prune -f
```
 
After removing the stale container, `gpu-build.sh` will succeed in creating a fresh one.
 
> **Note for future runs:** `gpu-build.sh` could be hardened to auto-remove stale containers with the same name before creating a new one. The following line added before `docker run` would eliminate the conflict entirely:
> ```bash
> docker rm "${CONTAINER_NAME}-dev" 2>/dev/null || true
> ```
> This is deferred to a future session — the current script is otherwise correct.
 
---
 
#### ALSA Warnings (Non-Fatal — Context)
 
The following ALSA messages appear on every container start when PulseAudio is not running inside the container. They are **not errors** and do not block audio capture via ALSA directly:
 
```
ALSA lib pcm_dsnoop.c:567:(snd_pcm_dsnoop_open) unable to open slave
ALSA lib pcm_dmix.c:1000:(snd_pcm_dmix_open) unable to open slave
ALSA lib pcm.c:2721:(snd_pcm_open_noupdate) Unknown PCM cards.pcm.rear
ALSA lib pcm.c:2721:(snd_pcm_open_noupdate) Unknown PCM cards.pcm.center_lfe
ALSA lib pcm.c:2721:(snd_pcm_open_noupdate) Unknown PCM cards.pcm.side
Cannot connect to server socket err = No such file or directory
Cannot connect to server request channel
jack server is not running or cannot be started
```
 
| Message | Cause | Action required |
|---|---|---|
| `unable to open slave` for dsnoop/dmix | ALSA dmix/dsnoop plugins attempt to open the shared PCM device; fail because device is held or no PulseAudio | None — these are probes, not errors |
| `Unknown PCM cards.pcm.rear/center_lfe/side` | Surround-sound PCM aliases referenced in ALSA config but not present on the hardware | None |
| `Cannot connect to server socket` | PulseAudio socket not present in container | None — ALSA direct access bypasses PulseAudio entirely |
| `jack server is not running` | JACK audio not present | None |
 
These messages are printed by PortAudio/ALSA during device enumeration and can be suppressed at the ALSA config level if desired, but suppressing them has no effect on functionality.
 
---
 
#### Files Changed
 
| File | Change summary |
|---|---|
| `whisper_trt/examples/live_transcription.py` | `import os` added; `_AUDIO_MATCH_KEYWORDS` tuple; `find_respeaker_audio_device_index()` fully rewritten; `--list-devices` flag; `model` arg made optional |
| `docker/gpu-build.sh` | `AUDIO_DEVICE_INDEX_ARG` array; passthrough into `docker run` |
 
---
 
#### Pre-Test Checklist for 2026-05-27
 
Before running `sudo bash docker/gpu-build.sh` tomorrow:
 
```bash
# 1. Remove the stale container from the 2026-05-24 run
docker rm whisper-trt-enhanced-dev
 
# 2. Confirm no competing application holds the microphone on the host
# (close browser tabs with mic access, video call apps, etc.)
fuser /dev/snd/*
 
# 3. Confirm the sound device is visible to the host
aplay -l   # lists playback devices
arecord -l # lists capture devices
 
# 4. Optional — identify the correct device index before starting the container
docker run --rm \
    --device /dev/snd \
    --group-add audio \
    whisper-trt-enhanced:latest \
    python whisper_trt/examples/live_transcription.py --list-devices
 
# 5. If auto-detection still fails, pin the index explicitly
AUDIO_DEVICE_INDEX=0 sudo bash docker/gpu-build.sh
 
# 6. Standard run (auto-detection enabled)
sudo bash docker/gpu-build.sh
```
 
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