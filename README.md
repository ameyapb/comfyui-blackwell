# ComfyUI Qwen Image Edit - Blackwell Ready

Production-grade RunPod template for **ComfyUI** with **Qwen Image Edit Rapid** models. Pre-configured for **RTX 5090 (Blackwell)**, RTX 4090, and A100 GPUs. All models (~38 GB) pre-loaded in the Docker image.

## ⚡ Quick Start

1. Deploy template on [RunPod](https://www.runpod.io)
2. Wait 2-3 minutes for startup
3. Access services:
   - **ComfyUI**: `http://<pod-ip>:8188`
   - **Jupyter Notebook**: `http://<pod-ip>:8888`
   - **FileBrowser**: `http://<pod-ip>:8080`
   - **SSH**: `ssh root@<pod-ip>`

## ✨ What's Included

- ✅ **Qwen-Rapid-AIO-NSFW-v11.4** (28.4 GB checkpoint)
- ✅ **qwen_2.5_vl_7b_fp8_scaled** (9.38 GB text encoder)
- ✅ **qwen_image_vae** (254 MB variational autoencoder)
- ✅ **CUDA 13.0** + **PyTorch cu130** (Blackwell optimized)
- ✅ **ComfyUI Manager**, KJNodes, Civicomfy custom nodes
- ✅ **Jupyter**, FileBrowser, FFmpeg (NVENC), OpenSSH

## 🛠️ Customize on Startup

Set these environment variables in RunPod before launching:

```bash
ENABLE_JUPYTER=1    # 0 to disable Jupyter on startup
DEBUG=0             # 1 to enable verbose logs
```

## 🔧 Supported GPUs

| GPU | Status | Notes |
|-----|--------|-------|
| RTX 5090 (Blackwell) | ✅ Primary | Requires CUDA 13.0+ |
| RTX 4090 (Ada) | ✅ Full support | CUDA 12.8+ |
| A100 (Ampere) | ✅ Full support | Older CUDA versions ok |

## 🆘 Troubleshooting

**GPU not detected?**
```bash
# Inside pod, check:
nvidia-smi
python -c "import torch; print(torch.cuda.is_available())"
```

**ComfyUI won't load?**
- Check logs: `docker logs <container-id>`
- Verify GPU is working: `nvidia-smi`
- Test API: `curl http://<pod-ip>:8188/api`

**Models missing?**
- Models are pre-baked into the Docker image (~45-50 GB)
- Check: `ls -lh /workspace/models/checkpoints/`
- Should see `Qwen-Rapid-AIO-NSFW-v11.4.safetensors` (28.4 GB)

**Jupyter not accessible?**
- Verify `ENABLE_JUPYTER=1` is set
- Check listening ports: `ss -tlnp | grep 8888`

## 📝 Build Locally

```bash
git clone https://github.com/ameyapb/comfyui-blackwell
cd comfyui-blackwell

# Build image
docker build -t comfyui-blackwell:latest .

# Run locally
docker run -it --gpus all -p 8188:8188 -p 8888:8888 comfyui-blackwell:latest

# Visit http://localhost:8188
```

## 📊 Performance

| Metric | Value |
|--------|-------|
| Build time | ~45-60 min (first time) |
| Startup time | ~2-3 min |
| Image size | ~45-50 GB |
| RTX 5090 memory usage | ~20 GB |

## 📦 Files

- `Dockerfile` - Multi-stage build with CUDA 13.0
- `runpod-template.json` - RunPod template configuration
- `scripts/` - Startup and health check scripts

## 🔗 Links

- **Models**: [Phr00t/Qwen-Image-Edit-Rapid-AIO](https://huggingface.co/Phr00t/Qwen-Image-Edit-Rapid-AIO)
- **ComfyUI**: [ComfyUI GitHub](https://github.com/comfyanonymous/ComfyUI)
- **RunPod**: [Console](https://www.runpod.io/console)

---

**Last updated**: February 2026
