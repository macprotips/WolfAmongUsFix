#!/bin/bash
# Runs the shader patching tests natively, with the address and undefined-behaviour sanitizers.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
cc -std=c11 -Wall -Wextra -O1 -g -fsanitize=address,undefined -DFIXTURES="\"$PWD/tests\"" \
    -o build/test_core tests/test_core.c fix/wolffix_core.c
build/test_core
