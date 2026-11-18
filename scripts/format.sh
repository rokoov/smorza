#!/bin/bash
# Formats every Swift file in place with swift-format and the repo's .swift-format (SwiftNIO's settings).
set -euo pipefail
cd "$(dirname "$0")/.."

swift format format --in-place --parallel --recursive Package.swift Sources Checks scripts
