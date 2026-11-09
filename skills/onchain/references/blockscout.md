# Blockscout API v2 (REST) — reference for /onchain

Verified live 2026-11-09 through api.sh, keyless, on the public explorer hosts.

- Call: `api.sh blockscout <chain|host> '<path?query>'` → `GET https://<host>/api/v2<path>`. Aliases: `eth base optimism arbitrum polygon gnosis scroll zksync`; anything containing a dot is used as the host.
- Keyless public hosts: `x-ratelimit-limit: 10` per ~1 s window per IP (headers on eth.blockscout.com and scrollscan.com; `bypass-429-option: temporary_token`). Keep ≤4 req/s.
- Keyed Blockscout API (`https://api.blockscout.com/<chain_id>/api/v2/...`, docs): free key 5 RPS, 100K credits/day (20 credits per call, 30–50 for token-transfers/logs/internal/summary), resets 00:00 UTC; key via `apikey=` or `authorization` header. Keyless call → `402 {"error":"Proceed with API key or make a X402 payment to continue"}` (live). api.sh has no key for it.
- Docs warn: public per-chain hosts sit behind Cloudflare bot protection; scripted calls may get `403` HTML "Just a moment…" — not retryable. Confirmed live for Base, Arbitrum, Polygon, Gnosis (see host table).
- Units: every amount is a **decimal string in base units** (wei / token raw); divide by `10^decimals` (`token.decimals` is also a string). Timestamps are ISO-8601 UTC strings (`"2026-07-02T16:34:11.000000Z"`). `exchange_rate` = current USD price; tx `historic_exchange_rate` = price at the tx.
- Backend version decides paging rules: `api.sh blockscout <host> '/config/backend-version'`.

## Hosts (live check 2026-11-09, `/stats`)

| Chain (id) | Use with api.sh | Result | Version |
|---|---|---|---|
| Ethereum (1) | `eth` | ✅ JSON | v11.3.3 |
| OP Mainnet (10) | `explorer.optimism.io` | ✅ JSON | v11.3.3 |
| OP Mainnet | `optimism` alias (→ explorer.optimism.io since 2026-11-09) | ✅ | — |
| Scroll (534352) | `scrollscan.com` | ✅ JSON (Blockscout-run) | v12.0.4 |
| Scroll | `scroll` alias (→ scrollscan.com since 2026-11-09) | ✅ host answered in the agent probe | — |
| zkSync Era (324) | `zksync` | ✅ JSON | v12.0.4 |
| Celo (42220) | `celo.blockscout.com` | ✅ | v12.0.4 |
| Unichain (130) | `unichain.blockscout.com` | ✅ | v12.0.4 |
| Ink (57073) | `explorer.inkonchain.com` | ✅ | v12.0.4 |
| Soneium (1868) | `soneium.blockscout.com` | ✅ | v12.0.4 |
| Base (8453) | `base` | ❌ 403 Cloudflare challenge (also with browser UA) | — |
| Arbitrum One (42161) | `arbitrum` | ❌ 403 Cloudflare challenge | — |
| Polygon PoS (137) | `polygon` | ❌ 403 Cloudflare challenge | — |
| Gnosis (100) | `gnosis` | ❌ 301 → gnosisscan.io → 403 Cloudflare; api.sh refuses with exit 3 | — |
| Linea (59144) | `explorer.linea.build` | ❌ 302 → lineascan.build (not Blockscout) | — |
| BNB Smart Chain (56) | — | ❌ no instance: `bsc.blockscout.com` → 404; Chainscout registry (645 entries) has no chain 56; Blockscout API chain table marks BSC ❌ | — |

So keyless Blockscout today covers **Ethereum, OP, Scroll, zkSync, Celo, Unichain, Ink, Soneium**. Base/Arbitrum/Polygon/Gnosis need a free Blockscout API key (api.blockscout.com) — not wired in api.sh. BSC: public RPC only (`api.sh rpc bsc …`).

## Where labels and risk live

| Field | Endpoint | Live behaviour |
|---|---|---|
| `name` | `/addresses/{h}` | contract name for verified contracts (`"WETH9"`, `"USDC"`); `null` for EOAs |
| `ens_domain_name` | `/addresses/{h}`, all address objects | `"vitalik.eth"` |
| `is_contract`, `is_verified` | address objects | booleans |
| `proxy_type`, `implementations[]{address_hash,name}` | address objects, `/smart-contracts/{h}` | USDC: `eip1967_oz` → `FiatTokenV2_2`; EOAs with EIP-7702 delegation show `proxy_type:"eip7702"` + the delegate (`TokenPocketSimple7702Account`) |
| `is_scam`, `reputation` (`ok`/`scam`) | address objects, token objects | only `false`/`ok` seen on addresses; `/tokens/{h}` shows `reputation:"scam"` for fake USDT 0x810074D7…; `/addresses/{scam}` returned 500 |
| `metadata`, `public_tags` | address objects | **always `null` / `[]`** in every response checked (Binance 14, Ronin exploiter, Binance on OP) |
| `metadata.name`, `metadata.tagType`, `metadata.slug` | `/search?q=<label text>` items with `type:"metadata_tag"` | ✅ `"Binance 14"`, `"Ronin Bridge Exploiter"` — search by name works, search by address returns no tag |
| Metadata service tags | `api.sh bsmeta <chainId> '<a,b>'` (= metadata.services.blockscout.com/api/v1/metadata) | ✅ keyless: Ronin exploiter → `Ronin Bridge Exploiter`, `SANCTIONED` (`OFAC Sanctioned`), `BLOCKED` (`Blocked By USDC/USDT`), `Exploit`; 0x28C6… → `Binance: Hot Wallet`, `Exchange`. Works for chainId 8453/10 too. **Not reachable through api.sh** (it forces `/api/v2`). |

Reading an address's labels by address therefore needs the metadata service; through api.sh you can only (a) search by a label name and (b) read contract `name`/ENS.

## Endpoint catalogue (paths after `/api/v2`)

Paging: keyset. Response has `next_page_params` (object or `null`); append each key=value to the same query for the next page. Default page = 50.
- v11 hosts (eth, explorer.optimism.io): `items_count` is a cursor echoed in `next_page_params`; `items_count>50` → 422 "larger than inclusive maximum 50".
- v12 hosts (zksync, scrollscan, celo, …): `items_count` = page size 1–100 (live: 100 works); it is **not** echoed, so add it to every page. `limit` → 422 "Unexpected field". Sorted lists must re-send `sort`/`order` on every page.

### Addresses
| Path | Params | Returns |
|---|---|---|
| `/addresses/{h}` | — | `hash,name,is_contract,is_verified,is_scam,reputation,ens_domain_name,coin_balance(wei),exchange_rate,has_token_transfers,has_tokens,has_logs,proxy_type,implementations,token{…} (if token contract),creator_address_hash,creation_transaction_hash,block_number_balance_updated_at` |
| `/addresses/{h}/transactions` | `filter=to|from` | `items[]{hash,timestamp,status,result,method,value,fee.value,from,to,transaction_types,decoded_input,token_transfers}` |
| `/addresses/{h}/token-transfers` | `type=ERC-20|ERC-721|ERC-1155`, `filter=to|from`, `token=<contract>` | `items[]{transaction_hash,log_index,timestamp,from,to,token{address_hash,symbol,decimals,exchange_rate,reputation},total{value,decimals},method}` |
| `/addresses/{h}/internal-transactions` | `filter=to|from` | `items[]{type,call_type,from,to,value,success,error,transaction_hash,index,timestamp,block_number}` |
| `/addresses/{h}/logs` | — | event logs emitted by the address |
| `/addresses/{h}/tokens` | `type=ERC-20…` | `items[]{token{symbol,decimals,exchange_rate,reputation},value}` (paged) |
| `/addresses/{h}/token-balances` | — | flat array `[{token,value}]`, all tokens (30 for the Ronin exploiter) |
| `/addresses/{h}/coin-balance-history` | — | `items[]{block_number,block_timestamp,delta,value,transaction_hash}` |
| `/addresses/{h}/coin-balance-history-by-day` | — | last 10 days only (empty for idle addresses) |
| `/addresses/{h}/counters` | — | `{transactions_count,token_transfers_count,gas_usage_count,validations_count}` strings — **stale/zero for some addresses** (a test EOA → all 0 despite 19 txs) |
| `/addresses/{h}/tabs-counters` | — | ints capped at 51 (= "50+"): `transactions_count,token_transfers_count,internal_transactions_count,logs_count,token_balances_count`; 500 for some addresses |
| `/addresses/{h}/nft`, `/nft/collections`, `/withdrawals`, `/blocks-validated` | — | doc only |

### Transactions
| Path | Returns |
|---|---|
| `/transactions/{hash}` | `status`, `result`, `method`, `value`, `fee{type,value}`, `gas_used`, `from`, `to{hash,name,is_verified}`, `decoded_input{method_call,method_id,parameters[]{name,type,value}}`, `raw_input`, `token_transfers[]` (+ `token_transfers_overflow`), `transaction_types[]`, `confirmations`, `historic_exchange_rate` |
| `/transactions/{hash}/token-transfers` | paged transfers inside the tx (use when `token_transfers_overflow:true`) |
| `/transactions/{hash}/internal-transactions` | paged internal calls |
| `/transactions/{hash}/logs` | `items[]{address.hash,index,topics[],data,decoded{method_call,parameters[]{name,type,value,indexed}}}` |
| `/transactions/{hash}/summary` | human summary — 500 or >30 s timeout in all 3 tries; v12 may answer 503 under load. Don't rely on it. |
| `/transactions/{hash}/state-changes`, `/raw-trace` | doc only |

### Tokens, contracts, search, stats
| Path | Params | Returns |
|---|---|---|
| `/tokens/{h}` | — | `name,symbol,decimals,type,holders_count,total_supply,exchange_rate,circulating_market_cap,volume_24h,reputation` |
| `/tokens/{h}/holders` | — | `items[]{address{hash,name},value}`, sorted by balance |
| `/tokens/{h}/counters` | — | `{transfers_count,token_holders_count}` |
| `/tokens/{h}/transfers` | — | all transfers of the token |
| `/tokens` | `q=<name>`, `type=ERC-20` | token list by name; **scam tokens hidden** unless request header `show-scam-tokens: true` (api.sh cannot send it; with it 11/50 "tether" results were `reputation:"scam"`) |
| `/smart-contracts/{h}` | — | `name,is_verified,is_fully_verified,is_verified_via_sourcify,compiler_version,language,license_type,optimization_enabled,verified_at,source_code,additional_sources,abi,constructor_args,decoded_constructor_args,proxy_type,implementations,creation_bytecode,deployed_bytecode`; EOA/unverified → `404 {"message":"Not found"}` |
| `/search` | `q` | `items[]{type: token|address|contract|metadata_tag|ens_domain|transaction|block, name, address_hash, symbol, metadata{name,tagType,slug}}`, paged |
| `/search/quick` | `q` | flat array, first matches; ENS: `type:"ens_domain"`, `ens_info.name` |
| `/stats` | — | `total_blocks,total_addresses,coin_price,network_utilization_percentage` (host health check) |
| `/config/backend-version` | — | `{"backend_version":"v12.0.4"}` |

## Recipes

Address profile (label/contract/scam):
```
api.sh blockscout eth '/addresses/0x…'        # name, ens_domain_name, is_contract, is_verified, is_scam, reputation, proxy_type, implementations[].name, coin_balance
api.sh blockscout eth '/addresses/0x…/tabs-counters'
```
Then labels: search the suspected entity name — `api.sh blockscout eth '/search?q=Binance%2014'` → items with `type=="metadata_tag"` and `address_hash==<addr>` give `metadata.name`. For a direct by-address label lookup the metadata service is needed (outside api.sh, see table above).

ERC-20 transfers, all pages:
```
api.sh blockscout eth '/addresses/0x…/token-transfers?type=ERC-20&filter=from'
api.sh blockscout eth '/addresses/0x…/token-transfers?type=ERC-20&filter=from&index=249&block_number=14498427'   # keys from next_page_params
```
Read `items[].{transaction_hash,timestamp,from.hash,to.hash,to.name,to.is_contract,token.symbol,token.address_hash,total.value,total.decimals}`; amount = value/10^decimals. One token only: `&token=0xdAC17F958D2ee523a2206206994597C13D831ec7`. Stop when `next_page_params` is `null`. <!-- gitleaks:allow (public USDT contract address) -->

Internal transfers (ETH moved by contracts): `api.sh blockscout eth '/addresses/0x…/internal-transactions'` → `items[].{from.hash,to.hash,value,type,success,transaction_hash}`.

Decode a tx: `api.sh blockscout eth '/transactions/0x…'` → `decoded_input.method_call` + `parameters`, `token_transfers[].{from.hash,to.hash,token.symbol,total}`, `status`; logs: `/transactions/0x…/logs` → `decoded.method_call` (`Transfer(address indexed from, …)`).

Token info + holders: `/tokens/0x…` (`holders_count`, `reputation`, `exchange_rate`) and `/tokens/0x…/holders` (`items[].{address.hash,address.name,value}`).

Contract source/name: `/smart-contracts/0x…` → `name`, `is_verified`, `compiler_version`, `source_code`, `implementations[]` (follow the implementation for proxies).

Find by name: `/search?q=uniswap` (tokens, contracts, labelled addresses), `/search/quick?q=vitalik.eth` (ENS), `/tokens?q=tether&type=ERC-20`.

Second source for Ethereum: compare `/addresses/{h}/token-transfers` with Etherscan `tokentx`; Blockscout adds ENS, proxy, 7702 delegate and decoded calls in the same row.

## Ready jq one-liners

```
# One-line address verdict
api.sh blockscout eth '/addresses/0x…' | jq -c '{name, ens:.ens_domain_name, contract:.is_contract, verified:.is_verified,
  scam:.is_scam, rep:.reputation, proxy:.proxy_type, impl:[.implementations[]?.name], eth:((.coin_balance|tonumber)/1e18),
  token:(.token|if .==null then null else "\(.symbol) \(.type)" end), creator:.creator_address_hash}'

# ERC-20 flow table of one page
api.sh blockscout eth '/addresses/0x…/token-transfers?type=ERC-20' | jq -r --arg A 0x… '.items[]
  | [.timestamp, (if (.from.hash|ascii_downcase)==($A|ascii_downcase) then "OUT" else "IN" end),
     ((.total.value|tonumber)/pow(10;(.total.decimals|tonumber))), .token.symbol,
     (if (.from.hash|ascii_downcase)==($A|ascii_downcase) then .to.hash else .from.hash end),
     (if (.from.hash|ascii_downcase)==($A|ascii_downcase) then (.to.name // .to.ens_domain_name // "") else (.from.name // .from.ens_domain_name // "") end),
     .token.reputation, .transaction_hash] | @tsv'

# next_page_params → query string
… | jq -r '.next_page_params // empty | to_entries | map("\(.key)=\(.value|tostring|@uri)") | join("&")'
```

Paging loop (stops on `next_page_params == null`, refuses HTML, retries a 5xx once):
```
q='type=ERC-20'; while :; do
  out=$(api.sh blockscout eth "/addresses/$A/token-transfers?$q") || { sleep 2; out=$(api.sh blockscout eth "/addresses/$A/token-transfers?$q") || break; }
  case "$out" in \{*) ;; *) echo "non-JSON at $q" >&2; break;; esac
  printf '%s\n' "$out" >> page.jsonl
  np=$(printf '%s' "$out" | jq -r '.next_page_params // empty | to_entries | map("\(.key)=\(.value|tostring|@uri)") | join("&")')
  [ -z "$np" ] && break; q="type=ERC-20&$np"; sleep 0.3
done
```
On v12 hosts add `&items_count=100` to every request to halve the calls.

## Response skeletons (trimmed, live)

Address object (embedded as `from`/`to` in every list):
```
{"hash":"0x1234…abcd","name":null,"ens_domain_name":null,"is_contract":true,"is_verified":true,"is_scam":false,
 "reputation":"ok","proxy_type":"eip7702","implementations":[{"address_hash":"0xcc0c…f17b","name":"TokenPocketSimple7702Account"}],
 "metadata":null,"public_tags":[],"private_tags":[],"watchlist_names":[]}
```
Token transfer item:
```
{"transaction_hash":"0xe1a7…fecdf","log_index":494,"timestamp":"2026-07-02T16:34:11.000000Z","method":"0xa9059cbb",
 "from":{…},"to":{…},"token":{"address_hash":"0xA0b8…eB48","symbol":"USDC","decimals":"6","exchange_rate":"0.999411","reputation":"ok","type":"ERC-20"},
 "total":{"decimals":"6","value":"808993900"},"token_type":"ERC-20","type":"token_transfer"}
```
Search label hit:
```
{"type":"metadata_tag","address_hash":"0x28C6…1d60","reputation":"ok",
 "metadata":{"name":"Binance 14","slug":"binance-14","tagType":"name","meta":{"tooltipDescription":"Provided by OLI",…}}}
```

## Gotchas seen live

- **Intermittent 500 / timeouts on eth.blockscout.com.** `/transactions/{h}`, `/search`, `/addresses/{h}` each returned `HTTP 500 "Internal server error"` once and worked on retry 2–3 s later; `/transactions/{h}/internal-transactions` and `/summary` timed out (curl 000 after 30 s) on an old tx. api.sh retries only on 429 — retry 5xx yourself once after `sleep 2`.
- **Redirects.** Since 2026-11-09 api.sh never follows redirects and exits 3 with `HTTP 30x redirect to: <url>` — call the printed host/path directly. Aliases `optimism`/`scroll` already point at the right hosts; `base|arbitrum|polygon|gnosis|bsc` exit 3 with a reason (403 / no instance).
- Cloudflare `403` (Base/Arbitrum/Polygon/Gnosis) is not a rate limit; waiting does not help.
- `metadata`/`public_tags` on address objects are empty even for famous labelled addresses — absence of a tag there means nothing.
- `/addresses/{h}/counters` can be all zero for an active address; use `tabs-counters` (capped at 51) or count pages.
- `/tokens` and v12 `tabs-counters` hide scam tokens by default; a scam token address may return 500 on `/addresses/{h}` — query `/tokens/{h}` for `reputation`.
- EIP-7702-delegated EOAs show `proxy_type:"eip7702"` with the delegate in `implementations` (seen on a wallet-app account).
- v11 vs v12 paging differs (see catalogue). v12 also prefixes `constructor_args` with `0x` and may return `ens_domain` items for bare names in search.

## Sources

- https://docs.blockscout.com/llms.txt · https://docs.blockscout.com/_llms/blockscout-api.txt
- https://docs.blockscout.com/rate-limits.md
- https://docs.blockscout.com/devs/blockscout-api-responses-and-routes.md (auth, headers, pagination, credits)
- https://docs.blockscout.com/blockscout-v12-0-0-api-updates-and-breaking-changes.md
- https://docs.blockscout.com/endpoint-overview.md (REST route list)
- https://docs.blockscout.com/devs/metadata-service.md
- https://docs.blockscout.com/devs/chainscout-chains-list.md · https://raw.githubusercontent.com/blockscout/chainscout/main/data/chains.json
- https://docs.blockscout.com/devs/migrate-from-etherscan.md (supported-chain table: BSC ❌)
