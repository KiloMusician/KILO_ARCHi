#!/bin/bash
# Isolated, credential-free setup for the existing native ARCHi Reactor worker.
set -euo pipefail
archi_root="$(cd "$(dirname "$0")/.." && pwd)"
archi_runtime="$archi_root/output/creative-tools/reactor/runtime"
archi_python="${ARCHI_REACTOR_SETUP_PYTHON:-/Library/Frameworks/Python.framework/Versions/3.11/bin/python3}"
if [[ ! -x "$archi_python" ]]; then archi_python="$(command -v python3)"; fi
"$archi_python" -c 'import platform,sys; assert sys.version_info >= (3,10), "Python 3.10+ required"; assert platform.machine() == "arm64", "Use native Apple Silicon Python"'
if [[ ! -x "$archi_runtime/bin/python3" ]]; then "$archi_python" -m venv "$archi_runtime"; fi
"$archi_runtime/bin/python3" -m pip install --disable-pip-version-check --only-binary=:all: -r "$archi_root/desktop/Sources/ARCHiDesktop/Resources/ReactorBridge/requirements.txt"
"$archi_runtime/bin/python3" -I -c 'import importlib.metadata; from reactor_sdk._ffi import get_lib; from PIL import Image; import certifi; get_lib(); print("Reactor native runtime ready: SDK " + importlib.metadata.version("reactor-sdk"))'
printf '%s\n' "$archi_runtime/bin/python3"
