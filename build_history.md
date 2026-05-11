# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Detailed Docker experiment log for `nvcr.io/nvidia/pytorch:25.02-py3` environment setup and dependency resolution.
- Explicit note that microphone permissions must be granted when starting the container (cannot be fixed after attach without restarting).
- Explicit note to mount model cache directories to host before starting container to avoid redundant re-downloads and container bloat.
- Production-ready Dockerfile and gpu-build.sh based on experimental findings (2026-05-09).
- Docker build now uses the local workspace sources for `torch2trt` and `whisper_trt` instead of cloning remote repositories.
- `gpu-build.sh` now builds from the repository root and launches `whisper_trt/examples/live_transcription.py` with `base.en` and `--backend whisper_trt` by default.

#### Docker Follow-up Update (2026-05-11)

Refined the Docker workflow so the image is built from the current workspace and the container starts live transcription automatically.

1. **Dockerfile updates**
   - Installs runtime dependencies needed by live transcription, including `openai-whisper`, `pyaudio`, `onnxruntime`, and `onnx_graphsurgeon`
   - Copies local `torch2trt` and `whisper_trt` sources into the image and installs them in editable mode
   - Sets default runtime environment variables for `base.en` and `whisper_trt`
   - Runs `whisper_trt/examples/live_transcription.py` by default instead of dropping into a shell

2. **gpu-build.sh updates**
   - Resolves the repository root automatically from the script location
   - Builds the Docker image from the workspace root so local source changes are included
   - Mounts the repository into `/workspace` for interactive development and runtime access
   - Starts live transcription directly with `base.en` and the `whisper_trt` backend

#### Docker Implementation (2026-05-09)

Created production-ready Docker configuration incorporating lessons learned from 2026-05-08 experiments.

1. **Dockerfile**
   - Base: `nvcr.io/nvidia/pytorch:25.02-py3` with TensorRT and CUDA 12.8 pre-installed
   - System dependencies: `build-essential`, `cmake`, `libssl-dev`, `portaudio19-dev`, `python3-dev`, `git`, `wget`
   - Pinned setuptools to v70.0.0 for build compatibility
   - Installs openai-whisper v20240927 with `--no-build-isolation` flag (resolves metadata/wheel build failures)
   - Audio support: pyaudio with pre-installed system portaudio libs
   - TensorRT dependencies: onnxruntime_gpu, onnx_graphsurgeon
   - Pre-clones and installs torch2trt and whisper_trt with error isolation
   - CUDA availability verification step
   - Pre-creates `/root/.cache/whisper` and `/root/.cache/whisper_trt` directories
   - Optimizations: Cleans apt cache, removes temp build directories after installation

2. **gpu-build.sh**
   - Automated build and run script with configurable image name and container name
   - Pre-creates host cache directories (`~/.cache/whisper`, `~/.cache/whisper_trt`)
   - Builds local Dockerfile if present
   - Comprehensive container launch with:
     - GPU passthrough: `--gpus all`
     - IPC optimization: `--ipc=host`
     - Memory limits: `--ulimit memlock=-1 --ulimit stack=67108864`
     - Audio device access: `--device /dev/snd --group-add audio` (resolves ALSA/device errors)
     - Volume mounts for persistent model/cache storage
     - Named container for easy restart/management
   - Provides helpful notes and cleanup instructions
   - Graceful container state management (exit, restart, cleanup commands)

3. **Key improvements from experiments**
   - Setuptools pinning prevents build isolation failures
   - Audio device passthrough ensures live transcription works without restart
   - Host cache mounts prevent container bloat and redundant model re-downloads
   - Pre-installation of dependencies reduces first-run build time
   - Error verification (CUDA check) fails fast if environment is misconfigured

#### Usage
```bash
cd docker
chmod +x gpu-build.sh
./gpu-build.sh
```

To restart persistent container:
```bash
docker start -ai whisper-trt-enhanced-dev
```

To clean up:
```bash
docker rm whisper-trt-enhanced-dev
```

#### Docker Experiment Details (2026-05-08)

This entry captures an end-to-end container setup attempt where dependency issues were resolved one by one, followed by runtime issues related to container launch flags.

1. **Base container launch**
   - Container started with GPU and memory flags:
   - `docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -it nvcr.io/nvidia/pytorch:25.02-py3 /bin/bash`
   - CUDA availability verified (`torch.cuda.is_available() == True`).

2. **Whisper package install issue and resolution**
   - `pip install openai-whisper==20240927` initially failed during build metadata/wheel preparation.
   - Upgraded packaging tools, then used non-isolated build.
   - Resolved by pinning `setuptools==70.0.0` and installing with:
   - `pip install --no-build-isolation openai-whisper==20240927`

3. **whisper_trt dependency chain resolution**
   - `whisper_trt` install initially failed due to missing `torch2trt`.
   - Cloned and installed `torch2trt`, then installed `whisper_trt`.
   - Runtime dependencies were resolved iteratively:
     - Missing `pyaudio` -> installed system deps `portaudio19-dev python3-dev`, then installed `pyaudio`.
     - Missing `onnxruntime` -> installed `onnxruntime_gpu`.
     - Missing `onnx_graphsurgeon` -> installed `onnx_graphsurgeon`.
   - After these, TensorRT runtime started and model assets downloaded/build process began successfully.

4. **Critical runtime lesson: microphone access**
   - Live transcription failed in container due to ALSA/device errors because container was not started with audio device permissions.
   - Container must be launched with host audio access, e.g. include:
   - `--device /dev/snd --group-add audio`
   - Depending on host setup, PulseAudio/PipeWire socket mapping may also be required.

5. **Critical storage lesson: mount model/cache paths to host**
   - Whisper/whisper_trt downloads and TensorRT engine artifacts can be large.
   - If cache/model paths are not bind-mounted, downloads remain inside container writable layer and are lost on container removal (and may grow container storage usage unnecessarily).
   - Recommended mounts at container start:
   - `-v $HOME/.cache/whisper:/root/.cache/whisper`
   - `-v $HOME/.cache/whisper_trt:/root/.cache/whisper_trt`

6. **Recommended improved launch command**
   - `docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 --device /dev/snd --group-add audio -v $HOME/.cache/whisper:/root/.cache/whisper -v $HOME/.cache/whisper_trt:/root/.cache/whisper_trt -it nvcr.io/nvidia/pytorch:25.02-py3 /bin/bash`

#### Notes
- `setup.py install` worked for this experiment but is deprecated; a modern `pip install .`-based flow is preferable for future updates.
- Several package conflict warnings were observed while upgrading build tooling in-container; pinning versions helped complete the setup.

## [0.0.1] - 2026-05-02

### Added
- Comprehensive installation guide for whisperTRT-enhanced project
- Prerequisites section with system requirements
- Manual installation steps for PyTorch, torch2trt, and whisper_trt
- Docker setup alternative using NVIDIA PyTorch containers
- Troubleshooting section for common issues
- Key links to official documentation and resources

#### Installation Guide Details

This document outlines the installation process for the whisperTRT-enhanced project, including torch2trt and whisper_trt components. It covers manual setup and Docker-based alternatives, with troubleshooting tips.

#### Prerequisites
- Python >= 3.12
- NVIDIA GPU with CUDA support (compute capability >= 7.0)
- CUDA Toolkit (12.8+, matching PyTorch and TensorRT)
- System dependencies: `build-essential`, `cmake`, `libssl-dev` (install via `sudo apt-get install build-essential cmake libssl-dev` on Ubuntu/Debian)
- Disk space: ~5-10 GB

**Key links:**
- [PyTorch with CUDA installation](https://pytorch.org/get-started/locally/)
- [TensorRT installation guide](https://docs.nvidia.com/deeplearning/tensorrt/install-guide/index.html)
- [uv package manager](https://docs.astral.sh/uv/getting-started/installation/)
- [NGC PyTorch containers](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/pytorch)

#### Manual Installation Steps

1. **Install PyTorch with CUDA**:
   - Download and install PyTorch with CUDA support from the official site.
   - Example: `uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128`
   - Verify: `python -c "import torch; print(torch.cuda.is_available())"`

2. **Clone repositories**:
   - Clone whisper_trt and torch2trt if not already present.
   - `git clone https://github.com/NVIDIA-AI-IOT/whisper_trt.git`
   - `git clone https://github.com/NVIDIA-AI-IOT/torch2trt.git`

3. **Install torch2trt**:
   - `cd torch2trt`
   - `uv run setup.py install`
   - If TensorRT is missing, install according to the [NVIDIA guide](https://docs.nvidia.com/deeplearning/tensorrt/install-guide/index.html).
   - Optional: Build plugins with `cmake -B build . && cmake --build build --target install && sudo ldconfig`

4. **Install whisper_trt**:
   - `cd ../whisper_trt`
   - Install openai-whisper version 20240927 (see [issue #12 comment](https://github.com/NVIDIA-AI-IOT/whisper_trt/issues/12#issuecomment-2459897517) for details).
   - `uv pip install openai-whisper==20240927`
   - Then: `uv run setup.py install`

5. **Run an example**:
   - After installation, test with `python examples/transcribe.py tiny.en <audio_file>`

#### Docker Setup (Recommended)

For easier setup, use NVIDIA's PyTorch Docker image, which includes TensorRT and torch2trt pre-installed.

1. **Download the image**:
   - Pull the appropriate image from [NGC catalog](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/pytorch), matching your CUDA, PyTorch, and Linux versions.
   - Example: `docker pull nvcr.io/nvidia/pytorch:25.02-py3`

2. **Run the container**:
   - `docker run --gpus all -it nvcr.io/nvidia/pytorch:25.02-py3 /bin/bash`

3. **Install dependencies inside container**:
   - Install the correct openai-whisper version: `pip install openai-whisper==20240927`
   - Clone and install whisper_trt: `git clone https://github.com/NVIDIA-AI-IOT/whisper_trt.git && cd whisper_trt && python setup.py install`

4. **Run examples**:
   - Proceed to run the examples as in the manual steps.

#### Troubleshooting

- **TensorRT missing**: Follow the NVIDIA installation guide and ensure LD_LIBRARY_PATH includes TensorRT libs.
- **Version mismatches**: Ensure CUDA, PyTorch, and TensorRT versions are compatible (e.g., TensorRT 10+ with CUDA 12.8).
- **Build failures**: Check for cmake and CUDA in PATH; use sudo if needed.
- **First-run delays**: TensorRT engine building takes time; it's cached afterward.
- **Jetson-specific**: Use JetPack containers; avoid mixing desktop and Jetson TensorRT.

