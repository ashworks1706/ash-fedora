#!/usr/bin/env bash

set -euo pipefail

direction="${1:-}"

if [[ "$direction" != "r-1" && "$direction" != "r+1" ]]; then
  echo "Usage: $0 r-1|r+1" >&2
  exit 1
fi

if ! command -v hyprctl >/dev/null 2>&1; then
  echo "hyprctl not found" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found" >&2
  exit 1
fi

current_workspace="$(hyprctl activeworkspace -j | jq -r '.id')"

mapfile -t addresses < <(
  hyprctl clients -j \
    | jq -r --argjson workspace "$current_workspace" '.[] | select(.workspace.id == $workspace) | .address'
)

for address in "${addresses[@]}"; do
  hyprctl dispatch movetoworkspacesilent "$direction,address:$address" >/dev/null
done

hyprctl dispatch workspace "$direction" >/dev/null

