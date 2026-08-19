#!/usr/bin/env bash
# Regenerates RoadTripPlanner.xcodeproj (and the derived Info-*.plist files)
# from project.yml. Run this after cloning and whenever project.yml changes.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen not found. Install it with 'brew install xcodegen'." >&2
    exit 1
fi

xcodegen generate
echo "Generated RoadTripPlanner.xcodeproj from project.yml"
