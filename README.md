# WhisperTRT-Enhanced

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Python](https://img.shields.io/badge/Python-3.12+-blue.svg)](https://www.python.org/)
[![CUDA](https://img.shields.io/badge/CUDA-12.8%2B-green.svg)](https://developer.nvidia.com/cuda-toolkit)
[![TensorRT](https://img.shields.io/badge/TensorRT-10+-red.svg)](https://developer.nvidia.com/tensorrt)

An enhanced version of the forgotten [whisper_trt](https://github.com/NVIDIA-AI-IOT/whisper_trt) by dustynv, powered by NVIDIA Triton for modern production serving. Designed for seamless integration with agentic platforms like LiveKit, offering low memory/GPU usage and high accuracy for English-only transcription, rivaling NVIDIA Parakeet models at the same inference speed.

## 🚀 Features

- **Low Resource Consumption**: Optimized for minimal GPU memory and CPU usage, ideal for edge devices and low-resource environments.
- **High Accuracy**: Maintains accuracy comparable to modern NVIDIA Parakeet models for English transcription.
- **Fast Inference**: Same speed as Parakeet models, leveraging TensorRT optimizations.
- **Production Ready**: Integrated with NVIDIA Triton Inference Server for scalable, production-grade serving.
- **Agentic Platform Compatible**: Easy integration with platforms like LiveKit for real-time agentic applications.
- **Modern Python Practices**: Built with `uv` for fast, reliable package management and Python 3.12+ best practices.
- **English-Only Focus**: Streamlined for English transcription with superior performance in this domain.

## 📋 Prerequisites

- Python >= 3.12
- NVIDIA GPU with CUDA support (compute capability >= 7.0)
- CUDA Toolkit (12.8+)
- TensorRT 10+
- System dependencies: `build-essential`, `cmake`, `libssl-dev`

## 🛠 Installation

For detailed installation steps, see [build_history.md](build_history.md).

### Quick Setup with Docker (Recommended)

```bash
# Pull NVIDIA PyTorch image with TensorRT pre-installed
docker pull nvcr.io/nvidia/pytorch:25.02-py3

# Run container
docker run --gpus all -it nvcr.io/nvidia/pytorch:25.02-py3 /bin/bash

# Inside container
pip install openai-whisper==20240927
git clone https://github.com/NVIDIA-AI-IOT/whisper_trt.git
cd whisper_trt && python setup.py install
```

### Manual Installation

1. Install PyTorch with CUDA: `uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128`
2. Clone and install torch2trt and whisper_trt as per [build_history.md](build_history.md).
3. Install openai-whisper: `uv pip install openai-whisper==20240927`

## 📖 Usage

### Basic Transcription

```python
from whisper_trt import load_trt_model

# Load model
model = load_trt_model("tiny.en")

# Transcribe audio
result = model.transcribe("path/to/audio.wav")
print(result["text"])
```

### With Triton Server

Configure Triton for serving the TensorRT-optimized Whisper model. Refer to NVIDIA Triton documentation for deployment.

### LiveKit Integration

This project is designed for easy compatibility with LiveKit agentic platforms. Use the Triton server endpoint for real-time transcription in your agents.

## 🔧 Development

- **Package Manager**: Uses `uv` for fast, reproducible installs.
- **Code Quality**: Follows modern Python practices with type hints, async support, and modular design.
- **Testing**: Run tests with `uv run pytest`.

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](torch2trt/CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Based on [NVIDIA-AI-IOT/whisper_trt](https://github.com/NVIDIA-AI-IOT/whisper_trt) by dustynv
- Powered by [torch2trt](https://github.com/NVIDIA-AI-IOT/torch2trt)
- NVIDIA Triton Inference Server for production serving
- Inspired by LiveKit for agentic platform compatibility

## 📞 Support

For issues and questions, please open an issue on [GitHub](https://github.com/hasithdd/whisperTRT-enhanced).

---

*Bringing forgotten Whisper TRT back to life with modern production capabilities.*
