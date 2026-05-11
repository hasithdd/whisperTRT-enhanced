#!/bin/bash

# GPU Build Script for whisperTRT-enhanced
# This script builds and runs the Docker container with proper GPU, audio, and cache configuration

set -e

# Resolve repository locations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration
IMAGE_NAME="${1:-whisper-trt-enhanced:latest}"
CONTAINER_NAME="${2:-whisper-trt-enhanced}"
MODEL_NAME="${3:-base.en}"
BACKEND_NAME="${4:-whisper_trt}"
CACHE_DIR="${HOME}/.cache"

# Create cache directories on host if they don't exist
mkdir -p "${CACHE_DIR}/whisper"
mkdir -p "${CACHE_DIR}/whisper_trt"

echo "Building whisperTRT-enhanced Docker container..."
echo "  Image Tag: ${IMAGE_NAME}"
echo "  Container Name: ${CONTAINER_NAME}"
echo "  Model: ${MODEL_NAME}"
echo "  Backend: ${BACKEND_NAME}"
echo "  Cache Directory: ${CACHE_DIR}"
echo ""

# Build the Docker image from the repository root
echo "Building Docker image from local Dockerfile..."
docker build -t "${IMAGE_NAME}" -f "${SCRIPT_DIR}/Dockerfile" "${REPO_ROOT}"

# Display the recommended run command
echo ""
echo "Starting container with optimized GPU configuration..."
echo ""
echo "Important Notes:"
echo "  1. Microphone permissions are granted with --device /dev/snd --group-add audio"
echo "  2. Model and cache directories are mounted to preserve them on host"
echo "  3. GPU access, IPC, and memory limits are configured for optimal performance"
echo ""

# Run the container with comprehensive configuration
docker run \
    --gpus all \
    --ipc=host \
    --ulimit memlock=-1 \
    --ulimit stack=67108864 \
    --device /dev/snd \
    --group-add audio \
    -v "${CACHE_DIR}/whisper:/root/.cache/whisper" \
    -v "${CACHE_DIR}/whisper_trt:/root/.cache/whisper_trt" \
    -v "${REPO_ROOT}:/workspace" \
    --workdir /workspace \
    --name "${CONTAINER_NAME}-dev" \
    -it \
    "${IMAGE_NAME}" \
    python whisper_trt/examples/live_transcription.py "${MODEL_NAME}" --backend "${BACKEND_NAME}"

echo ""
echo "Container stopped. To restart, run:"
echo "  docker start -ai ${CONTAINER_NAME}-dev"
echo ""
echo "To clean up the container, run:"
echo "  docker rm ${CONTAINER_NAME}-dev"
