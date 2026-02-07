##############################################################################
# ComfyUI Qwen Image Edit - Blackwell Ready
# ==============================================================================
# Multi-stage Docker build optimized for RTX 5090 (Blackwell, sm_120)
# 
# Features:
# - CUDA 12.8 (supports Blackwell sm_120)
# - PyTorch cu128 (stable CUDA 12.8 build)
# - Pre-downloaded Qwen models (~38 GB)
# - Jupyter, FileBrowser, SSH, FFmpeg integration
# - Health checks for GPU/CUDA compatibility
#
# Build time: ~45-60 min (first build with models)
# Final image: ~45-50 GB
##############################################################################

FROM ubuntu:22.04 AS builder

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

WORKDIR /build

# Install CUDA 12.8 + build essentials
RUN set -e && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    software-properties-common \
    gpg-agent \
    wget \
    curl \
    ca-certificates \
    && wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb \
    && dpkg -i cuda-keyring_1.1-1_all.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends cuda-minimal-build-12-8 \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && rm cuda-keyring_1.1-1_all.deb

# ============================================================================
# Stage 1: Builder - Install all dependencies & download models
# ============================================================================

RUN set -e && \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    aria2 \
    git \
    make \
    pkg-config \
    libssl-dev \
    libffi-dev \
    libopenblas-dev \
    ffmpeg \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Python 3.10 (ComfyUI standard)
RUN set -e && \
    add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.10 \
    python3.10-dev \
    python3.10-venv \
    python3-pip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set Python 3.10 as default
RUN set -e && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1 && \
    update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1

# Upgrade pip, setuptools, wheel
RUN set -e && python -m pip install --upgrade pip setuptools wheel

# ============================================================================
# PyTorch Installation (stable CUDA 12.8 build)
# ============================================================================
# RTX 5090 (Blackwell, sm_120) is supported via CUDA 12.8

RUN set -e && \
    python -m pip install --index-url https://download.pytorch.org/whl/cu128 \
    torch torchvision torchaudio \
    --no-cache-dir

# Verify PyTorch + CUDA compatibility (logs for debugging)
RUN set -e && \
    python -c "import torch; print(f'PyTorch: {torch.__version__}'); print(f'CUDA: {torch.version.cuda}'); print(f'GPU Available: {torch.cuda.is_available()}')"

# ============================================================================
# ComfyUI Installation
# ============================================================================

RUN set -e && \
    git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI && \
    cd /workspace/ComfyUI && \
    git checkout main

# Install ComfyUI Python dependencies
RUN set -e && \
    cd /workspace/ComfyUI && \
    python -m pip install -r requirements.txt --no-cache-dir

# Install custom nodes
RUN set -e && \
    mkdir -p /workspace/ComfyUI/custom_nodes && \
    cd /workspace/ComfyUI/custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelper-Nodes.git && \
    git clone https://github.com/kijai/ComfyUI-KJNodes.git && \
    git clone https://github.com/MoonGoblinDev/Civicomfy.git

# Install custom node dependencies
RUN cd /workspace/ComfyUI/custom_nodes && \
    for node_dir in */; do \
        if [ -f "$node_dir/requirements.txt" ]; then \
            echo "Installing requirements for $node_dir"; \
            python -m pip install --no-cache-dir -r "$node_dir/requirements.txt" || true; \
        fi; \
    done

# ============================================================================
# Jupyter Notebook for interactive workflows
# ============================================================================

RUN set -e && \
    python -m pip install \
    jupyter \
    jupyterlab \
    notebook \
    --no-cache-dir

# ============================================================================
# FileBrowser for file management UI (download with aria2c for speed)
# ============================================================================

RUN set -e && \
    aria2c -x 16 -k 1M -c \
    -d /tmp \
    -o linux-amd64-filebrowser.tar.gz \
    "https://github.com/filebrowser/filebrowser/releases/download/v2.28.0/linux-amd64-filebrowser.tar.gz" && \
    tar -xzf /tmp/linux-amd64-filebrowser.tar.gz -C /usr/local/bin && \
    rm /tmp/linux-amd64-filebrowser.tar.gz && \
    chmod +x /usr/local/bin/filebrowser

# ============================================================================
# FFmpeg with NVIDIA NVENC support
# ============================================================================
# Already installed via apt (ffmpeg was in initial apt-get install)
# Verify hardware encoding support:

RUN set -o pipefail && ffmpeg -encoders 2>&1 | grep -i nvenc || true

# ============================================================================
# Model Downloads (38 GB total) - Using aria2c for speed
# ============================================================================
# aria2c: 16 parallel connections → 25-48 Mbps (vs wget single-threaded 5-6 Mbps)

# Create model directories
RUN mkdir -p /workspace/models/checkpoints && \
    mkdir -p /workspace/models/text_encoders && \
    mkdir -p /workspace/models/vae

# Download Checkpoint: Qwen-Rapid-AIO-NSFW-v11.4.safetensors (28.4 GB)
RUN set -e && \
    aria2c -x 16 -k 1M -c \
    -d /workspace/models/checkpoints \
    -o Qwen-Rapid-AIO-NSFW-v11.4.safetensors \
    "https://huggingface.co/Phr00t/Qwen-Image-Edit-Rapid-AIO/resolve/main/v11/Qwen-Rapid-AIO-NSFW-v11.4.safetensors" || \
    (echo "ERROR: Failed to download checkpoint model" && exit 1)

# Download Text Encoder: qwen_2.5_vl_7b_fp8_scaled.safetensors (9.38 GB)
RUN set -e && \
    aria2c -x 16 -k 1M -c \
    -d /workspace/models/text_encoders \
    -o qwen_2.5_vl_7b_fp8_scaled.safetensors \
    "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors" || \
    (echo "ERROR: Failed to download text encoder model" && exit 1)

# Download VAE: qwen_image_vae.safetensors (254 MB)
RUN set -e && \
    aria2c -x 16 -k 1M -c \
    -d /workspace/models/vae \
    -o qwen_image_vae.safetensors \
    "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors" || \
    (echo "ERROR: Failed to download VAE model" && exit 1)

# Verify model downloads (file sizes)
RUN set -e && \
    ls -lh /workspace/models/checkpoints/ && \
    ls -lh /workspace/models/text_encoders/ && \
    ls -lh /workspace/models/vae/

# ============================================================================
# SSH Configuration
# ============================================================================

RUN set -e && \
    mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# ============================================================================
# Cleanup & Optimize
# ============================================================================

RUN set -e && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    find /usr -type f -name "*.pyc" -delete && \
    find /usr -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

##############################################################################
# Stage 2: Runtime - Lean image with pre-compiled dependencies
##############################################################################

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# Install CUDA 12.8 runtime + minimal deps
RUN set -e && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    software-properties-common \
    gpg-agent \
    wget \
    curl \
    ca-certificates \
    && wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb \
    && dpkg -i cuda-keyring_1.1-1_all.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends cuda-minimal-build-12-8 \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && rm cuda-keyring_1.1-1_all.deb

# Minimal dependencies for runtime
RUN set -e && \
    apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    openssh-server \
    openssh-client \
    tmux \
    nano \
    htop \
    ffmpeg \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    python3.10 \
    python3.10-dev \
    python3-pip \
    golang \
    make \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Remove uv to force ComfyUI-Manager to use pip
RUN pip uninstall -y uv 2>/dev/null || true && \
    rm -f /usr/local/bin/uv /usr/local/bin/uvx

# SSH setup
RUN set -e && \
    mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Create SSH runtime directory
RUN set -e && \
    mkdir -p /run/sshd && \
    chmod 755 /run/sshd

# Copy built files from builder stage
COPY --from=builder /workspace /workspace
COPY --from=builder /usr/local/bin/filebrowser /usr/local/bin/filebrowser
COPY --from=builder /usr/local/lib/python3.10 /usr/local/lib/python3.10
COPY --from=builder /usr/local/bin /usr/local/bin

# Set Python 3.10 as default
RUN set -e && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1 && \
    update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1

WORKDIR /workspace

# ============================================================================
# Copy Startup Scripts
# ============================================================================

COPY scripts/start.sh /usr/local/bin/start.sh
COPY scripts/health_check.sh /usr/local/bin/health_check.sh
COPY scripts/validate_models.sh /usr/local/bin/validate_models.sh

RUN set -e && \
    chmod +x /usr/local/bin/start.sh && \
    chmod +x /usr/local/bin/health_check.sh && \
    chmod +x /usr/local/bin/validate_models.sh

# ============================================================================
# Expose Services
# ============================================================================

# ComfyUI
EXPOSE 8188
# Jupyter
EXPOSE 8888
# FileBrowser
EXPOSE 8080
# SSH
EXPOSE 22

# ============================================================================
# Health Check
# ============================================================================

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /usr/local/bin/health_check.sh

# ============================================================================
# Entrypoint
# ============================================================================

ENTRYPOINT ["/usr/local/bin/start.sh"]