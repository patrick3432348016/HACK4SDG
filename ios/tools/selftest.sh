#!/bin/sh
# Compile/run map, landmark, solar and shade core checks on Mac without a simulator.
# Optionally set STREETWALK_TILES to a directory containing v1/v2 tile caches for real-tile home/name/landmark checks.
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)/selftest
swiftc -O -o "$OUT" \
  Shared/Lang.swift StreetWalk/Domain/Geo.swift StreetWalk/Domain/Polygon.swift \
  StreetWalk/Map/MapModel.swift StreetWalk/Map/OSMParser.swift StreetWalk/Map/LandmarkDeriver.swift StreetWalk/Map/PathGrid.swift StreetWalk/Map/MapModel+Locate.swift \
  StreetWalk/Services/HKOWeather.swift StreetWalk/Services/OpenMeteo.swift \
  StreetWalk/Shade/SolarPosition.swift StreetWalk/Shade/ShadeCalculator.swift \
  tools/selftest/main.swift
"$OUT" "$(pwd)"
