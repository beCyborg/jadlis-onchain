#!/usr/bin/env bash
# evm-presence.sh <0xaddress> — where is this EVM address alive?
# One row per chain: outgoing tx count (nonce), native balance, and whether token
# transfers exist (Etherscan free chains / Blockscout). Read-only, keys never printed.
# A nonce of 0 does NOT mean empty: receive-only deposit addresses have nonce 0 —
# read the balance and token columns too.
set -uo pipefail
A=${1:-}; [[ "$A" =~ ^0x[0-9a-fA-F]{40}$ ]] || { echo "usage: evm-presence.sh 0x<40 hex>" >&2; exit 1; }
API="$(cd "$(dirname "$0")" && pwd)/api.sh"
hex2dec() { python3 -c "import sys;print(int(sys.argv[1],16))" "${1:-0x0}" 2>/dev/null || echo "?"; }
wei2() { python3 -c "import sys;print(f'{int(sys.argv[1],16)/1e18:.6f}')" "${1:-0x0}" 2>/dev/null || echo "?"; }

# chain | rpc name | etherscan chainid (free key) or - | blockscout name or -
CHAINS="ethereum eth 1 eth
bsc bsc - -
base base - -
arbitrum arbitrum 42161 -
polygon polygon 137 -
optimism optimism - optimism
avalanche avax - -
linea linea 59144 -
gnosis gnosis - -"

printf '%-10s %8s %16s  %s\n' chain nonce native tokens
while read -r name rpc cid bs; do
  n=$("$API" rpc "$rpc" eth_getTransactionCount "[\"$A\",\"latest\"]" 2>/dev/null | jq -r '.result // empty')
  b=$("$API" rpc "$rpc" eth_getBalance "[\"$A\",\"latest\"]" 2>/dev/null | jq -r '.result // empty')
  tok="-"
  if [ "$cid" != "-" ]; then
    c=$("$API" etherscan "$cid" "module=account&action=tokentx&address=$A&page=1&offset=1" 2>/dev/null | jq -r 'if (.result|type)=="array" then (.result|length) else "err" end')
    tok=$([ "$c" = 1 ] && echo "yes (etherscan)" || { [ "$c" = 0 ] && echo "none (etherscan)" || echo "? (etherscan)"; })
    sleep 0.4
  elif [ "$bs" != "-" ]; then
    t=$("$API" blockscout "$bs" "/addresses/$A" 2>/dev/null | jq -r '.has_token_transfers // empty' 2>/dev/null)
    case "$t" in true) tok="yes (blockscout)";; false) tok="none (blockscout)";; *) tok="none/unknown (blockscout: address not indexed)";; esac
  else
    # No free history source here: read current USDC/USDT balances straight from the contracts.
    case "$name" in
      base)      st="USDC:0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913:6 USDT:0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2:6" ;;
      bsc)       st="USDT:0x55d398326f99059fF775485246999027B3197955:18 USDC:0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d:18" ;;
      avalanche) st="USDC:0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E:6 USDT:0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7:6" ;;
      gnosis)    st="USDC:0xDDAfbb505ad214D7b80b1f830fcCc89B60fb7A83:6 USDT:0x4ECaBa5870353805a9F068101A40E0f32ed605C6:6" ;;
      *)         st="" ;;
    esac
    parts=""
    for s in $st; do
      sy=${s%%:*}; rest=${s#*:}; ca=${rest%%:*}; dec=${rest##*:}
      r=$("$API" rpc "$rpc" eth_call "[{\"to\":\"$ca\",\"data\":\"0x70a08231000000000000000000000000${A:2}\"},\"latest\"]" 2>/dev/null | jq -r '.result // empty')
      v=$(python3 -c "import sys;print(f'{int(sys.argv[1],16)/10**int(sys.argv[2]):.2f}')" "${r:-0x0}" "$dec" 2>/dev/null || echo "?")
      parts="$parts $sy=$v"
    done
    tok="history n/a (no free indexer); balances:${parts:- none}"
  fi
  printf '%-10s %8s %16s  %s\n' "$name" "$( [ -n "$n" ] && hex2dec "$n" || echo err)" "$( [ -n "$b" ] && wei2 "$b" || echo err)" "$tok"
done <<< "$CHAINS"
