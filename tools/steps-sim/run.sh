#!/bin/sh
# Builds and runs the floor-reader simulation on a Mac. Extra arguments: --seeds=N --noise=X --only=text --verbose
set -e
cd "$(dirname "$0")/../.."
mkdir -p build
xcrun swiftc -O -o build/steps-sim \
  FieldVision/FloorSteps.swift FieldVision/Lang.swift FieldVision/MathUtil.swift FieldVision/DepthEstimator.swift \
  tools/steps-sim/main.swift
./build/steps-sim "$@"
