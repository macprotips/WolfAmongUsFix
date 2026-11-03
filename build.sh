#!/bin/bash
# Builds the fix's d3d11.dll into build/ (needs `brew install mingw-w64`).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -Wno-unused-parameter -Wno-cast-function-type -Wno-missing-field-initializers \
    -shared -static-libgcc -s -Wl,--no-insert-timestamp \
    -o build/d3d11.dll fix/wolffix.c fix/wolffix_core.c fix/wolffix.def -ldxguid
echo "built build/d3d11.dll"
