#!/bin/sh
# 在 Mac 上编译运行核心逻辑自测（地图解析、地标、太阳位置、遮荫），不需要模拟器。
# 可选：STREETWALK_TILES=<放 v1/、v2/ 实时格子缓存的目录> ./tools/selftest.sh，再用实时格子检查选楼、地名、地标。
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)/selftest
swiftc -O -o "$OUT" \
  StreetWalk/Domain/Geo.swift StreetWalk/Domain/Polygon.swift \
  StreetWalk/Map/MapModel.swift StreetWalk/Map/OSMParser.swift StreetWalk/Map/LandmarkDeriver.swift StreetWalk/Map/PathGrid.swift StreetWalk/Map/MapModel+Locate.swift \
  StreetWalk/Services/HKOWeather.swift StreetWalk/Services/OpenMeteo.swift \
  StreetWalk/Shade/SolarPosition.swift StreetWalk/Shade/ShadeCalculator.swift \
  tools/selftest/main.swift
"$OUT" "$(pwd)"
