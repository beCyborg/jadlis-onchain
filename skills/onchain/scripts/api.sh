#!/usr/bin/env bash
# api.sh — read-only gateway to on-chain data APIs for the /onchain skill.
# Injects API keys from env vars or the macOS Keychain (service "jadlis") and NEVER prints them.
#
# Usage:
#   api.sh etherscan <chainid> '<query>'        GET api.etherscan.io/v2/api?chainid=…&<query>&apikey=…
#                                               e.g. api.sh etherscan 1 'module=account&action=tokentx&address=0x…&page=1&offset=100&sort=desc'
#   api.sh trongrid '<path?query>'              GET api.trongrid.io<path>      (header TRON-PRO-API-KEY)
#   api.sh trongrid-post '<path>' '<json>'      POST api.trongrid.io<path>     (read-only /wallet* and /walletsolidity* calls only)
#   api.sh tronscan '<path?query>'              GET apilist.tronscanapi.com<path> (header TRON-PRO-API-KEY)
#   api.sh blockscout <chain> '<path?query>'    GET https://<host>/api/v2<path>  chain: eth|optimism|scroll|zksync|celo|unichain|ink|soneium|<full host>
#                                               (base/arbitrum/polygon/gnosis hosts answer 403 to scripts; BSC has no Blockscout)
#   api.sh bsmeta <chainId> '<0xA,0xB,…>'       Blockscout metadata service: public labels/tags for EVM addresses, keyless
#   api.sh rpc <chain> <method> '<params-json>' JSON-RPC to a keyless public node  chain: eth|bsc|base|arbitrum|polygon|optimism|avax|linea|gnosis
#
# Output: raw JSON on stdout. Errors on stderr with the key redacted; exit 3 = HTTP/API error, 1 = usage, 4 = blocked write call.
set -uo pipefail

# Key lookup: environment variable first, then the macOS Keychain (service "jadlis", account = key name).
key() { if [ -n "${!1:-}" ]; then printf '%s' "${!1}"; else command -v security >/dev/null && security find-generic-password -s jadlis -a "$1" -w 2>/dev/null; fi; }
redact() { sed -E 's/(apikey=)[^&" ]+/\1***/g'; }
usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 1; }

# One retry on 429 / rate-limit and on 5xx (Blockscout throws transient 500s), then fail loudly.
# Redirects are NOT followed (a key header must never travel to another host): 3xx = error with the target.
fetch() { # fetch <curl args...>
  local out code loc i
  for i in 1 2; do
    out=$(curl -sS -m 30 -w $'\n%{redirect_url}\n%{http_code}' "$@" 2>&1) || { echo "curl failed: $(printf '%s' "$out" | redact | tail -1)" >&2; return 3; }
    code=${out##*$'\n'}; out=${out%$'\n'*}; loc=${out##*$'\n'}; out=${out%$'\n'*}
    if [ "$code" = 429 ] || printf '%s' "$out" | head -c 600 | grep -qiE 'rate limit|Max calls per sec|too many requests'; then
      [ $i = 1 ] && { sleep 1.2; continue; }
    fi
    if [ "${code:-0}" -ge 500 ] 2>/dev/null && [ $i = 1 ]; then sleep 2.5; continue; fi
    break
  done
  if [ "${code:-0}" -ge 300 ] 2>/dev/null && [ "$code" -lt 400 ]; then
    echo "HTTP $code redirect to: $(printf '%s' "$loc" | redact) — call that path/host directly" >&2; return 3
  fi
  if [ "${code:-000}" -ge 400 ] 2>/dev/null; then
    echo "HTTP $code: $(printf '%s' "$out" | head -c 400 | redact)" >&2; printf '%s\n' "$out"; return 3
  fi
  printf '%s\n' "$out"
}

# Read-only guard for TRON full-node paths (GET and POST alike).
tron_guard() {
  case "$1" in
    */broadcast*|*/create*|*/freeze*|*/unfreeze*|*/vote*|*/deploy*|*/transfer*|*/withdraw*|*/delegate*|*/undelegate*|*/updateaccount*|*/triggersmartcontract*|*/easytransfer*|*/gettransactionsign*|*/addtransactionsign*|*/generateaddress*|*/createaddress*)
      echo "blocked: $1 builds, signs or sends a transaction — this skill is read-only (use triggerconstantcontract for contract reads)" >&2; exit 4 ;;
  esac
}
# FullNode /wallet* answers errors with HTTP 200: {"Error":…} or {"result":{"code":…,"message":<hex>}}.
tron_check() {
  local e
  e=$(printf '%s' "$1" | jq -r 'if type=="object" and .Error then .Error elif type=="object" and (.result|type)=="object" and .result.code and (.result.result|not) then "\(.result.code): \(.result.message // "")" else empty end' 2>/dev/null)
  if [ -n "$e" ]; then
    case "$e" in *:\ [0-9a-fA-F]*) e="$e ($(printf '%s' "${e#*: }" | xxd -r -p 2>/dev/null))";; esac
    echo "tron node error: $e" >&2; return 3
  fi
}

svc=${1:-}; shift || true
case "$svc" in
  etherscan)
    [ $# -ge 2 ] || usage
    k=$(key ETHERSCAN_API_KEY) || { echo "ETHERSCAN_API_KEY missing in Keychain (run: crypttrace-key etherscan)" >&2; exit 1; }
    out=$(fetch "https://api.etherscan.io/v2/api?chainid=$1&$2&apikey=$k") ; rc=$?
    printf '%s\n' "$out"
    # Etherscan answers HTTP 200 with status "0" on errors; surface the message (but "No transactions found" is a valid empty result).
    msg=$(printf '%s' "$out" | jq -r 'if .error then "JSON-RPC error: \(.error|tostring)" elif .status=="0" then "\(.message): \(.result|tostring)" else empty end' 2>/dev/null)
    if [ -n "$msg" ] && ! printf '%s' "$msg" | grep -qE 'No transactions found|No records? found|No data found|No token transfers'; then
      echo "etherscan error: $(printf '%s' "$msg" | redact | head -c 300)" >&2; exit 3
    fi
    exit $rc ;;
  trongrid|tronscan)
    [ $# -ge 1 ] || usage
    k=$(key "$( [ "$svc" = trongrid ] && echo TRONGRID_API_KEY || echo TRONSCAN_API_KEY )")
    host=$( [ "$svc" = trongrid ] && echo https://api.trongrid.io || echo https://apilist.tronscanapi.com )
    hdr=(); [ -n "$k" ] && hdr=(-H "TRON-PRO-API-KEY: $k")
    [ "$svc" = trongrid ] && tron_guard "${1%%\?*}"
    out=$(fetch "${hdr[@]}" "$host$1"); rc=$?; printf '%s\n' "$out"
    [ $rc = 0 ] && [ "$svc" = trongrid ] && { tron_check "$out" || rc=3; }
    exit $rc ;;
  trongrid-post)
    [ $# -ge 2 ] || usage
    tron_guard "$1"
    case "$1" in
      /wallet/*|/walletsolidity/*) ;;
      *) echo "trongrid-post accepts only /wallet/* and /walletsolidity/* paths" >&2; exit 1 ;;
    esac
    k=$(key TRONGRID_API_KEY); hdr=(-H 'content-type: application/json'); [ -n "$k" ] && hdr+=(-H "TRON-PRO-API-KEY: $k")
    out=$(fetch -X POST "${hdr[@]}" --data "$2" "https://api.trongrid.io$1"); rc=$?; printf '%s\n' "$out"
    [ $rc = 0 ] && { tron_check "$out" || rc=3; }
    exit $rc ;;
  blockscout)
    [ $# -ge 2 ] || usage
    case "$1" in
      eth) h=eth.blockscout.com ;; optimism) h=explorer.optimism.io ;; scroll) h=scrollscan.com ;;
      zksync) h=zksync.blockscout.com ;; celo) h=celo.blockscout.com ;; unichain) h=unichain.blockscout.com ;;
      ink) h=explorer.inkonchain.com ;; soneium) h=soneium.blockscout.com ;;
      base|arbitrum|polygon|gnosis) echo "blockscout $1: public host is behind Cloudflare (HTTP 403, checked 2026-11-09). Use: etherscan (arbitrum 42161, polygon 137), rpc, or bsmeta for labels" >&2; exit 3 ;;
      bsc) echo "no Blockscout instance for BSC — use rpc bsc" >&2; exit 3 ;;
      *.*) h=$1 ;;
      *) echo "unknown blockscout chain: $1" >&2; exit 1 ;;
    esac
    fetch "https://$h/api/v2$2"; exit $? ;;
  bsmeta)
    # Blockscout metadata service: public labels (exchange, SANCTIONED/OFAC, BLOCKED by USDT/USDC, exploit) for any EVM chain id, keyless.
    [ $# -ge 2 ] || usage
    fetch "https://metadata.services.blockscout.com/api/v1/metadata?addresses=$2&chainId=$1"; exit $? ;;
  rpc)
    [ $# -ge 2 ] || usage
    case "$1" in
      eth) u=https://ethereum-rpc.publicnode.com ;; bsc) u=https://bsc-rpc.publicnode.com ;; base) u=https://base-rpc.publicnode.com ;;
      arbitrum) u=https://arbitrum-one-rpc.publicnode.com ;; polygon) u=https://polygon-bor-rpc.publicnode.com ;;
      optimism) u=https://optimism-rpc.publicnode.com ;; avax) u=https://avalanche-c-chain-rpc.publicnode.com ;;
      linea) u=https://linea-rpc.publicnode.com ;; gnosis) u=https://gnosis-rpc.publicnode.com ;;
      http*) u=$1 ;; *) echo "unknown rpc chain: $1" >&2; exit 1 ;;
    esac
    case "$2" in eth_sendRawTransaction|eth_sendTransaction|eth_sign*|personal_*) echo "blocked: $2 — read-only skill" >&2; exit 4 ;; esac
    out=$(fetch -X POST -H 'content-type: application/json' --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$2\",\"params\":${3:-[]}}" "$u"); rc=$?; printf '%s\n' "$out"
    e=$(printf '%s' "$out" | jq -r '.error // empty | tostring' 2>/dev/null)
    [ -n "$e" ] && { echo "rpc error: $e" >&2; rc=3; }
    exit $rc ;;
  *) usage ;;
esac
