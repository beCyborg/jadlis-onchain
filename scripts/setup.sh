#!/usr/bin/env bash
# setup.sh — install what the /onchain skill needs: the crypttrace CLI, a key-injecting
# wrapper and the crypttrace-key helper. Idempotent; never prints key values.
#
#   bash scripts/setup.sh            install or repair
#   bash scripts/setup.sh --check    report status only (keys by name and length)
#   bash scripts/setup.sh --bin-dir DIR   put the wrapper and helper into DIR (default ~/.local/bin)
#
# Keys (all free) live in the macOS Keychain as generic passwords, service "jadlis",
# account = ETHERSCAN_API_KEY | TRONSCAN_API_KEY | TRONGRID_API_KEY. On other systems
# export them as environment variables instead.
set -uo pipefail

BIN="$HOME/.local/bin"; CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1 ;;
    --bin-dir) BIN="$2"; shift ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done
REAL_DIR="$HOME/.local/share/crypttrace-bin"
REAL="$REAL_DIR/crypttrace"
KEYS="ETHERSCAN_API_KEY TRONSCAN_API_KEY TRONGRID_API_KEY"
ok() { printf '  ✓ %s\n' "$*"; }
no() { printf '  ✗ %s\n' "$*"; }

keylen() { # length only, never the value
  local v="${!1:-}"
  [ -z "$v" ] && command -v security >/dev/null && v=$(security find-generic-password -s jadlis -a "$1" -w 2>/dev/null)
  printf '%s' "${#v}"
}

status() {
  echo "crypttrace:"
  if [ -x "$REAL" ]; then ok "binary $("$REAL" --version 2>/dev/null | head -1 || echo installed) in $REAL_DIR"; else no "binary missing ($REAL)"; fi
  if [ -x "$BIN/crypttrace" ] && grep -q 'crypttrace wrapper' "$BIN/crypttrace" 2>/dev/null; then ok "wrapper $BIN/crypttrace"; else no "wrapper missing in $BIN"; fi
  if [ -x "$BIN/crypttrace-key" ]; then ok "helper $BIN/crypttrace-key"; else no "helper missing in $BIN"; fi
  local w; w=$(command -v crypttrace || true)
  case "$w" in "") no "crypttrace is not on PATH — add $BIN to PATH" ;; "$BIN/crypttrace") ok "PATH resolves crypttrace to the wrapper" ;; *) printf '  ! PATH resolves crypttrace to %s (a wrapper from an earlier setup is fine)\n' "$w" ;; esac
  echo "keys (free; optional but recommended):"
  for k in $KEYS; do n=$(keylen "$k"); [ "$n" -gt 0 ] && ok "$k present (length $n)" || no "$k missing"; done
  echo "tools:"
  for t in jq curl python3; do command -v "$t" >/dev/null && ok "$t" || no "$t missing"; done
}

if [ "$CHECK" = 1 ]; then status; exit 0; fi

command -v uv >/dev/null || { echo "uv is required: brew install uv  (or https://docs.astral.sh/uv/getting-started/installation/)" >&2; exit 1; }
for t in jq curl python3; do command -v "$t" >/dev/null || { echo "$t is required (brew install $t)" >&2; exit 1; }; done

echo "1/3 installing crypttrace into $REAL_DIR (kept off PATH; the wrapper calls it)…"
mkdir -p "$REAL_DIR" "$BIN"
UV_TOOL_BIN_DIR="$REAL_DIR" uv tool install --upgrade --python 3.12 "crypttrace[web]" >/dev/null 2>&1 \
  || UV_TOOL_BIN_DIR="$REAL_DIR" uv tool install --python 3.12 "crypttrace[web]" || { echo "uv tool install crypttrace failed" >&2; exit 1; }

echo "2/3 writing $BIN/crypttrace (wrapper) and $BIN/crypttrace-key (helper)…"
cat > "$BIN/crypttrace" <<WRAP
#!/usr/bin/env bash
# crypttrace wrapper (jadlis-onchain): exports optional free API keys from the environment
# or the macOS Keychain (service "jadlis", account = key name) and runs the real binary.
set -uo pipefail
for k in $KEYS; do
  if [ -z "\${!k:-}" ] && command -v security >/dev/null; then
    v=\$(security find-generic-password -s jadlis -a "\$k" -w 2>/dev/null) && [ -n "\$v" ] && export "\$k=\$v"
  fi
done
unset v
exec "$REAL" "\$@"
WRAP
cat > "$BIN/crypttrace-key" <<'HELP'
#!/usr/bin/env bash
# crypttrace-key (jadlis-onchain): save an API key from the clipboard into the macOS Keychain.
# Usage: copy the key, then `crypttrace-key etherscan|tronscan|trongrid`. Prints only the length.
set -uo pipefail
case "${1:-}" in
  etherscan) name=ETHERSCAN_API_KEY ;; tronscan) name=TRONSCAN_API_KEY ;; trongrid) name=TRONGRID_API_KEY ;;
  *) echo "usage: crypttrace-key etherscan|tronscan|trongrid  (key must be in the clipboard)" >&2; exit 1 ;;
esac
command -v security >/dev/null && command -v pbpaste >/dev/null || { echo "macOS only — elsewhere export $name in your shell profile" >&2; exit 1; }
val=$(pbpaste | tr -d '[:space:]')
if [ -z "$val" ] || [ "${#val}" -lt 16 ] || [ "${#val}" -gt 128 ]; then
  echo "clipboard does not look like an API key (length ${#val}); copy the key and retry" >&2; exit 1
fi
security add-generic-password -U -s jadlis -a "$name" -w "$val" || exit 1
[ "$(security find-generic-password -s jadlis -a "$name" -w 2>/dev/null)" = "$val" ] && echo "saved $name (length ${#val})" || { echo "save failed for $name" >&2; exit 1; }
HELP
chmod +x "$BIN/crypttrace" "$BIN/crypttrace-key"

echo "3/3 downloading label lists (OFAC, ScamSniffer)…"
"$BIN/crypttrace" update-labels 2>&1 | tail -1

echo; status
cat <<'NEXT'

Next — three free keys (each sign-up is email + password):
  Etherscan  https://etherscan.io/register  → https://etherscan.io/myapikey (Ethereum, Polygon, Arbitrum, Linea…)
  Tronscan   https://tronscan.org/#/myaccount/apiKeys  (Tron labels and risk; keyless access is being throttled)
  TronGrid   https://www.trongrid.io/register  → dashboard → API key (higher Tron rate limit)
Copy each key and run:  crypttrace-key etherscan | crypttrace-key tronscan | crypttrace-key trongrid
NEXT
