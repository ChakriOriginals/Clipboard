#!/usr/bin/env bash
# Static privacy rules (docs/SECURITY_MODEL.md §7). Exits non-zero on any violation.
#   1. No networking APIs in app or core sources.
#   2. No print/NSLog/debugPrint (could leak clipboard content to the console).
#   3. No os.Logger call that interpolates content-like values.
set -uo pipefail
root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
sources=("$root/Clipboard" "$root/Packages/ClipboardCore/Sources")
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
# Every interpolation inside a log call must be one of these non-content shapes.
log_allowlist='^\\\((ms|purged|corrupt\.count|[a-zA-Z]+Count|String\(describing: type\(of: error\)\))(, (format: \.fixed\(precision: [0-9]\), )?privacy: \.public)?\)$'
bad_logs=""
while IFS= read -r line; do
    file_line="${line%%:*}:$(echo "$line" | cut -d: -f2)"
    while IFS= read -r interp; do
        [[ -z "$interp" ]] && continue
        if ! [[ "$interp" =~ $log_allowlist ]]; then bad_logs+="    $file_line  $interp"$'\n'; fi
    done < <(echo "$line" | grep -oE '\\\([^()]*(\([^()]*(\([^()]*\))?[^()]*\))?[^()]*\)')
done < <(grep -rnE --include='*.swift' '(log|logger|Logger\([^)]*\))\.(debug|info|notice|error|fault|warning|critical|log|trace)\(|os_log\(' "${sources[@]}" 2>/dev/null)
if [[ -n "$bad_logs" ]]; then
    echo "✗ log interpolations limited to counts, timings and error types"
    printf "%s" "$bad_logs"
    status=1
else
    echo "✓ log interpolations limited to counts, timings and error types"
fi
exit $status
