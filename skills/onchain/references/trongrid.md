# TronGrid API reference (TRON mainnet, read-only)

Live-verified 2026-11-09 through `api.sh` with the free key, unless a line says otherwise.
Covers the TronGrid **v1 indexed API** (history, TRC-20 transfers, events, holders) and the **FullNode / Solidity HTTP API** (`/wallet/*`, `/walletsolidity/*`: current state, tx receipts, contract reads, resources).

## 1. Header

| Item | Value |
|---|---|
| Base URL | `https://api.trongrid.io` (mainnet). Testnets `api.shasta.trongrid.io`, `nile.trongrid.io` are not wired into api.sh. |
| GET | `api.sh trongrid '<path?query>'` — v1 endpoints, and GET forms of `/wallet/*` (e.g. `/wallet/getchainparameters`, `/wallet/getaccount?address=T…&visible=true`) |
| POST | `api.sh trongrid-post '<path>' '<json>'` — only `/wallet/*`, `/walletsolidity/*`; build/sign/broadcast paths exit 4 |
| Key | header `TRON-PRO-API-KEY` added by api.sh from Keychain; never print it |
| api.sh exit codes | 0 ok · 3 HTTP ≥ 400 (body still printed) · 4 blocked write path · 1 usage. One automatic retry on 429 after 1.2 s |
| **Errors with HTTP 200** | FullNode errors come back HTTP 200: `{"Error":"…"}` or `{"result":{"code":"…","message":"<hex>"}}` — api.sh (since 2026-11-09) detects both, decodes the hex message to stderr and exits 3. `{}` (not found) still exits 0 — check for an empty object yourself. |

### Rate limits
| Who | Limit | Source |
|---|---|---|
| No key | **3 QPS** (cut from 10 on 2025-12-23) | trongrid.io/changeLog/v1-10-0 (official) |
| Free "Basic" plan | **100,000 requests/day**, 3 API keys | trongrid.io/price (official, read 2026-11-09) |
| "Trial" plan | 500,000 requests/day, 3 keys | trongrid.io/price |
| Per key QPS | **15 QPS per key**; daily quota shared by all keys of the account | third-party only (boltrpc.io, quoting TronGrid's plan config, 2026-10-24) — not in official docs |
| Over limit | HTTP 429, body `{"success":false,"error":"The key exceeds the frequency limit","statusCode":429}` (v1) or `{"Error":"…"}` (node). Abuse → 403 / temporary block. | developers.tron.network/reference/rate-limits |
| Headers | No `X-RateLimit-*`, no `Retry-After` (checked live) | live |
Official docs say: "Do not hard-code fixed limits". Practical rule: ≤ 5 req/s, `sleep 0.3` between paged calls.

### Units and formats
- **TRX amounts are in sun**: 1 TRX = 1,000,000 sun (`balance`, `amount`, `fee`, `call_value`, `frozen_balance_for_energy`).
- **TRC-20 `value` is a raw integer string**; divide by `10^decimals`. USDT (`TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t`) = 6 decimals.
- **Timestamps are Unix ms** (`block_timestamp`, `create_time`, `min_timestamp`). Block every 3 s.
- Solidified (final) head lags the latest head by ~19 blocks (~1 min; observed live).
- Proto3 omission: in `/wallet/*` JSON a field with a default value (0, false, "", empty list, first enum) is **omitted**. `frozenV2:[{}]` means `{type:BANDWIDTH, amount:0}`; no `type` on `getaccount` means a normal account; missing `balance` means 0.

### Address formats
| Form | Example | Where it appears |
|---|---|---|
| Base58Check | `TMuA6YqfCeX8EhbfYEg5y7S4DqzSJireY9` | v1 TRC-20 `from/to`, `token_info.address`; `/wallet/*` with `visible:true` |
| Hex with `41` prefix (21 bytes) | `4182dd6b9966724ae2fdc79b416c7588da67ff1b35` | v1 `/transactions` `raw_data`, internal txs, v1 account `address`; `/wallet/*` default |
| 0x + 20 bytes (no 41) | `0x82dd6b9966724ae2fdc79b416c7588da67ff1b35` | v1 events `result` fields |
| 20 bytes, no prefix | `a614f803…` | `gettransactioninfobyid` `log[].address`, `topics` |
- `visible:true` (POST body) makes `/wallet/*` take and return Base58. Exception: **`getnowblock` reads `visible` only as a query param** — `'/wallet/getnowblock?visible=true'`.
- v1 endpoints accept Base58 or hex `41…` in the path (verified both).
- **ABI address argument** for `triggerconstantcontract.parameter`: hex without `41`, left-padded with zeros to 64 chars: `printf '%064s' 82dd6b9966724ae2fdc79b416c7588da67ff1b35 | tr ' ' 0`. A uint256 argument is the hex value, left-padded to 64.
- Validate: `trongrid-post /wallet/validateaddress '{"address":"T…"}'` → `{"result":true,"message":"Base58check format"}` / `{"result":false,"message":"Invalid address"}`.
- Converter (Base58 ↔ hex 41), verified on TMuA6Y… ↔ 4182dd…:
```python
import sys,hashlib
B='123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
def to_b58(h):  # '41…' or 0x/20-byte hex
    h=h[-40:]; b=bytes.fromhex('41'+h); b+=hashlib.sha256(hashlib.sha256(b).digest()).digest()[:4]
    n=int.from_bytes(b,'big'); s=''
    while n: n,r=divmod(n,58); s=B[r]+s
    return s
def to_hex(a):
    n=0
    for c in a: n=n*58+B.index(c)
    return n.to_bytes(25,'big')[:21].hex()
for a in sys.argv[1:]: print(a,'->',to_hex(a) if a.startswith('T') else to_b58(a))
```
Run as `python3.13 -I conv.py <addr…>`.

## 2. v1 indexed API (GET, `api.sh trongrid`)

Common to every list endpoint (verified on accounts/trc20, accounts/transactions, contract events, holders):
- `limit` default 20, **max 200**; `limit=201` → HTTP 400 `{"success":false,"error":"A valid limit by parameter is required."}` (api.sh exit 3).
- Paging: response `meta.fingerprint` + `meta.links.next` (full URL incl. host). Strip `https://api.trongrid.io` and call again. Keep every other param unchanged. **Last page has no `fingerprint`/`links`.** `meta.page_size` = rows in this page. Fingerprints are opaque (the contract-events one was just `7`) — never build them.
- `order_by=block_timestamp,asc|desc` (default desc). `min_timestamp` / `max_timestamp` in ms, **both inclusive** (synonyms `min_block_timestamp`, `max_block_timestamp`).
- `only_confirmed=true` | `only_unconfirmed=true` — both together → HTTP 400 `Conflicting parameters passed.`
- Bad address → HTTP 400 `{"success":false,"error":"A valid account address is required."}` (rc 3).
- Unconfirmed rows carry `"_unconfirmed": true` (seen on events).

| Endpoint | Key params | Returns | Notes |
|---|---|---|---|
| `/v1/accounts/{addr}` | only_confirmed / only_unconfirmed | `data[0]`: `address`(hex), `balance`(sun), `create_time`, `latest_opration_time` (sic), `trc20:[{contract: rawBalance}]`, `assetV2:[{key: TRC10 id, value}]`, `frozenV2`, `account_resource`, `owner_permission`/`active_permission` (Base58 inside) | **Not activated → `data: []`**. Spam TRC-10 tokens show up in `assetV2`. |
| `/v1/accounts/{addr}/transactions` | only_to, only_from, limit, fingerprint, order_by, min/max_timestamp, only_confirmed | native txs: `txID`, `blockNumber`, `block_timestamp`, `raw_data.contract[0].type` + `.parameter.value` (hex addrs, amounts sun), `ret[0].contractRet`, `ret[0].fee` (total sun), `energy_fee`, `net_fee`, `energy_usage_total`, `net_usage`, `internal_transactions[]` | Only txs where the address is owner or direct recipient. TRC-20 transfers appear only as `TriggerSmartContract` (decode `data`) — use the trc20 endpoint. `search_internal` was **removed** in v1.7.0 (no effect; verified). On a test wallet the total equalled only_to + only_from. |
| `/v1/accounts/{addr}/transactions/trc20` | only_to, only_from, **contract_address**, limit, fingerprint, order_by, min/max_timestamp, only_confirmed | `transaction_id`, `block_timestamp`, `from`, `to` (Base58), `value` (raw string), `type` (`Transfer` / `Approval`), `token_info{symbol,address,decimals(number),name}` | Also TRC-721. For `Approval`: `from` = owner, `to` = spender. Includes `transferFrom` legs made by routers. |
| `/v1/accounts/{addr}/internal-transactions` | only_to / only_from (not together), limit, fingerprint, order_by, min/max_timestamp | `internal_tx_id`, `tx_id` (parent), `from_address`, `to_address` (hex), `data.call_value._` (sun), `data.note`, `data.rejected` | The only way to see TRX that arrived via a contract (DEX swap payouts, contract withdrawals). |
| `/v1/accounts/{addr}/trc20/balance` | contract_address (Base58), limit, fingerprint | `data:[{contract: rawBalance}]` | No decimals/symbol; zero balances omitted. Indexed — confirm with `balanceOf` for evidence. |
| `/v1/transactions/{txid}/events` | only_confirmed | decoded logs: `event_name`, `event` (signature), `contract_address`, `caller_contract_address`, `event_index`, `block_number`, `result{name: value}`, `result_type` | `result` addresses are `0x`+20 bytes. Arrays are `\n`-joined strings. |
| `/v1/transactions/{txid}/internal-transactions` | only_confirmed | same shape as account internal txs | |
| `/v1/contracts/{addr}/events` | **event_name**, block_number (or `latest`), min/max_timestamp, order_by, limit, fingerprint, only_confirmed | events as above | USDT freeze history: `event_name=AddedBlackList`, `RemovedBlackList`, `DestroyedBlackFunds`. |
| `/v1/contracts/{addr}/transactions` | min/max_timestamp, order_by, limit, fingerprint, only_confirmed | txs calling the contract (`txID`, `raw_data`, `ret`), **no fee fields** | `search_internal` removed (v1.8.1). |
| `/v1/contracts/{addr}/internal-transactions` | min/max_timestamp, order_by, limit, fingerprint, only_confirmed | internal txs of the contract | |
| `/v1/contracts/{addr}/tokens` | order_by=`balance,desc`(default)/`asc`, limit, fingerprint | holders `data:[{holderBase58: rawBalance}]` | Top USDT holders in 1 call. |
| `/v1/trc20/info?contract_list=A,B` | up to 20 contracts | `symbol`, `name`, **`decimals` (string!)**, `type` (trc20/trc721/trc1155), `total_supply` (raw string) | Fastest token identification. |
| `/v1/blocks/{n}/events` · `/v1/blocks/latest/events` | limit, fingerprint, only_confirmed | events of one block | |
| `/v1/blocks/{n}/stats` | `get_tx_detail=true` adds `txStat` | `feeStat{energyUsage, netUsage, energyBurnFeeSunAmt, bandwidthBurnFeeSunAmt, accountActivationFee, …}`; `txStat{transferCount, trc20And721TransferCount, failTxCount, internalTxCount, contractTypeDistribute}` | **`…FeeSunAmt` values are in TRX despite the name** (20061 bytes burned → 20.061). |
| `/v1/assets/{id or issuer}` | — | TRC-10 metadata: `id`, `name`, `abbr`, `precision`, `owner_address`(hex), `total_supply`, `url`, `description` | Integers 1000001–2000000 = asset id, else issuer address. |
| `/v1/assets/{name}/list` · `/v1/assets` | limit, fingerprint, order_by (`id`, `total_supply`, `start_time`, `end_time`) | TRC-10 lists | Many assets share a name (`btt` → 2). |

## 3. FullNode / Solidity HTTP API (`api.sh trongrid-post`)

`/wallet/X` = latest head (may still change). `/walletsolidity/X` = solidified state, same shapes; use it for evidence and balances. Add `"visible":true` for Base58.

| Endpoint | Body | Returns (key fields) | Notes |
|---|---|---|---|
| `/wallet/getaccount` (+solidity) | `{"address":A,"visible":true}` | `balance` (sun), `create_time`, `latest_opration_time`, `type:"Contract"` (absent = normal), `account_name` (readable only with visible), `is_witness`, `frozenV2`, `unfrozenV2`, `account_resource{delegated_frozenV2_balance_for_energy, acquired_delegated_frozenV2_balance_for_energy, energy_usage}`, `acquired_delegated_frozenV2_balance_for_bandwidth`, `assetV2`, permissions | **Not activated → `{}`**. Contract accounts: `account_name` = contract name, no `create_time`. |
| `/wallet/getaccountresource` | same | `freeNetLimit` (600/day), `NetUsed`, `NetLimit`, `EnergyUsed`, `EnergyLimit`, `tronPowerUsed/Limit`, `TotalEnergyLimit`, `TotalEnergyWeight` | `EnergyLimit` > 0 with no own stake → energy delegated in. |
| `/wallet/getaccountnet` | same | bandwidth only (`freeNetUsed`, `NetLimit`…) | Subset of getaccountresource. |
| `/wallet/gettransactionbyid` (+solidity) | `{"value":txid,"visible":true}` | `raw_data.contract[0]{type, parameter.value}`, `ret[0].contractRet`, `raw_data.fee_limit`, `raw_data.data` (memo, hex) | Unknown txid → `{}`. Solidity variant returns `{}` until final. |
| `/wallet/gettransactioninfobyid` (+solidity) | `{"value":txid}` | `fee` (total sun), `blockNumber`, `blockTimeStamp`, `contract_address`, `receipt{energy_usage, energy_fee, origin_energy_usage, energy_usage_total, energy_penalty_total, net_usage, net_fee, result}`, `log[]{address, topics, data}`, `internal_transactions[]{hash, caller_address, transferTo_address, callValueInfo[].callValue, note(hex)}`, `contractResult` | `energy_usage` = energy from own/delegated stake; `energy_fee` = TRX burned for energy; `energy_penalty_total` = dynamic-energy surcharge. Unknown txid → `{}`. |
| `/wallet/gettransactionreceiptbyid` | `{"value":txid}` | `{"Receipt":{…}}` | Receipt only. |
| `/wallet/gettransactioninfobyblocknum` | `{"num":n}` | array of tx infos of the block | ~300 rows per block; heavy. |
| `/wallet/triggerconstantcontract` (+solidity) | `{"owner_address":A,"contract_address":C,"function_selector":"balanceOf(address)","parameter":P,"visible":true}` | `constant_result[0]` (hex), `result.result`, `energy_used`, `energy_penalty` | **`owner_address` is required** (missing → `OTHER_ERROR … owner_address isn't set`); any valid address works, e.g. `T9yD14Nj9j7xAB4dbGeiX9h8unkKHxuWwb` (zero address). Missing function → `result:{result:true, message:"REVERT opcode executed"}`, `constant_result:[""]`. Non-contract → `CONTRACT_VALIDATE_ERROR: Smart contract is not exist.` |
| `/wallet/estimateenergy` | same as above, for a write call | `energy_required` | Doc only, not tested. |
| `/wallet/getcontract` | `{"value":C,"visible":true}` | `name`, `origin_address` (**deployer**), `abi.entrys[]`, `bytecode`, `code_hash`, `consume_user_resource_percent`, `origin_energy_limit` | EOA → `{}` (= not a contract). |
| `/wallet/getcontractinfo` | same | `smart_contract{…}`, `runtimecode`, `contract_state{energy_usage, energy_factor, update_cycle}` | `energy_factor` > 0 = dynamic-energy penalty (popular contract). |
| `/wallet/getdelegatedresourceaccountindexv2` (+solidity) | `{"value":A,"visible":true}` | `fromAccounts[]` (who delegates TO A), `toAccounts[]` (whom A delegates to) | Stake 2.0, current state only. Empty → only `{"account":A}`. |
| `/wallet/getdelegatedresourcev2` (+solidity) | `{"fromAddress":F,"toAddress":T,"visible":true}` | `delegatedResource[]{from,to,frozen_balance_for_energy, frozen_balance_for_bandwidth, expire_time_for_energy/_bandwidth}` | Amounts = staked TRX in sun. No current delegation → `{}`. |
| `/wallet/getdelegatedresourceaccountindex` · `getdelegatedresource` | Stake 1.0 versions | legacy | Mostly empty now. |
| `/wallet/getcandelegatedmaxsize` | `{"owner_address":A,"type":1,"visible":true}` (0 bandwidth, 1 energy) | `max_size` (sun) | Capacity of a delegator. |
| `/wallet/getavailableunfreezecount` · `getcanwithdrawunfreezeamount` | `{"owner_address":A,"visible":true}` | `count` · `amount` (or `{}`) | Stake 2.0 unstaking state. |
| `/wallet/getReward` | `{"address":A,"visible":true}` | `reward` (sun) | Unclaimed voting reward. |
| `/wallet/getnowblock` (+solidity) | `{}`; path `?visible=true` | `blockID`, `block_header.raw_data{number,timestamp,witness_address}`, `transactions[]` | |
| `/wallet/getblockbynum` (+solidity) | `{"num":n,"visible":true}` | full block | |
| `/wallet/getblock` | `{"id_or_num":"n","detail":false}` | header (`blockID` = hash) | `detail:true` → full block. |
| `/wallet/getblockbylatestnum` · `getblockbylimitnext` | `{"num":k}` · `{"startNum":a,"endNum":b}` (end exclusive) | `{"block":[…]}` | |
| `/wallet/getchainparameters` (GET) | — | `chainParameter[]{key,value}` | Now: `getEnergyFee` 100 sun/energy, `getTransactionFee` 1000 sun/byte, `getCreateNewAccountFeeInSystemContract` 1 TRX, `getCreateAccountFee` 0.1 TRX, `getFreeNetLimit` 600, `getMemoFee` 1 TRX, `getUnfreezeDelayDays` 14, `getMaxFeeLimit` 15,000 TRX. |
| `/wallet/getenergyprices` · `getbandwidthprices` (GET) | — | `prices`: `"ts:price,ts:price"` (sun) | Price history; last entry is current. |
| `/wallet/getburntrx` (GET) | — | `burnTrxAmount` (sun) | Chain-wide stat. |
| `/wallet/getassetissuebyid` · `getassetissuebyaccount` | `{"value":id}` · `{"address":A}` | TRC-10 metadata | Doc only; v1 `/v1/assets/{id}` verified instead. |
| `/wallet/listwitnesses` (GET, `?visible=true`) | — | SR list | Doc only. |
| `/wallet/getaccountbalance` · `getblockbalance` | historical balance | **does not work on TronGrid**: returns `balance: 0` for a funded account / `This block does not exist` | Needs a node with `storage.balance.history.lookup`. Rebuild history from v1 txs instead. |

## 4. Recipes

`A=~/.claude/skills/onchain/scripts/api.sh`, `X=<address>`, `USDT=TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t`.

**Pager** (follows `links.next`, prints one JSON row per line):
```bash
page() { local p="$1" r; while [ -n "$p" ]; do r=$($A trongrid "$p") || return 3
  printf '%s' "$r" | jq -c '.data[]'; p=$(printf '%s' "$r" | jq -r '.meta.links.next // empty'); p=${p#https://api.trongrid.io}; sleep 0.3; done; }
```

1. **Full USDT history**: `page "/v1/accounts/$X/transactions/trc20?limit=200&contract_address=$USDT&only_confirmed=true" > usdt.jsonl`. Keep `type=="Transfer"`; amount = `(.value|tonumber)/1e6`.
2. **Incoming only / outgoing only**: add `&only_to=true` or `&only_from=true`. The same flags work on `/transactions` (TRX) and `/internal-transactions`.
3. **Time window**: `&min_timestamp=1767225600000&max_timestamp=1769278584000` (ms, inclusive). Add `&order_by=block_timestamp,asc` for chronological order.
4. **Counterparties** (from usdt.jsonl):
   `jq -s --arg me $X '[.[]|select(.type=="Transfer")|{cp:(if .from==$me then .to else .from end),dir:(if .from==$me then "out" else "in" end),usdt:((.value|tonumber)/1e6)}]|group_by(.cp+.dir)|map({cp:.[0].cp,dir:.[0].dir,n:length,usdt:(map(.usdt)|add)})|sort_by(-.usdt)'`
5. **Who activated / funded the address first**:
   - `$A trongrid-post /wallet/getaccount '{"address":"'$X'","visible":true}' | jq '{create_time,balance,type}'` (`{}` = never activated).
   - `$A trongrid "/v1/accounts/$X/transactions?limit=5&order_by=block_timestamp,asc&only_to=true"` → first `TransferContract`: `raw_data.contract[0].parameter.value.owner_address` (hex → convert) = activator; `amount` in sun. `ret[0].fee` = 1,100,000 (1.1 TRX) means this tx created the account. Its `block_timestamp` is a few seconds after `create_time`.
   - Also check the first USDT in: recipe 1 with `order_by=block_timestamp,asc&only_to=true&limit=1`.
6. **Current USDT balance (on-chain evidence)**:
   `P=$(printf '%064s' <hex-without-41> | tr ' ' 0); $A trongrid-post /walletsolidity/triggerconstantcontract '{"owner_address":"T9yD14Nj9j7xAB4dbGeiX9h8unkKHxuWwb","contract_address":"'$USDT'","function_selector":"balanceOf(address)","parameter":"'$P'","visible":true}' | jq -r '.constant_result[0]'` → hex raw; `python3 -c "print(int('<hex>',16)/1e6)"`. Quick indexed value: `/v1/accounts/$X/trc20/balance?contract_address=$USDT`.
7. **Blacklisted (frozen) by Tether?** Both `isBlackListed(address)` and `getBlackListStatus(address)` exist on USDT-TRC20 and agree (verified: a listed address → `…0001`, clean → `…0000`). Same call as recipe 6. History of the freeze: `$A trongrid "/v1/contracts/$USDT/events?event_name=AddedBlackList&only_confirmed=true&limit=200"` and filter `.result._user == "0x<hex-without-41>"`; also `RemovedBlackList`, `DestroyedBlackFunds` (`_blackListedUser`, `_balance`). For a time window add min/max_timestamp — the full AddedBlackList list is long.
8. **Tx details incl. fee / energy burned**: `$A trongrid-post /walletsolidity/gettransactioninfobyid '{"value":"<txid>"}'`. Total TRX paid = `fee/1e6`. `receipt.energy_fee` = TRX burned for energy (sun); `receipt.energy_usage` = energy paid by stake (own or delegated); `receipt.net_fee` = burned for bandwidth. A USDT transfer with `energy_fee` 0, `energy_usage` ≈ 130k means rented/delegated energy. Decode the USDT transfer: `log[0].topics[1]` = from, `topics[2]` = to (last 40 hex), `data` = amount. Sender/method: `gettransactionbyid` → `raw_data.contract[0].parameter.value.data` starts `a9059cbb` (`transfer`), `23b872dd` (`transferFrom`), `095ea7b3` (`approve`).
9. **Who delegates energy to the address** (service / exchange sign):
   - Now: `$A trongrid-post /wallet/getdelegatedresourceaccountindexv2 '{"value":"'$X'","visible":true}'` → `fromAccounts`; then `getdelegatedresourcev2 {"fromAddress":F,"toAddress":X}` for amounts.
   - History: `page "/v1/accounts/$X/transactions?limit=200" | jq -c 'select(.raw_data.contract[0].type=="DelegateResourceContract")|.raw_data.contract[0].parameter.value|{owner_address,balance,resource,lock}'`.
   - **Rental pattern** (seen live on a test wallet): `DelegateResource` → USDT transfer 6 s later → `UnDelegateResource` 15 s later, from many different delegators. That is an energy-rental service, not a relation between owners. A delegator with dozens of `toAccounts` and a large `delegated_frozenV2_balance_for_energy` is a rental pool.
10. **Identify an unknown contract**: `getaccount` (`type:"Contract"`, `account_name`) → `getcontract` (`name`, `origin_address` = deployer, ABI event names) → `/v1/trc20/info?contract_list=C` (token? symbol, decimals) → `triggerconstantcontract` `name()`, `symbol()`, `owner()`; decode strings: skip 2×64 hex chars (offset, length), the rest is UTF-8 hex. → `/v1/contracts/C/transactions?limit=20` for activity, `/v1/contracts/C/tokens` for holders. `getcontract` → `{}` = not a contract.
11. **DEX swaps / TRX from contracts**: `page "/v1/accounts/$X/internal-transactions?limit=200&only_to=true"` → `call_value._` sun with parent `tx_id`; decode the parent with `/v1/transactions/<tx_id>/events` (e.g. `SwapExactTokensForTokens`, `Swap`).

## 5. Gotchas observed live

- `/transactions` shows TRC-20 sends only as `TriggerSmartContract`; transfers **to** X made by other people do not appear there at all. Use `/transactions/trc20` for tokens and `/internal-transactions` for TRX from contracts.
- **Fake tokens**: TRC-20 lists include spam tokens (e.g. a symbol that is a URL). Filter by `token_info.address == TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t`, never by symbol "USDT". <!-- gitleaks:allow (public USDT contract address) -->
- **Address poisoning dust**: tiny TRX transfers (1–8 sun) from look-alike addresses arrive right after a new activity; spam TRC-10 assets fill `assetV2`. Do not treat them as counterparties.
- **Unlimited approvals**: `type=="Approval"` with value `115792089237316195423570985008687907853269984665640564039457584007913129639935` (2^256−1). `to` = spender; an unknown spender is a drainer risk.
- v1 account `address` is hex while `owner_permission.keys[].address` is Base58 — mixed formats in one object.
- `/v1/trc20/info` returns `decimals` as a string; `token_info.decimals` is a number.
- `limit` > 200 → HTTP 400 "A valid limit by parameter is required." (re-checked 2026-11-09; an earlier probe saw an empty body).
- FullNode errors return HTTP 200; api.sh now turns `.Error` / `.result.code` into exit 3, but an empty `{}` (unknown tx/contract) still exits 0.
- Historical balance endpoints do not work on TronGrid (return 0 / "block does not exist").
- `visible` in the body is ignored by `getnowblock`; use `?visible=true`.
- Event `result` addresses are `0x`+20 bytes; tx-info `log` addresses/topics have no prefix. Prepend `41` before converting to Base58.
- `/v1/blocks/{n}/stats` `…FeeSunAmt` fields are TRX, not sun.
- `search_internal` is gone from both `/transactions` endpoints (changelog v1.7.0, v1.8.1).
- Activation fee: an account-creating TRX transfer costs the sender 1.1 TRX (`ret[0].fee` 1,100,000; receipt shows only the 0.1 TRX `net_fee`).

## 6. Not verified live
- Per-key 15 QPS and the 401 body `{"Error":"ApiKey not exists"}` (third-party report; the brief says wrong key → 401).
- A possible new 10,000/day Free plan (third-party report of a "v1.12.0" note; absent from the official changelog, which ends at v1.11.0 on 2026-11-09).
- `estimateenergy`, `listwitnesses`, `getassetissueby*` (`/wallet/*`), `expire_time_*` / `lock` fields in `getdelegatedresourcev2` (no locked delegation found).
- Maximum paging depth of v1 lists (largest test was 267 rows, 2 pages).

## Sources (read 2026-11-09)
- https://developers.tron.network/llms.txt, https://developers.tron.network/reference/llms.txt
- TronGrid v1 pages (`.md`): trongrid-v1-api-overview, select-network, rate-limits, get-account-info-by-address, get-transaction-info-by-account-address, get-trc20-transaction-info-by-account-address, get-internal-transactions-by-address, get-internal-transactions-by-transactionid, get-trc20-token-balances-by-address, get-transaction-info-by-contract-address, get-internal-transactions-by-contract-address, get-trc20-token-holder-balances, get-trc-20-token-information, get-events-by-transaction-id, get-events-by-contract-address, get-events-by-block-number, get-events-by-latest-block, get-block-statistics, list-all-assets-trc10-tokens-on-chain, get-asset-by-name, get-asset-by-id-or-issuer — all under https://developers.tron.network/reference/
- FullNode/Solidity pages: full-node-api-overview, solidity-node-http-api-overview, account-getaccount, getaccountresource, getaccountnet, getaccountbalance, getblockbalance, wallet-gettransactionbyid, gettransactioninfobyid, gettransactionreceiptbyid, gettransactioninfobyblocknum, triggerconstantcontract, estimateenergy, wallet-getcontract, getcontractinfo, getdelegatedresourcev2, getdelegatedresourceaccountindexv2-1, getcandelegatedmaxsize, wallet-getchainparameters, getenergyprices, getbandwidthprices, getburntrx, wallet-getnowblock, wallet-getblockbynum, getblock-1, validateaddress (same base URL)
- https://developers.tron.network/docs/trongrid
- https://www.trongrid.io/price · https://www.trongrid.io/changeLog · /changeLog/v1-10-0 · /v1-7-0 · /v1-8-0 · /v1-8-1 · /v1-6-0
- https://trongrid.zendesk.com/hc/en-us/articles/18574394281753 (2023 keyless QPS plan, superseded by v1.10.0)
- https://boltrpc.io/blog/trongrid-rate-limits (third-party: 15 QPS per key, 429 body, 401 body)
