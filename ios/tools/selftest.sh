#!/bin/sh
# 在 Mac 上编译运行核心逻辑自测（地图解析、地标、太阳位置、遮荫），不需要模拟器。
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)/selftest
swiftc -O -o "$OUT" \
  StreetWalk/Domain/Geo.swift StreetWalk/Domain/Polygon.swift \
  StreetWalk/Map/MapModel.swift StreetWalk/Map/OSMParser.swift StreetWalk/Map/LandmarkDeriver.swift StreetWalk/Map/PathGrid.swift \
  StreetWalk/Shade/SolarPosition.swift StreetWalk/Shade/ShadeCalculator.swift \
  tools/selftest/main.swift
"$OUT" "$(pwd)"
