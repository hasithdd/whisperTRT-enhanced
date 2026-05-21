# Use PyTorch container with CUDA support
FROM pytorch/pytorch:2.11.0-cuda12.8-cudnn9-devel

# Environment
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH} \
    WHISPER_MODEL=base.en \
    WHISPER_BACKEND=whisper_trt

# System deps
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    ffmpeg \
    libssl-dev \
    portaudio19-dev \
    python3-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# IMPORTANT:
# Pin setuptools before installing whisper
RUN pip install --no-cache-dir --break-system-packages \
    "pip<25" \
    "setuptools<81" \
    wheel \
    packaging

# Cache dirs
RUN mkdir -p /root/.cache/whisper /root/.cache/whisper_trt

WORKDIR /workspace

# Install whisper FIRST with build isolation disabled
RUN pip install --no-build-isolation --break-system-packages \
    openai-whisper==20240927

# Install remaining deps
RUN pip install --break-system-packages \
    pyaudio \
    onnxruntime \
    onnx_graphsurgeon \
    tensorrt

# Local packages
COPY torch2trt /workspace/torch2trt
RUN pip install --break-system-packages -e /workspace/torch2trt

COPY whisper_trt /workspace/whisper_trt
RUN pip install --break-system-packages -e /workspace/whisper_trt

# Verify CUDA
RUN python -c "import torch; print(torch.cuda.is_available())"

CMD ["python", "whisper_trt/examples/live_transcription.py", "base.en", "--backend", "whisper_trt"]