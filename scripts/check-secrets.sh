#!/usr/bin/env bash
# Fail if anything that looks like a credential is about to be committed.
# Checks generic key/token patterns, plus exact strings listed one per line in
# local.secrets (gitignored; put your real passwords/tokens there).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

mapfile -t files < <(git ls-files -co --exclude-standard)
patterns='AIza[0-9A-Za-z_-]{30,}|ghp_[0-9A-Za-z]{30,}|github_pat_[0-9A-Za-z_]{30,}|gho_[0-9A-Za-z]{30,}|sk-[A-Za-z0-9_-]{30,}|sk-ant-[A-Za-z0-9_-]{20,}|npm_[A-Za-z0-9]{30,}|xox[abp]-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|"refresh_token" *: *"[^"]+"|"client_secret" *: *"[^"]+"|^ *password: *[^ _]'

found=0
if hits=$(grep -nIE "$patterns" -- "${files[@]}" 2>/dev/null); then
  echo "Possible secrets:"; echo "$hits" | cut -c1-160; found=1
fi
if [[ -f local.secrets ]]; then
  while IFS= read -r s; do
    [[ -z "$s" || "$s" == \#* ]] && continue
    if grep -lIF -- "$s" "${files[@]}" 2>/dev/null; then
      echo "^ contains a value from local.secrets"; found=1
    fi
  done < local.secrets
fi
for f in "${files[@]}"; do
  case "$f" in
    *token.json|*credentials.json|*client_secret*|*.pem|*.key|*sunshine_state.json|*/secrets/*|local.env|local.secrets)
      echo "Sensitive file in the tree: $f"; found=1 ;;
  esac
done

if [[ $found -eq 1 ]]; then
  echo "Secret check FAILED: fix the above before committing."; exit 1
fi
echo "Secret check passed (${#files[@]} files)."
