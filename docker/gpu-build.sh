#!/bin/bash

# GPU Build Script for whisperTRT-enhanced
# This script builds and runs the Docker container with proper GPU, audio, and cache configuration

set -e

# Configuration
IMAGE_NAME="${1:-nvcr.io/nvidia/pytorch:25.02-py3}"
CONTAINER_NAME="${2:-whisper-trt-enhanced}"
CACHE_DIR="${HOME}/.cache"

# Create cache directories on host if they don't exist
mkdir -p "${CACHE_DIR}/whisper"
mkdir -p "${CACHE_DIR}/whisper_trt"

echo "Building whisperTRT-enhanced Docker container..."
echo "  Base Image: ${IMAGE_NAME}"
echo "  Container Name: ${CONTAINER_NAME}"
echo "  Cache Directory: ${CACHE_DIR}"
echo ""

# Build the Docker image (if using local Dockerfile)
if [ -f "./Dockerfile" ]; then
    echo "Building Docker image from local Dockerfile..."
    docker build -t "${CONTAINER_NAME}:latest" -f ./Dockerfile .
fi

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
    --name "${CONTAINER_NAME}-dev" \
    -it \
    "${CONTAINER_NAME}:latest" \
    /bin/bash

echo ""
echo "Container stopped. To restart, run:"
echo "  docker start -ai ${CONTAINER_NAME}-dev"
echo ""
echo "To clean up the container, run:"
echo "  docker rm ${CONTAINER_NAME}-dev"
