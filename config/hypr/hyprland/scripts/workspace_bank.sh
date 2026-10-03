#!/usr/bin/env bash

# Two banks of six workspaces:
#   bank 1: 1-6
#   bank 2: 7-12
# Selecting a slot or changing banks preserves the slot number.

current_workspace="$(hyprctl activeworkspace -j | jq -r '.id')"

if ! [[ "$current_workspace" =~ ^[1-9][0-9]*$ ]]; then
  exit 1
fi

case "${1:-}" in
  select)
    slot="${2:-}"
    if ! [[ "$slot" =~ ^[1-6]$ ]]; then
      exit 2
    fi

    if (( current_workspace <= 6 )); then
      target_workspace="$slot"
    else
      target_workspace=$((slot + 6))
    fi
    ;;
  previous)
    # Stay in bank 1 when there is no previous bank.
    (( current_workspace > 6 )) || exit 0
    target_workspace=$((current_workspace - 6))
    ;;
  next)
    # This setup intentionally has only two banks.
    (( current_workspace <= 6 )) || exit 0
    target_workspace=$((current_workspace + 6))
    ;;
  *)
    echo "Usage: $0 select <1-6> | previous | next" >&2
    exit 2
    ;;
esac

hyprctl dispatch workspace "$target_workspace"
