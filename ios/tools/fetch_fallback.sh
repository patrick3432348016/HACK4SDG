#!/bin/sh
# Refetch Queen's Hill fallback tile 0_0 using the App's query; Swift remains the only parser.
set -e
cd "$(dirname "$0")/.."
BBOX="22.5018715,114.1535787,22.5069285,114.1590213"
Q=$(sed "s/{{bbox}}/$BBOX/g" StreetWalk/Resources/estate.overpassql)
for i in 1 2 3; do
  if curl -sf --max-time 90 -A "hack4sdg-streetwalk/0.1" --data-urlencode "data=$Q" \
       https://overpass-api.de/api/interpreter -o StreetWalk/Resources/fallback_queenshill.json; then
    echo "ok: $(wc -c < StreetWalk/Resources/fallback_queenshill.json) bytes"; exit 0
  fi
  sleep $((i * 4))
done
echo "fetch failed" >&2; exit 1
