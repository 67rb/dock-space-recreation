#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build
swiftc -swift-version 5 Sources/Docklet/DockApplicationManager.swift Sources/Docklet/DockSlotPlan.swift Sources/Docklet/LayoutProfiles.swift Sources/Docklet/TimerStore.swift Sources/Docklet/StockStore.swift Sources/Docklet/WeatherStore.swift Tests/FeatureChecks/main.swift -o .build/DockFeatureChecks
.build/DockFeatureChecks
