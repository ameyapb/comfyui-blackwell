#!/bin/bash
##############################################################################
# validate_models.sh - Model File Verification
# ==============================================================================
# Validates:
# - Model files exist in correct locations
# - File sizes match expected (detects incomplete downloads)
# - Files are not corrupted (checks for HTML error pages)
# - All required models for Qwen Image Edit Rapid workflow
##############################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

WORKSPACE="${WORKSPACE:-/workspace}"
MODEL_DIR="$WORKSPACE/models"

# Expected models with size validation (in GB)
declare -A MODELS=(
    ["checkpoints/Qwen-Rapid-AIO-NSFW-v11.4.safetensors"]="26"     # 28.4 GB
    ["text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors"]="8"     # 9.38 GB
    ["vae/qwen_image_vae.safetensors"]="0.2"                        # 254 MB
)

echo -e "${BLUE}========================================"
echo "Model File Validation"
echo "========================================${NC}"
echo ""

# Counter
FOUND=0
MISSING=0
CORRUPTED=0

# ============================================================================
# Validate each model
# ============================================================================

for model_path in "${!MODELS[@]}"; do
    full_path="$MODEL_DIR/$model_path"
    min_size_gb=${MODELS[$model_path]}
    # Convert GB to bytes using shell arithmetic (no bc required)
    # Handle decimal values: round down to integer
    min_size_gb_int=${min_size_gb%.*}  # Remove decimal part
    min_size_bytes=$((min_size_gb_int * 1024 * 1024 * 1024))
    
    echo -n "Checking: $model_path ... "
    
    if [ ! -f "$full_path" ]; then
        echo -e "${RED}✗ NOT FOUND${NC}"
        echo "  Expected: $full_path"
        ((MISSING++))
        continue
    fi
    
    # Get file size (portable: works on Linux and macOS without bc)
    if [ -f "$full_path" ]; then
        file_size=$(stat -f%z "$full_path" 2>/dev/null || stat -c%s "$full_path" 2>/dev/null || wc -c < "$full_path" 2>/dev/null)
    else
        file_size=0
    fi
    # Convert to GB (shell arithmetic, no bc needed)
    if [ "$file_size" -gt 0 ]; then
        file_size_gb=$((file_size / 1024 / 1024 / 1024))
    else
        file_size_gb=0
    fi
    
    # Check file size
    if [ "$file_size" -lt "$min_size_bytes" ]; then
        echo -e "${RED}✗ TOO SMALL${NC}"
        echo "  Size: $file_size_gb GB (expected ≥ $min_size_gb GB)"
        ((CORRUPTED++))
        continue
    fi
    
    # Check if file is HTML (common download error)
    if head -c 100 "$full_path" | grep -q -i "<!DOCTYPE\|<html"; then
        echo -e "${RED}✗ CORRUPTED (HTML)${NC}"
        echo "  File contains HTML (download error/auth failure)"
        ((CORRUPTED++))
        continue
    fi
    
    # Valid
    echo -e "${GREEN}✓ VALID${NC}"
    echo "  Size: $file_size_gb GB"
    ((FOUND++))
done

echo ""
echo -e "${BLUE}========================================"
echo "Validation Summary"
echo "========================================${NC}"
echo -e "Found:     ${GREEN}$FOUND${NC}"
echo -e "Missing:   ${YELLOW}$MISSING${NC}"
echo -e "Corrupted: ${RED}$CORRUPTED${NC}"
echo ""

# ============================================================================
# Directory listing for reference
# ============================================================================

if [ -d "$MODEL_DIR" ]; then
    echo -e "${BLUE}Model Directory Contents:${NC}"
    find "$MODEL_DIR" -type f -exec ls -lh {} \; 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
    echo ""
fi

# ============================================================================
# Final result
# ============================================================================

if [ $FOUND -eq ${#MODELS[@]} ] && [ $MISSING -eq 0 ] && [ $CORRUPTED -eq 0 ]; then
    echo -e "${GREEN}✓ All models validated successfully!${NC}"
    exit 0
elif [ $MISSING -eq 0 ] && [ $CORRUPTED -eq 0 ]; then
    echo -e "${YELLOW}⚠ Found $FOUND/${#MODELS[@]} required models${NC}"
    echo "  Some optional models may be missing, but core models are present"
    exit 0
elif [ $CORRUPTED -gt 0 ]; then
    echo -e "${RED}✗ Model validation FAILED${NC}"
    echo "  Corrupted files detected. Models may need to be re-downloaded:"
    echo "  See DEVELOPMENT.md or README.md for model update procedures"
    exit 1
else
    echo -e "${YELLOW}⚠ Some models are missing${NC}"
    echo "  This is normal if models are being downloaded on first startup"
    echo "  Wait 5-10 minutes for models to download via aria2c"
    exit 0
fi
