# Use NVIDIA PyTorch container with TensorRT and CUDA support
FROM nvcr.io/nvidia/pytorch:25.02-py3

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH} \
    WHISPER_MODEL=base.en \
    WHISPER_BACKEND=whisper_trt

# Install system dependencies for audio and build tools
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    ffmpeg \
    libssl-dev \
    portaudio19-dev \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Upgrade packaging tools for local installs
RUN pip install --upgrade pip setuptools wheel

# Create cache directories
RUN mkdir -p /root/.cache/whisper /root/.cache/whisper_trt

WORKDIR /workspace

# Install Python dependencies required by the live transcription example
RUN pip install --no-build-isolation \
    openai-whisper==20240927 \
    pyaudio \
    onnxruntime \
    onnx_graphsurgeon

# Install the local torch2trt and whisper_trt packages from the workspace
COPY torch2trt /workspace/torch2trt
RUN pip install --no-build-isolation -e /workspace/torch2trt

COPY whisper_trt /workspace/whisper_trt
RUN pip install --no-build-isolation -e /workspace/whisper_trt

# Verify CUDA is available
RUN python -c "import torch; assert torch.cuda.is_available(), 'CUDA not available'"

# Run live transcription by default
CMD ["python", "whisper_trt/examples/live_transcription.py", "base.en", "--backend", "whisper_trt"]
