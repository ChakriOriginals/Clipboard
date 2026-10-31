#!/usr/bin/env bash
# Static privacy rules (docs/SECURITY_MODEL.md §7). Exits non-zero on any violation.
#   1. No networking APIs in app or core sources.
#   2. No print/NSLog/debugPrint (could leak clipboard content to the console).
#   3. No os.Logger call that interpolates content-like values.
set -uo pipefail
root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
sources=("$root/ClipFlow" "$root/Packages/ClipFlowCore/Sources")
status=0

check() {
    local description="$1" pattern="$2"
    local hits
    hits=$(grep -rnE --include='*.swift' "$pattern" "${sources[@]}" 2>/dev/null)
    if [[ -n "$hits" ]]; then
        echo "✗ $description"
        echo "$hits" | sed 's/^/    /'
        status=1
    else
        echo "✓ $description"
    fi
}

check "no networking APIs" '(URLSession|NWConnection|NWListener|NWBrowser|CFNetwork|^import Network)'
check "no print/NSLog/debugPrint" '(^|[^A-Za-z_.])(print|debugPrint|NSLog|dump)\('
check "no content interpolated into log calls" \
    '(log|logger|Logger\([^)]*\))\.(debug|info|notice|error|fault|warning|critical|log)\(.*\\\((preview|text|data|content|string|summary|snapshot|item|url|representation)'
exit $status
