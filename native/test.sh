#!/bin/sh
set -e
cd "$(dirname "$0")"
mkdir -p build
xcrun swiftc -Onone Shared/*.swift Tests/main.swift -o build/tests
./build/tests
