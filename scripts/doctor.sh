#!/usr/bin/env bash
set -euo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
errors=0

check_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "[ok] $cmd"
  else
    echo "[missing] $cmd"
    errors=$((errors + 1))
  fi
}

echo "Checking core tools..."
check_cmd hyprland
check_cmd hyprctl
check_cmd quickshell
check_cmd kitty
check_cmd jq
check_cmd nmcli
check_cmd secret-tool
check_cmd rsync

echo
echo "Checking config placeholders..."
if rg -n "__HOME__" "$XDG_CONFIG_HOME/hypr" "$XDG_CONFIG_HOME/illogical-impulse" >/dev/null 2>&1; then
  echo "[warn] Found unresolved __HOME__ placeholders in active config."
  errors=$((errors + 1))
else
  echo "[ok] No unresolved __HOME__ placeholders."
fi

echo
echo "Checking GitHub token file (optional widget)..."
token_file="$XDG_CONFIG_HOME/quickshell/ii/secrets/github_token"
if [[ -f "$token_file" ]]; then
  perms="$(stat -c '%a' "$token_file" 2>/dev/null || echo unknown)"
  if [[ "$perms" != "600" ]]; then
    echo "[warn] $token_file should be chmod 600 (currently $perms)."
  else
    echo "[ok] token file permissions look good."
  fi
else
  echo "[info] token file not found (fine unless GitHub widget is enabled)."
fi

echo
if [[ "$errors" -gt 0 ]]; then
  echo "Doctor finished with $errors issue(s)."
  exit 1
fi

echo "Doctor finished clean."
