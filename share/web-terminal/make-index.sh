#!/usr/bin/env bash
# Build the web terminal page: ttyd's built-in page + inject.html (font, colors,
# image paste, OSC 52 copy). Rerun after upgrading ttyd.
set -euo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Start a throwaway ttyd to fetch its stock page.
ttyd --interface lo --port 7699 true >/dev/null 2>&1 &
pid=$!
for _ in $(seq 1 20); do curl -fs -o "$tmp/base.html" http://127.0.0.1:7699/ && break; sleep 0.2; done
kill "$pid" 2>/dev/null || true
[[ -s "$tmp/base.html" ]] || { echo "couldn't fetch ttyd's page" >&2; exit 1; }

python3 - "$tmp/base.html" "$dir/inject.html" "$dir/index.html" <<'EOF'
import sys
base_path, inject_path, out_path = sys.argv[1:4]
base = open(base_path, encoding="utf-8").read()
inject = open(inject_path, encoding="utf-8").read()
assert "</body>" in base, "unexpected ttyd page"
open(out_path, "w", encoding="utf-8").write(base.replace("</body>", inject + "</body>", 1))
EOF
echo "wrote $dir/index.html"
