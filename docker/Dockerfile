# Use NVIDIA PyTorch container with TensorRT and CUDA support
FROM nvcr.io/nvidia/pytorch:25.02-py3

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# Install system dependencies for audio and build tools
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    libssl-dev \
    portaudio19-dev \
    python3-dev \
    git \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Upgrade setuptools to specified version for compatibility
RUN pip install --upgrade setuptools==70.0.0

# Create cache directories
RUN mkdir -p /root/.cache/whisper /root/.cache/whisper_trt

# Install openai-whisper with specific version and build flags
RUN pip install --no-build-isolation openai-whisper==20240927

# Install audio support
RUN pip install pyaudio

# Install TensorRT runtime dependencies
RUN pip install onnxruntime_gpu onnx_graphsurgeon

# Clone and install torch2trt
RUN git clone https://github.com/NVIDIA-AI-IOT/torch2trt.git /tmp/torch2trt && \
    cd /tmp/torch2trt && \
    pip install --no-build-isolation . && \
    rm -rf /tmp/torch2trt

# Clone and install whisper_trt
RUN git clone https://github.com/NVIDIA-AI-IOT/whisper_trt.git /tmp/whisper_trt && \
    cd /tmp/whisper_trt && \
    pip install --no-build-isolation . && \
    rm -rf /tmp/whisper_trt

# Verify CUDA is available
RUN python -c "import torch; assert torch.cuda.is_available(), 'CUDA not available'"

# Set working directory
WORKDIR /root

# Default command
CMD ["/bin/bash"]
