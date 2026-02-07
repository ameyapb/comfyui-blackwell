##############################################################################
# ComfyUI Qwen Image Edit - Blackwell Ready
# ==============================================================================
# Multi-stage Docker build optimized for RTX 5090 (Blackwell, sm_120)
#
# Features:
# - CUDA 12.8 build (forward-compatible with CUDA 13.0 runtime on RunPod)
# - Python 3.12 (matches proven working template)
# - PyTorch cu128 (stable CUDA 12.8 build)
# - ComfyUI + custom nodes pre-installed
# - Models downloaded at first startup (~38 GB via aria2c)
# - Jupyter, FileBrowser, SSH, FFmpeg integration
# - Health checks for GPU/CUDA compatibility
#
# Build time: ~30-45 min
# Final image: ~15-20 GB (models downloaded at runtime)
##############################################################################

# ============================================================================
# Stage 1: Builder - Install all Python packages (CUDA 12.8)
# ============================================================================
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Install all build dependencies in one layer (matches working template)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    software-properties-common \
    gpg-agent \
    git \
    wget \
    curl \
    ca-certificates \
    aria2 \
    build-essential \
    pkg-config \
    libssl-dev \
    libffi-dev \
    libopenblas-dev \
    ffmpeg \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    && add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    && wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb \
    && dpkg -i cuda-keyring_1.1-1_all.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends cuda-minimal-build-12-8 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm cuda-keyring_1.1-1_all.deb

# Install pip for Python 3.12 (matches working template - do NOT use apt python3-pip)
RUN curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python3.12 get-pip.py && \
    python3.12 -m pip install --upgrade pip && \
    rm get-pip.py

# Set CUDA environment for building
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64

# ============================================================================
# PyTorch Installation (stable CUDA 12.8 build)
# ============================================================================
# cu128 is forward-compatible with CUDA 13.0 runtime on RunPod
# RTX 5090 (Blackwell, sm_120) works with CUDA 13.0 runtime + cu128 PyTorch

RUN python3.12 -m pip install --no-cache-dir \
    torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

# ============================================================================
# ComfyUI Installation
# ============================================================================

WORKDIR /tmp/build
RUN git clone https://github.com/comfyanonymous/ComfyUI.git

# Clone custom nodes
WORKDIR /tmp/build/ComfyUI/custom_nodes
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    git clone https://github.com/kijai/ComfyUI-KJNodes.git && \
    git clone https://github.com/MoonGoblinDev/Civicomfy.git

# Install ComfyUI Python dependencies (matches working template)
WORKDIR /tmp/build/ComfyUI
RUN python3.12 -m pip install --no-cache-dir -r requirements.txt && \
    python3.12 -m pip install --no-cache-dir GitPython opencv-python

# Install custom node dependencies
WORKDIR /tmp/build/ComfyUI/custom_nodes
RUN for node_dir in */; do \
        if [ -f "$node_dir/requirements.txt" ]; then \
            echo "Installing requirements for $node_dir"; \
            python3.12 -m pip install --no-cache-dir -r "$node_dir/requirements.txt" || true; \
        fi; \
    done

# ============================================================================
# Additional Tools
# ============================================================================

# Jupyter Notebook
RUN python3.12 -m pip install --no-cache-dir jupyter jupyterlab notebook

# FileBrowser binary
RUN aria2c -x 16 -k 1M -c \
    -d /tmp \
    -o linux-amd64-filebrowser.tar.gz \
    "https://github.com/filebrowser/filebrowser/releases/download/v2.28.0/linux-amd64-filebrowser.tar.gz" && \
    tar -xzf /tmp/linux-amd64-filebrowser.tar.gz -C /usr/local/bin && \
    rm /tmp/linux-amd64-filebrowser.tar.gz && \
    chmod +x /usr/local/bin/filebrowser

##############################################################################
# Stage 2: Runtime - Clean image with pre-installed packages
##############################################################################
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV IMAGEIO_FFMPEG_EXE=/usr/bin/ffmpeg

# Install runtime dependencies (matches working template)
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    software-properties-common \
    gpg-agent \
    && add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    build-essential \
    libssl-dev \
    wget \
    gnupg \
    xz-utils \
    openssh-client \
    openssh-server \
    nano \
    curl \
    htop \
    tmux \
    ca-certificates \
    less \
    net-tools \
    iputils-ping \
    procps \
    aria2 \
    ffmpeg \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    golang \
    make \
    && wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb \
    && dpkg -i cuda-keyring_1.1-1_all.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends cuda-minimal-build-12-8 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm cuda-keyring_1.1-1_all.deb

# Copy Python packages and executables from builder (MUST come before uv removal)
COPY --from=builder /usr/local/lib/python3.12 /usr/local/lib/python3.12
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy ComfyUI from builder (pre-installed with custom nodes)
COPY --from=builder /tmp/build/ComfyUI /workspace/ComfyUI

# Remove uv AFTER copying from builder (order matters!)
RUN pip uninstall -y uv 2>/dev/null || true && \
    rm -f /usr/local/bin/uv /usr/local/bin/uvx

# Set CUDA environment variables
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64

# Set Python 3.12 as default (matches working template)
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    update-alternatives --set python3 /usr/bin/python3.12 && \
    update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1

# SSH configuration (matches working template)
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    mkdir -p /run/sshd && \
    mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh && \
    rm -f /etc/ssh/ssh_host_*

WORKDIR /workspace

# ============================================================================
# Copy Startup Scripts
# ============================================================================

COPY scripts/start.sh /usr/local/bin/start.sh
COPY scripts/health_check.sh /usr/local/bin/health_check.sh
COPY scripts/validate_models.sh /usr/local/bin/validate_models.sh

# Fix Windows CRLF line endings (critical: bash scripts fail with \r)
RUN sed -i 's/\r$//' /usr/local/bin/start.sh && \
    sed -i 's/\r$//' /usr/local/bin/health_check.sh && \
    sed -i 's/\r$//' /usr/local/bin/validate_models.sh && \
    chmod +x /usr/local/bin/start.sh && \
    chmod +x /usr/local/bin/health_check.sh && \
    chmod +x /usr/local/bin/validate_models.sh

# ============================================================================
# Expose Services
# ============================================================================

EXPOSE 8188 8888 8080 22

# ============================================================================
# Health Check
# ============================================================================

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /usr/local/bin/health_check.sh

# ============================================================================
# Entrypoint
# ============================================================================

ENTRYPOINT ["/usr/local/bin/start.sh"]
