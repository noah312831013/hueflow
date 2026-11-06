#!/bin/sh
# Regenerates site/assets/cards/ and site/assets/patterns/ (the website's gallery and pattern showcase) from the app's presets and renderer.
set -e
cd "$(dirname "$0")"
mkdir -p build
xcrun swiftc -O Shared/*.swift Tools/SiteThumbs/main.swift -o build/site-thumbs
./build/site-thumbs ../site/assets
