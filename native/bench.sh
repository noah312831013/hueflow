#!/bin/sh
# Prints the GPU time of a wallpaper frame for the presets and a heavy pattern case. See Tools/Bench/main.swift.
set -e
cd "$(dirname "$0")"
mkdir -p build
xcrun swiftc -O Shared/*.swift Tools/Bench/main.swift -o build/bench
./build/bench "$@"
