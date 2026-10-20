#!/bin/zsh
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"
mkdir -p .build
swiftc -swift-version 5 Sources/Docklet/DockApplicationManager.swift Sources/Docklet/DockSlotPlan.swift Tests/DockletTests/main.swift -o .build/DockLayoutChecks
.build/DockLayoutChecks
