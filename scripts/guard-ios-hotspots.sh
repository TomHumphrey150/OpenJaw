#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

declare -a limits=(
  "ios/Telocare/Telocare/Sources/Features/ExploreTabShell.swift:250"
  "ios/Telocare/Telocare/Sources/App/AppViewModel.swift:2200"
  "ios/Telocare/Telocare/Sources/App/RootViewModel.swift:300"
  "ios/Telocare/Telocare/Sources/Health/MuseSDK/MuseSDKSessionService.swift:1000"
  "ios/Telocare/Telocare/Sources/App/DashboardSnapshotBuilder.swift:800"
  "ios/Telocare/Telocare/Sources/Data/UserDataDocument.swift:750"
)

failed=0
for entry in "${limits[@]}"; do
  file="${entry%%:*}"
  limit="${entry##*:}"

  if [[ ! -f "$file" ]]; then
    echo "missing file: $file"
    failed=1
    continue
  fi

  line_count="$(wc -l < "$file" | tr -d ' ')"
  if (( line_count > limit )); then
    echo "hotspot limit exceeded: $file has $line_count lines (limit $limit)"
    failed=1
  else
    echo "ok: $file has $line_count lines (limit $limit)"
  fi
 done

if (( failed != 0 )); then
  exit 1
fi
