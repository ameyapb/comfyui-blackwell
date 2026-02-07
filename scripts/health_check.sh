#!/bin/bash
##############################################################################
# health_check.sh - GPU/CUDA/PyTorch Health Verification
# ==============================================================================
# Verifies:
# - CUDA runtime is available and version
# - NVIDIA drivers loaded
# - GPU is accessible
# - PyTorch installation and CUDA compatibility
# - GPU architecture support (especially Blackwell/sm_120)
##############################################################################

# IMPORTANT: Do NOT use 'set -e' - health checks should report issues gracefully
# without crashing the script. Warnings should not halt execution.

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Exit status
EXIT_OK=0
EXIT_WARN=1
EXIT_ERROR=2

# Counter for issues
ISSUES=0

echo -e "${BLUE}========================================"
echo "GPU/CUDA Health Check"
echo "========================================${NC}"
echo ""

# ============================================================================
# Check 1: NVIDIA Driver & GPU Detection
# ============================================================================

echo -e "${BLUE}[1] NVIDIA Driver & GPU Detection${NC}"

if command -v nvidia-smi &> /dev/null; then
    NVIDIA_SMI_OUTPUT=$(nvidia-smi)
    echo "$NVIDIA_SMI_OUTPUT"
    echo ""
    echo -e "${GREEN}✓ nvidia-smi available${NC}"
    
    # Extract CUDA version
    CUDA_VERSION=$(nvidia-smi | grep "CUDA Version:" | awk '{print $NF}')
    echo -e "${GREEN}✓ CUDA Runtime: $CUDA_VERSION${NC}"
    
    # Check for Blackwell (RTX 5090)
    if echo "$NVIDIA_SMI_OUTPUT" | grep -i "RTX 5090\|Blackwell"; then
        echo -e "${GREEN}✓ Blackwell GPU detected (RTX 5090) - sm_120${NC}"
    fi
    
    # Check for Ada (RTX 4090)
    if echo "$NVIDIA_SMI_OUTPUT" | grep -i "RTX 4090\|Ada"; then
        echo -e "${GREEN}✓ Ada GPU detected (RTX 4090) - sm_89${NC}"
    fi
else
    echo -e "${RED}✗ nvidia-smi not found${NC}"
    ((ISSUES++))
fi

echo ""

# ============================================================================
# Check 2: GPU Architecture (SM version)
# ============================================================================

echo -e "${BLUE}[2] GPU Architecture Detection${NC}"

GPU_ARCH=$(python3 -c "
import torch
if torch.cuda.is_available():
    major, minor = torch.cuda.get_device_capability(0)
    sm = major * 10 + minor
    names = {
        50: 'Maxwell',
        60: 'Pascal',
        70: 'Volta',
        75: 'Turing',
        80: 'Ampere',
        86: 'Ampere',
        89: 'Ada',
        90: 'Hopper',
        120: 'Blackwell'
    }
    print(f'sm_{sm} ({names.get(sm, \"Unknown\")})')
else:
    print('CPU-only')
" 2>/dev/null)

if [ -n "$GPU_ARCH" ] && [ "$GPU_ARCH" != "CPU-only" ]; then
    echo -e "${GREEN}✓ GPU Architecture: $GPU_ARCH${NC}"
else
    echo -e "${YELLOW}⚠ GPU Architecture: Not detected (CPU-only mode)${NC}"
    ((ISSUES++))
fi

echo ""

# ============================================================================
# Check 3: CUDA 13.0 Requirement for Blackwell
# ============================================================================

echo -e "${BLUE}[3] CUDA Version Check (Blackwell Requirement)${NC}"

if [ -n "$CUDA_VERSION" ]; then
    CUDA_MAJOR=$(echo $CUDA_VERSION | cut -d. -f1)
    
    if [ "$CUDA_MAJOR" -ge 13 ]; then
        echo -e "${GREEN}✓ CUDA $CUDA_VERSION (≥13.0 for Blackwell support)${NC}"
    else
        echo -e "${YELLOW}⚠ CUDA $CUDA_VERSION detected${NC}"
        echo "  Note: CUDA 13.0+ is required for RTX 5090 (Blackwell)"
        echo "  Older GPUs (RTX 4090, A100) may work with CUDA 12.8"
        ((ISSUES++))
    fi
else
    echo -e "${RED}✗ Could not determine CUDA version${NC}"
    ((ISSUES++))
fi

echo ""

# ============================================================================
# Check 4: PyTorch Installation
# ============================================================================

echo -e "${BLUE}[4] PyTorch Installation Check${NC}"

PYTORCH_CHECK=$(python3 -c "
import torch
print(f'PyTorch Version: {torch.__version__}')
print(f'CUDA Support: {torch.version.cuda}')
print(f'Compiled with CUDA: {torch.version.cuda}')
print(f'Available: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'Device: {torch.cuda.get_device_name(0)}')
" 2>&1)

echo "$PYTORCH_CHECK"

# Extract PyTorch CUDA version
PYTORCH_CUDA=$(echo "$PYTORCH_CHECK" | grep "CUDA Support:" | awk '{print $NF}')

if [ -n "$PYTORCH_CUDA" ]; then
    PYTORCH_CUDA_MAJOR=$(echo $PYTORCH_CUDA | cut -d. -f1)
    if [ "$PYTORCH_CUDA_MAJOR" -ge 13 ] 2>/dev/null; then
        echo -e "${GREEN}✓ PyTorch CUDA $PYTORCH_CUDA (≥13.0, Blackwell native)${NC}"
    elif [ "$PYTORCH_CUDA_MAJOR" -ge 12 ] 2>/dev/null; then
        echo -e "${YELLOW}⚠ PyTorch CUDA $PYTORCH_CUDA detected${NC}"
        echo "  Note: cu128 is forward-compatible with CUDA 13.0 runtime"
        echo "  RTX 5090 will work if RunPod provides CUDA 13.0 driver"
    else
        echo -e "${RED}✗ PyTorch CUDA $PYTORCH_CUDA may be too old${NC}"
        ((ISSUES++))
    fi
else
    echo -e "${RED}✗ Could not determine PyTorch CUDA version${NC}"
    ((ISSUES++))
fi

echo ""

# ============================================================================
# Check 5: PyTorch GPU Availability
# ============================================================================

echo -e "${BLUE}[5] PyTorch GPU Testing${NC}"

GPU_TEST=$(python3 -c "
import torch
if torch.cuda.is_available():
    print('✓ CUDA Available: True')
    print(f'Device Count: {torch.cuda.device_count()}')
    print(f'Current Device: {torch.cuda.current_device()}')
    
    # Test tensor creation
    x = torch.randn(1000, 1000).cuda()
    print(f'✓ Tensor on GPU: Success')
    print(f'✓ GPU Memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f} GB')
else:
    print('✗ CUDA Available: False')
    exit(1)
" 2>&1)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}$GPU_TEST${NC}"
else
    echo -e "${RED}$GPU_TEST${NC}"
    ((ISSUES++))
fi

echo ""

# ============================================================================
# Check 6: Compatibility Summary
# ============================================================================

echo -e "${BLUE}[6] Compatibility Summary${NC}"

if [[ "$GPU_ARCH" == *"sm_120"* ]]; then
    # Blackwell-specific checks
    if [ "$CUDA_MAJOR" -ge 13 ] 2>/dev/null; then
        PYTORCH_CUDA_MAJOR=$(echo $PYTORCH_CUDA | cut -d. -f1)
        if [ "$PYTORCH_CUDA_MAJOR" -ge 12 ] 2>/dev/null; then
            echo -e "${GREEN}✓ Blackwell (RTX 5090) Compatible${NC}"
            echo "  CUDA $CUDA_VERSION runtime + PyTorch CUDA $PYTORCH_CUDA = Ready"
        else
            echo -e "${YELLOW}⚠ Blackwell detected but PyTorch CUDA version may be incompatible${NC}"
            echo "  Need: CUDA ≥12.8, Found: $PYTORCH_CUDA"
            ((ISSUES++))
        fi
    else
        echo -e "${RED}✗ Blackwell requires CUDA 13.0+ runtime, found: $CUDA_VERSION${NC}"
        ((ISSUES++))
    fi
elif [[ "$GPU_ARCH" == *"sm_89"* ]]; then
    echo -e "${GREEN}✓ Ada (RTX 4090) Fully Compatible${NC}"
    echo "  CUDA $CUDA_VERSION + PyTorch cu128/cu130 = Ready"
else
    echo -e "${GREEN}✓ GPU detected and PyTorch available${NC}"
fi

echo ""

# ============================================================================
# Final Result
# ============================================================================

echo -e "${BLUE}========================================"
if [ $ISSUES -eq 0 ]; then
    echo -e "Status: ${GREEN}✓ ALL CHECKS PASSED${NC}"
    echo "=======================================${NC}"
    exit 0
elif [ $ISSUES -le 2 ]; then
    echo -e "Status: ${YELLOW}⚠ WARNINGS DETECTED ($ISSUES)${NC}"
    echo -e "The pod may work, but GPU support might be limited"
    echo "=======================================${NC}"
    exit 0  # Still pass for startup
else
    echo -e "Status: ${RED}✗ CRITICAL ISSUES ($ISSUES)${NC}"
    echo -e "GPU/CUDA may not be properly configured"
    echo "=======================================${NC}"
    exit 1
fi
