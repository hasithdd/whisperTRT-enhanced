# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

