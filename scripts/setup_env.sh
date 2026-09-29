#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UV_VERSION="0.12.19"
PYTHON_VERSION="3.12.14"
EXPECTED_PYPROJECT_SHA256="a451af4cf723cc58b710a2f6f3a12a8d7f03850a39cc5ba420a18fcc20e2a3d0"
EXPECTED_UV_LOCK_SHA256="0d67d3b0dd41b28375bbc2351eefc9e064cbad2d1c40682a52b97fc625a60f19"

UV_BIN_DIR="$REPO_ROOT/.tools/bin"
UV_BIN="$UV_BIN_DIR/uv"
export UV_PROJECT_ENVIRONMENT="$REPO_ROOT/.venv"
export UV_CACHE_DIR="$REPO_ROOT/.cache/uv"
export UV_PYTHON_CACHE_DIR="$REPO_ROOT/.cache/python"
export UV_PYTHON_INSTALL_DIR="$REPO_ROOT/.tools/python"
export UV_PYTHON_BIN_DIR="$REPO_ROOT/.tools/bin/python"
export UV_MANAGED_PYTHON=1
export UV_NO_PROGRESS=1
export UV_LINK_MODE=copy

cd "$REPO_ROOT"

actual_pyproject_sha256="$(sha256sum pyproject.toml | awk '{print $1}')"
actual_uv_lock_sha256="$(sha256sum uv.lock | awk '{print $1}')"
if [[ "$actual_pyproject_sha256" != "$EXPECTED_PYPROJECT_SHA256" ]]; then
    echo "ERROR: pyproject.toml differs from the approved upstream snapshot." >&2
    exit 1
fi
if [[ "$actual_uv_lock_sha256" != "$EXPECTED_UV_LOCK_SHA256" ]]; then
    echo "ERROR: uv.lock differs from the approved upstream lock; refusing to resolve or sync." >&2
    exit 1
fi

mkdir -p "$UV_BIN_DIR" "$UV_CACHE_DIR" "$UV_PYTHON_CACHE_DIR" "$UV_PYTHON_INSTALL_DIR"

if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl is required to bootstrap the pinned uv release." >&2
    exit 1
fi

if [[ ! -x "$UV_BIN" ]] || [[ "$("$UV_BIN" --version | awk '{print $2}')" != "$UV_VERSION" ]]; then
    installer="$UV_CACHE_DIR/uv-installer-$UV_VERSION.sh"
    curl --proto '=https' --tlsv1.2 -LsSf \
        "https://releases.astral.sh/github/uv/releases/download/$UV_VERSION/uv-installer.sh" \
        -o "$installer"
    env UV_INSTALL_DIR="$UV_BIN_DIR" sh "$installer"
    rm -f "$installer"
fi

actual_uv_version="$("$UV_BIN" --version | awk '{print $2}')"
if [[ "$actual_uv_version" != "$UV_VERSION" ]]; then
    echo "ERROR: expected uv $UV_VERSION, found $actual_uv_version." >&2
    exit 1
fi

"$UV_BIN" python install "$PYTHON_VERSION"

if [[ -x /usr/local/cuda/bin/nvcc ]]; then
    export CUDA_HOME="/usr/local/cuda"
    export PATH="$CUDA_HOME/bin:$PATH"
fi

"$UV_BIN" sync --frozen --python "$PYTHON_VERSION" --no-progress

after_uv_lock_sha256="$(sha256sum uv.lock | awk '{print $1}')"
if [[ "$after_uv_lock_sha256" != "$EXPECTED_UV_LOCK_SHA256" ]]; then
    echo "ERROR: uv.lock changed during sync; refusing to continue." >&2
    exit 1
fi

"$REPO_ROOT/scripts/check_env.sh"
