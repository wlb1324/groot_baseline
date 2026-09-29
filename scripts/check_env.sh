#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON="$REPO_ROOT/.venv/bin/python"
export UV_PROJECT_ENVIRONMENT="$REPO_ROOT/.venv"
export UV_CACHE_DIR="$REPO_ROOT/.cache/uv"
export UV_PYTHON_CACHE_DIR="$REPO_ROOT/.cache/python"
export UV_PYTHON_INSTALL_DIR="$REPO_ROOT/.tools/python"
export UV_PYTHON_BIN_DIR="$REPO_ROOT/.tools/bin/python"
export PYTORCH_NVML_BASED_CUDA_CHECK=1

if [[ ! -x "$PYTHON" ]]; then
    echo "ERROR: environment is missing; run scripts/setup_env.sh first." >&2
    exit 1
fi

if command -v nvidia-smi >/dev/null 2>&1; then
    echo "GPU name(s):"
    nvidia-smi --query-gpu=name --format=csv,noheader
else
    echo "GPU name(s): nvidia-smi not found"
fi

if command -v ffmpeg >/dev/null 2>&1; then
    echo "FFmpeg: $(ffmpeg -version | head -n 1)"
else
    echo "FFmpeg: not installed (official torchcodec video decoding requires FFmpeg 4-7)"
fi

"$PYTHON" - <<'PY'
import importlib.metadata as metadata
import sys

errors = []
expected_python = (3, 12, 14)
actual_python = sys.version_info[:3]
print(f"Python: {'.'.join(map(str, actual_python))}")
if actual_python != expected_python:
    errors.append(f"Python must be {'.'.join(map(str, expected_python))}")

expected_packages = {
    "torch": "2.9.0",
    "torchvision": "0.24.0",
    "transformers": "4.57.3",
    "diffusers": "0.35.1",
    "flash-attn": "2.8.3",
    "torchcodec": "0.8.0",
}
for distribution, expected in expected_packages.items():
    try:
        actual = metadata.version(distribution)
    except metadata.PackageNotFoundError:
        print(f"{distribution}: MISSING (expected {expected})")
        errors.append(f"missing {distribution}")
        continue
    normalized = actual.split("+", 1)[0]
    print(f"{distribution}: {actual}")
    if normalized != expected:
        errors.append(f"{distribution} must be {expected}, found {actual}")

try:
    import torch
    cuda_version = torch.version.cuda or "none"
    cuda_available = torch.cuda.is_available()
    print(f"torch.version.cuda: {cuda_version}")
    print(f"torch.cuda.is_available(): {cuda_available}")
    print(f"visible CUDA device count: {torch.cuda.device_count()}")
    if cuda_version != "12.8":
        errors.append(f"PyTorch CUDA runtime must be 12.8, found {cuda_version}")
    if not cuda_available:
        errors.append("CUDA is not visible to PyTorch")
except Exception as exc:
    print(f"PyTorch CUDA check: ERROR: {type(exc).__name__}: {exc}")
    errors.append("PyTorch CUDA check failed")

try:
    import gr00t
    print(f"import gr00t: OK ({gr00t.__file__})")
except Exception as exc:
    print(f"import gr00t: ERROR: {type(exc).__name__}: {exc}")
    errors.append("import gr00t failed")

if errors:
    print("Environment check: FAILED")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("Environment check: PASSED")
PY
