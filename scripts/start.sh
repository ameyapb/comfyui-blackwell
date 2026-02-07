#!/bin/bash
##############################################################################
# start.sh - ComfyUI Pod Startup Script
# ==============================================================================
# Handles:
# - RunPod pod detection (On-demand vs Serverless)
# - Jupyter notebook launch (configurable)
# - ComfyUI server startup
# - Health check verification
# - Comprehensive logging
##############################################################################

# IMPORTANT: Do NOT use 'set -e' - startup should continue even if health checks
# have warnings. Warnings should not cause the entire startup to fail.

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging with timestamp
log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} [INFO] $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} [✓] $1"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} [⚠️] $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} [✗] $1"
}

# Environment variables
WORKSPACE="${WORKSPACE:-/workspace}"
COMFYUI_DIR="${WORKSPACE}/ComfyUI"
ENABLE_JUPYTER="${ENABLE_JUPYTER:-1}"
DEBUG="${DEBUG:-0}"
SERVERLESS_API_ENDPOINT="${SERVERLESS_API_ENDPOINT:-}"

# Detect RunPod environment
IS_RUNPOD=false
IS_SERVERLESS=false

if [ -n "$SERVERLESS_API_ENDPOINT" ]; then
    IS_SERVERLESS=true
    IS_RUNPOD=true
elif [ -n "$RUNPOD_POD_ID" ]; then
    IS_RUNPOD=true
fi

# Log startup environment
log_info "========================================"
log_info "ComfyUI Pod Startup"
log_info "========================================"
log_info "Workspace: $WORKSPACE"
log_info "ComfyUI Directory: $COMFYUI_DIR"
log_info "Enable Jupyter: $ENABLE_JUPYTER"
log_info "Debug Mode: $DEBUG"
log_info "RunPod Environment: $IS_RUNPOD"
log_info "Serverless Mode: $IS_SERVERLESS"
log_info "========================================"

# ============================================================================
# 1. Health Check - Verify GPU/CUDA/PyTorch
# ============================================================================

log_info "Running health checks..."

if ! /usr/local/bin/health_check.sh; then
    log_error "Health check failed!"
    echo "CUDA and GPU drivers may not be properly configured."
    echo "The pod will continue, but GPU access may not work."
    echo ""
fi

# ============================================================================
# 2. Model Validation - Verify all models are present
# ============================================================================

log_info "Validating models..."

if /usr/local/bin/validate_models.sh; then
    log_success "All models validated successfully"
else
    log_warn "Some models may be missing or corrupted"
    log_warn "Models may still be downloading or requiring manual configuration"
fi

# ============================================================================
# 3. SSH Server Setup
# ============================================================================

log_info "Starting SSH server..."

# Generate SSH host keys if missing
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    log_info "Generating SSH host keys..."
    ssh-keygen -A
fi

# Start SSH server
if /etc/init.d/ssh start; then
    log_success "SSH server started (port 22)"
else
    log_warn "Could not start SSH server (may require root)"
fi

# ============================================================================
# 4. Jupyter Notebook (ENABLED BY DEFAULT - Configurable)
# ============================================================================

if [ "$ENABLE_JUPYTER" = "1" ]; then
    log_info "Launching Jupyter Notebook (ENABLED BY DEFAULT)..."
    
    # Create Jupyter config directory
    mkdir -p ~/.jupyter
    
    # Start Jupyter in background with optimizations for pod environment
    # - No authentication (safe in pod environment)
    # - GPU/CUDA pre-loaded for interactive ML development
    # - Notebook dir set to workspace for easy access
    nohup jupyter notebook \
        --ip=0.0.0.0 \
        --port=8888 \
        --no-browser \
        --allow-root \
        --notebook-dir=$WORKSPACE \
        --NotebookApp.token='' \
        --NotebookApp.password='' \
        --NotebookApp.disable_check_xsrf=True \
        --NotebookApp.allows_root=True \
        > /var/log/jupyter.log 2>&1 &
    
    JUPYTER_PID=$!
    sleep 3
    
    if kill -0 $JUPYTER_PID 2>/dev/null; then
        log_success "Jupyter Notebook started (port 8888, PID: $JUPYTER_PID)"
        echo "  Access: http://<pod-ip>:8888"
    else
        log_warn "Failed to start Jupyter (see /var/log/jupyter.log)"
    fi
else
    log_info "Jupyter disabled (set ENABLE_JUPYTER=1 to enable)"
fi

# ============================================================================
# 5. FileBrowser Setup (Optimized for Speed)
# ============================================================================

log_info "Launching FileBrowser (optimized performance)..."

# Create optimized filebrowser config for faster performance
mkdir -p /tmp/filebrowser
cat > /tmp/filebrowser-config.json <<'EOF'
{
  "address": "0.0.0.0",
  "port": 8080,
  "baseURL": "",
  "database": "/tmp/filebrowser.db",
  "root": "/workspace",
  "logLevel": "error",
  "enableThumbs": false,
  "enableExec": true,
  "enableSearch": true
}
EOF

# Start FileBrowser in background with performance optimizations
# Using /tmp for database (faster I/O) and minimal logging (reduce overhead)
nohup filebrowser \
    -r $WORKSPACE \
    -a 0.0.0.0 \
    -p 8080 \
    -d /tmp/filebrowser.db \
    > /var/log/filebrowser.log 2>&1 &

FILEBROWSER_PID=$!
sleep 2

if kill -0 $FILEBROWSER_PID 2>/dev/null; then
    log_success "FileBrowser started (port 8080, PID: $FILEBROWSER_PID)"
    echo "  Access: http://<pod-ip>:8080"
else
    log_warn "Failed to start FileBrowser (see /var/log/filebrowser.log)"
fi

# ============================================================================
# 6. ComfyUI Server
# ============================================================================

log_info "========================================"
log_info "Starting ComfyUI Server"
log_info "========================================"

# Check if ComfyUI directory exists
if [ ! -d "$COMFYUI_DIR" ]; then
    log_error "ComfyUI directory not found: $COMFYUI_DIR"
    exit 1
fi

# Log file for ComfyUI
COMFYUI_LOG="/var/log/comfyui.log"

# Build ComfyUI startup command
COMFYUI_CMD="cd $COMFYUI_DIR && python main.py --listen 0.0.0.0 --port 8188"

# Add extra arguments based on environment
if [ "$DEBUG" = "1" ]; then
    COMFYUI_CMD="$COMFYUI_CMD --verbose"
    log_info "Debug mode enabled - verbose output"
fi

# For Serverless mode, use different handlers
if [ "$IS_SERVERLESS" = "true" ]; then
    log_info "Serverless mode detected"
    log_info "Note: Serverless requires additional API handlers (not yet configured)"
    COMFYUI_CMD="$COMFYUI_CMD --disable-auto-launch"
fi

# Log startup
log_info "Command: $COMFYUI_CMD"
log_info "Logs: $COMFYUI_LOG"
log_info "Web UI: http://0.0.0.0:8188"

# Start ComfyUI (foreground, logs to file)
$COMFYUI_CMD 2>&1 | tee $COMFYUI_LOG

# If we reach here, ComfyUI exited
log_error "ComfyUI process exited"
exit 1
