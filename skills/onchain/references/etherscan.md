# Etherscan API V2 — reference for /onchain

Verified live with the free key on 2026-11-09 (≈160 calls). "LIVE" = checked through api.sh that day; everything else is from the official docs (Sources at the end).

## 1. Basics

- **V2 = one key, one host, many chains.** `GET https://api.etherscan.io/v2/api?chainid=<id>&module=<m>&action=<a>&…&apikey=…`. The old per-explorer hosts (bscscan, polygonscan, arbiscan…) and their keys are not used. One `chainid` per request.
- **Call only through the gateway** (injects the key, never prints it):
  ```
  ES=<skill dir>/scripts/api.sh   # SKILL.md gives the path as ${CLAUDE_SKILL_DIR}
  $ES etherscan <chainid> '<query without apikey>'
  ```
  stdout = raw JSON; exit 3 = API/HTTP error (message on stderr); one automatic retry on rate-limit text/429.
- **Envelope (all modules except proxy):** `{"status":"1"|"0","message":"OK"|"NOTOK"|<text>,"result":…}`. `status:"0"` means EITHER an error OR an empty result — read `message` (see Gotchas).
- **Proxy module** answers JSON-RPC: `{"jsonrpc":"2.0","id":…,"result":"0x…"}` or `{"jsonrpc":"2.0","error":{"code":…,"message":…}}` — no `status` field.
- **Units:** native `value`/`balance` = wei (decimal string). Token `value` = raw integer, divide by `10^tokenDecimal`. Account-module `timeStamp` = unix seconds (decimal). Logs/proxy fields = hex (`blockNumber`, `timeStamp`, `logIndex`, `gasPrice`). Gas oracle = Gwei (decimal with fractions). Beacon withdrawal `amount` = Gwei. Addresses come back lowercase; input is case-insensitive.
- **Plan tiers** (docs `rate-limits`): PRO = Standard plan and above; PRO+ = Pro Plus only; Metadata exports = Enterprise only. Source code + ABI endpoints are free on **every** chain, including paid-only chains (LIVE on 56 and 8453).
- Keyless alternative (no PRO tools): Etherscan MCP `https://mcp-keyless.etherscan.io/mcp`; not wired into /onchain.

### Free-tier limits (docs `rate-limits`, `changelog`; LIVE where marked)

| Limit | Value |
|---|---|
| Rate | **3 calls/s** per key (keep `sleep 0.4` between calls) |
| Daily | **100,000 calls/day**, hard block at the cap, no overage (since 2026-11-03). LIVE: `getapilimit` → `creditLimit 100000`, `limitInterval daily`; ≈1 credit per call |
| Records per call | **1,000 max** on free tier since 2026-07-01. LIVE: `offset=2000`/`5000` silently returns 1000 rows |
| Result window | **page × offset ≤ 10,000**. LIVE error: `Result window is too large, PageNo x Offset size must be less than or equal to 10000` |
| PRO endpoints | not available (error text in §4) |
| ENS `forwardresolve` | 1 call/s on free tier |
| PRO endpoints marked "2 calls/s" | throttled at 2/s on every tier |
| Shared "community" pools | Linea 59144/59141 (since 2026-08-04), Arbitrum 42161/421614 (since 2026-11-01), Katana 747474/737373, Celo 42220/11142220: one free pool for ALL free users per chain. Error when empty: `Community Free API limit reached. Resets <UTC time>…` — wait or use Blockscout/RPC |

### Chains (official `GET https://api.etherscan.io/v2/chainlist`, no key needed; 55 chains on 2026-11-09)

Each row has `chainid`, `chainname`, `blockexplorer`, `status` (0 offline / 1 ok / 2 degraded), `comment` = `Free-tier available` | `Paid Plan required`.

| Tier | Mainnets (chainid) | LIVE 2026-11-09 |
|---|---|---|
| **Free** | Ethereum 1 · Polygon 137 · Arbitrum One 42161 · Linea 59144 · Mantle 5000 · Unichain 130 · Sonic 146 · Berachain 80094 · Monad 143 · HyperEVM 999 (free until 2026-11-30, Lite+ from 12-01) · Plasma 9745 · MegaETH 4326 · World 480 · Celo 42220 · Fraxtal 252 · Taiko 167000 · XDC 50 · BitTorrent 199 · Abstract 2741 · Katana 747474 · Sei 1329 · Stable 988 · Memecore 4352 | all OK (`balance`) |
| Free testnets | Sepolia 11155111 · Hoodi 560048 · Amoy 80002 · Arb Sepolia 421614 · Linea Sepolia 59141 · BTT 1029 · Celo Sepolia 11142220 · Fraxtal Hoodi 2523 · Mantle Sepolia 5003 · Memecore 43522 · Taiko Hoodi 167013 · XDC Apothem 51 · World Sepolia 4801 · Sonic 14601 · Unichain Sepolia 1301 · Bepolia 80069 · Monad 10143 · Katana Bokuto 737373 · Sei 1328 · Stable 2201 · Plasma 9746 · MegaETH 6343 | Sepolia OK |
| **Paid only** | BSC 56 (+97) · Base 8453 (+84532) · OP 10 (+11155420) · Avalanche 43114 · Gnosis 100 · Robinhood 4663 · Arc 5042 | `Free API access is not supported for this chain. Please upgrade your api plan for full chain coverage.` (except getsourcecode/getabi) |
| **Gone** | Scroll 534352 (2026-04-16) · zkSync 324 · Blast 81457 & ApeChain 33139 (2026-10-31) · opBNB 204 · Moonbeam 1284/Moonriver 1285 · Swell 1923; Avalanche Fuji 43113 ends 2026-11-15 | `Missing or unsupported chainid parameter (required for v2 api)…` |

For paid/gone chains use `api.sh blockscout <chain>` or `api.sh rpc <chain>`.

## 2. Endpoint catalogue

Params: `*` = required. All need `chainid` (added by api.sh). Pagination params `page`, `offset` (≤1000 free), `sort=asc|desc`, `startblock`/`endblock` (`endblock=latest` OK).

### account

| action | key params | returns | tier | notes |
|---|---|---|---|---|
| `balance` | `address*`, `tag=latest` | wei string | free LIVE | `tag` hex block only within last 128 blocks |
| `balancemulti` | `address*` comma list ≤20, `tag` | `[{account,balance}]` | free LIVE | |
| `balancehistory` | `address*`, `blockno*` | wei at block | PRO 2/s LIVE-denied | |
| `txlist` | `address*`, start/endblock, page, offset, sort | normal txs | free LIVE | fields: `blockNumber timeStamp hash nonce from to value gas gasPrice gasUsed isError txreceipt_status input methodId functionName contractAddress confirmations` |
| `txlist` (advanced filter, beta) | `from`, `to`, `fromto_opr*=and|or`, start/endblock, page, offset, sort | normal txs | free LIVE | `from`/`to` without `fromto_opr` → `Error! Missing fromto_opr (and|or) parameter` |
| `txlistinternal` | `address*`, start/endblock, page, offset, sort | internal (trace) value transfers | free LIVE | fields add `type`(call/create…), `traceId`, `isError`, `errCode` |
| `txlistinternal` | `txhash*` | internal calls inside one tx | free LIVE | |
| `txlistinternal` | `startblock*`, `endblock*` (no address) | internal txs in block range | PRO LIVE-denied | PRO since 2026-07-01 |
| `txlistinternal` (adv. filter) | `from`/`to` + `fromto_opr` | | free (beta) | same pattern as tokentx adv. filter |
| `tokentx` | `address` and/or `contractaddress` (≥1), start/endblock, page, offset, sort | ERC-20 transfers | free LIVE | fields: `blockNumber timeStamp hash from to value contractAddress tokenName tokenSymbol tokenDecimal statusRep functionName methodId …`; **no `logIndex`**; `contractaddress` alone = all transfers of a token |
| `tokentx` (adv. filter, beta) | `from`, `to`, `fromto_opr*`, `contractaddress`, … | ERC-20 transfers between two parties / one direction | free LIVE | best way to get "A→B only" |
| `tokennfttx` / `token1155tx` | as tokentx (+ adv. filter variants) | ERC-721 / ERC-1155 transfers | free LIVE (empty) | |
| `tokenbalance` | `contractaddress*`, `address*`, `tag=latest` | raw token balance string | free LIVE | latest only |
| `tokenbalancehistory` | `contractaddress*`, `address*`, `blockno*` | raw balance at block | PRO 2/s LIVE-denied | |
| `addresstokenbalance` | `address*`, page, offset | all ERC-20 holdings `{TokenAddress,TokenName,TokenSymbol,TokenQuantity,TokenDivisor,TokenPriceUSD}` | PRO 2/s LIVE-denied | free substitute: aggregate `tokentx` + `tokenbalance` |
| `addresstokennftbalance` / `addresstokennftinventory` | `address*` (+`contractaddress*`) | NFT holdings / token IDs | PRO 2/s | |
| `fundedby` | `address*` (EOA only) | `{block,timeStamp,fundingAddress,fundingTxn,value}` | PRO 2/s LIVE-denied | free substitute in §3.4 |
| `getminedblocks` | `address*`, `blocktype=blocks|uncles`, page, offset | `{blockNumber,timeStamp,blockReward}` | free LIVE | |
| `txsBeaconWithdrawal` | `address`, start/endblock, page, offset, sort | `{withdrawalIndex,validatorIndex,address,amount(Gwei),blockNumber,timestamp}` | free LIVE | note capital B in action |
| `getdeposittxs` / `getwithdrawaltxs` | `address*`, page, offset, sort | L1→L2 deposits / L2→L1 withdrawals | free on L2 chainids LIVE (42161) | on chainid 1 → `Error! Missing Or invalid Action name` |
| `txnbridge` | `address`, page, offset | Polygon Plasma deposits | free LIVE (137) | empty = `No record found` |

### contract

| action | key params | returns | tier | notes |
|---|---|---|---|---|
| `getsourcecode` | `address*` | `[{SourceCode,ABI,ContractName,CompilerVersion,CompilerType,OptimizationUsed,Runs,ConstructorArguments,EVMVersion,Library,ContractFileName,LicenseType,Proxy,Implementation,SwarmSource,SimilarMatch}]` | free, all chains LIVE | unverified/EOA → `status 1`, `ABI:"Contract source code not verified"`, `ContractName:""`. `Proxy`: 0 no, 1 proxy, **2 minimal proxy** (since 2026-09); `Implementation` = target. Multi-file sources come as `{{…}}` JSON in `SourceCode` |
| `getabi` | `address*` | ABI JSON string | free LIVE | unverified → `status 0`, `NOTOK`, `Contract source code not verified` (api.sh exit 3) |
| `getcontractcreation` | `contractaddresses*` comma list ≤5 | `[{contractAddress,contractCreator,txHash,blockNumber,timestamp,contractFactory,creationBytecode}]` | free LIVE | EOA → `status 0`, `No data found`, result null; result order ≠ input order |
| `verifysourcecode` (POST, Solidity/Vyper/Stylus/zkSync), `verifyproxycontract`, `checkverifystatus guid*`, `checkproxyverification guid*` | | verification flow | free | write-type actions, never needed for analysis |

### transaction

| action | key params | returns | tier |
|---|---|---|---|
| `getstatus` | `txhash*` | `{isError:"0"|"1", errDescription}` (revert reason) | free LIVE |
| `gettxreceiptstatus` | `txhash*` | `{status:"1"|"0"|""}` (post-Byzantium) | free LIVE |

### block

| action | key params | returns | tier |
|---|---|---|---|
| `getblocknobytime` | `timestamp*` (unix s), `closest*=before|after` | block number string | free LIVE |
| `getblockreward` | `blockno*` | `{blockNumber,timeStamp,blockMiner,blockReward(wei),uncles,uncleInclusionReward}` | free LIVE |
| `getblocktxnscount` | `blockno*` | `{block,txsCount,internalTxsCount,erc20TxsCount,erc721TxsCount,erc1155TxsCount}` | free LIVE |
| `getblockcountdown` | `blockno*` (future) | `{CurrentBlock,CountdownBlock,RemainingBlock,EstimateTimeInSec}`; past block → `Error! Block number already pass` | free LIVE |
| `dailyavgblocksize`, `dailyblkcount`, `dailyblockrewards`, `dailyavgblocktime`, `dailyuncleblkcount` | `startdate*`, `enddate*` (YYYY-MM-DD), `sort` | daily series | PRO |

### logs (`module=logs&action=getLogs`)

| variant | params | tier |
|---|---|---|
| by address | `address*`, `fromBlock*`, `toBlock*` (number or `latest`), page, offset | free LIVE |
| by topics | `fromBlock*`, `toBlock*`, `topic0..topic3` (≥1 required), operators `topic0_1_opr`, `topic0_2_opr`, `topic0_3_opr`, `topic1_2_opr`, `topic1_3_opr`, `topic2_3_opr` = `and|or`, page, offset | free LIVE |
| by address + topics | both of the above | free LIVE |

Returns `[{address,topics[],data,blockNumber,blockHash,timeStamp,gasPrice,gasUsed,logIndex,transactionHash,transactionIndex}]`, numeric fields **hex**. Max 1000/call, window 10,000. No address and no topic → `status 0`, `result:"Error!"` (LIVE).

### proxy (geth JSON-RPC passthrough, `module=proxy`)

| action | params | notes |
|---|---|---|
| `eth_blockNumber` | — | hex. LIVE |
| `eth_getBlockByNumber` | `tag*` hex/`latest`, `boolean*` true/false (full txs or hashes) | LIVE |
| `eth_getBlockTransactionCountByNumber` | `tag*` hex | |
| `eth_getUncleByBlockNumberAndIndex` | `tag*`, `index*` hex | |
| `eth_getTransactionByHash` | `txhash*` | `from,to,input,value(hex wei),nonce,type,blockNumber`, plus non-standard `blockTimestamp`. LIVE |
| `eth_getTransactionByBlockNumberAndIndex` | `tag*`, `index*` | |
| `eth_getTransactionReceipt` | `txhash*` | `status 0x1/0x0`, `gasUsed`, `effectiveGasPrice`, `contractAddress`, `logs[]`. LIVE |
| `eth_getTransactionCount` | `address*`, `tag` | nonce = txs sent by an EOA. LIVE |
| `eth_call` | `to*`, `data*`, `tag` (**only `latest`**) | read a view function. LIVE |
| `eth_getCode` | `address*`, `tag` | `"0x"` = EOA (or self-destructed). LIVE |
| `eth_getStorageAt` | `address*`, `position*`, `tag` | read proxy slots. LIVE |
| `eth_gasPrice`, `eth_estimateGas` | — / `data,to,value,gas,gasPrice` | |
| `eth_sendRawTransaction` | `hex*` | broadcast — **never use** (skill is read-only) |

### stats

| action | params | returns | tier |
|---|---|---|---|
| `ethprice` | — | `{ethbtc,ethbtc_timestamp,ethusd,ethusd_timestamp}` — on other chains = that chain's native token (LIVE 137: POL ≈ $0.0887 under `ethusd`) | free LIVE |
| `ethsupply` / `ethsupply2` | — | wei / `{EthSupply,Eth2Staking,BurntFees,WithdrawnTotal}` | free LIVE |
| `tokensupply` | `contractaddress*` | raw total supply | free LIVE |
| `tokensupplyhistory` | `contractaddress*`, `blockno*` | raw supply at block | PRO 2/s |
| `nodecount` | — | `{UTCDate,TotalNodeCount}` | free LIVE |
| `chainsize` | `startdate* enddate* clienttype*=geth|parity syncmode*=default|archive sort` | daily chain size | free LIVE |
| `ethdailyprice`, `dailytxnfee`, `dailynewaddress`, `dailynetutilization`, `dailyavghashrate`, `dailytx`, `dailyavgnetdifficulty`, `dailyensregister`, `nodecounthistory` | `startdate* enddate* sort` | daily series | PRO (LIVE-denied: dailytx) |

### token

| action | params | returns | tier |
|---|---|---|---|
| `tokeninfo` | `contractaddress*` | `tokenName symbol tokenType divisor totalSupply blueCheckmark description website` + socials, `tokenPriceUSD` | PRO 2/s LIVE-denied |
| `tokenholderlist` | `contractaddress*`, page, offset | holders + balances | PRO LIVE-denied (holdercount) |
| `tokenholdercount` | `contractaddress*` | count | PRO LIVE-denied |
| `topholders` | `contractaddress*`, `offset` ≤1000 | top holders | PRO 2/s LIVE-denied |

### gastracker

| action | params | returns | tier |
|---|---|---|---|
| `gasoracle` | — | `{LastBlock,SafeGasPrice,ProposeGasPrice,FastGasPrice,suggestBaseFee,gasUsedRatio}` (Gwei) | free LIVE |
| `gasestimate` | `gasprice` (wei) | seconds to confirm | free LIVE |
| `dailyavggaslimit`, `dailygasused`, `dailyavggasprice` | `startdate* enddate* sort` | | PRO |

### ens, nametag, usage, chainlist

| module/action | params | returns | tier |
|---|---|---|---|
| `ens` / `forwardresolve` | `name*` (e.g. `vitalik.eth`) | address. Mainnet only; cached ≤5 min; no CCIP/wildcard (`*.base.eth`). Unknown → `Error! Unable to resolve ENS name` | free, 1/s, LIVE |
| `nametag` / `getaddresstag` | `address*` comma list ≤100 | `{nametag,labels[],labels_slug[],reputation,url,other_attributes,…}` | **PRO+** LIVE-denied |
| `nametag` / `getlabelmasterlist`, `exportaddresstags label* format=csv|zip` | | temporary download URL (5 min) | Enterprise, LIVE-denied |
| `getapilimit` / `getapilimit` | — | `{creditsUsed,creditsAvailable,creditLimit,limitInterval,intervalExpiryTimespan}` | free LIVE |
| chainlist | `GET https://api.etherscan.io/v2/chainlist` (path, not `/v2/api`; api.sh cannot call it — use plain `curl -s`, no key) | chain table above | free LIVE |

No free name-tag / label endpoint exists. For "who is this address" on the free key, combine: `getsourcecode` (ContractName), `getcontractcreation` (deployer), `tokentx` token names, and the explorer page / Blockscout tags.

## 3. Recipes

`A` = target address, `T` = token contract. Keep `sleep 0.4` between calls.

**3.1 Full ERC-20 history of A (past the 10k window).** Ascending, 1000 per page, pages 1–10; then restart from the last block.
```
$ES etherscan 1 "module=account&action=tokentx&address=$A&startblock=$S&endblock=latest&page=$P&offset=1000&sort=asc"
```
Loop: `S=0`; for `P=1..10` fetch until a page has <1000 rows. If page 10 is full: `L=.result[-1].blockNumber`; **drop all collected rows with `blockNumber==L`**, set `S=L`, `P=1`, continue. (tokentx has no `logIndex`, so block-boundary cut is the only exact dedupe; verified LIVE that `endblock=L` resumes inside block L.) Read: `blockNumber timeStamp hash from to value tokenDecimal tokenSymbol contractAddress statusRep`. Direction: `from==A` → out, `to==A` → in (compare lowercase).

**3.2 Only one token.** Add `&contractaddress=$T` to 3.1. Only A↔B: advanced filter
```
$ES etherscan 1 "module=account&action=tokentx&contractaddress=$T&from=$A&to=$B&fromto_opr=and&page=1&offset=1000&sort=asc"
```
(`fromto_opr=or` with `from=$A&to=$A` = all transfers of A, same as `address=`.)

**3.3 Native + internal history.**
```
$ES etherscan 1 "module=account&action=txlist&address=$A&startblock=0&endblock=latest&page=1&offset=1000&sort=asc"
$ES etherscan 1 "module=account&action=txlistinternal&address=$A&startblock=0&endblock=latest&page=1&offset=1000&sort=asc"
```
txlist: `from to value(wei) isError txreceipt_status functionName methodId contractAddress`. A row with `value=0` and `functionName=transfer(…)` is a token transfer: `to` is the TOKEN CONTRACT, the real recipient is in tokentx/input. Internal: `from to value type isError` — ETH paid out by contracts (DEX swaps, bridges, exchange hot-wallet batchers). Page past 10k as in 3.1.

**3.4 Who funded A first (free substitute for PRO `fundedby`).** Take the first row of each, sort=asc, offset=1:
```
$ES etherscan 1 "module=account&action=txlist&address=$A&page=1&offset=1&sort=asc"
$ES etherscan 1 "module=account&action=txlistinternal&address=$A&page=1&offset=1&sort=asc"
$ES etherscan 1 "module=account&action=tokentx&address=$A&page=1&offset=1&sort=asc"
```
Earliest `blockNumber` with `to==A` wins; its `from` is the funder (for an internal row the funder is the contract, look at its `hash` with `eth_getTransactionByHash` to find the EOA that triggered it). If the first txlist row has `from==A`, A was funded earlier via internal/token transfer. Repeat on the funder for hop-by-hop.

**3.5 Identify an unknown counterparty X.**
1. EOA or contract: `module=proxy&action=eth_getCode&address=$X&tag=latest` → `"0x"` = EOA.
2. Contract name/verified: `module=contract&action=getsourcecode&address=$X` → `ContractName` (empty + ABI `Contract source code not verified` = unverified), `Proxy`/`Implementation` (re-run getsourcecode on Implementation for the logic name).
3. Deployer: `module=contract&action=getcontractcreation&contractaddresses=$X` → `contractCreator`, `txHash`, `contractFactory` (non-empty = deployed by a factory).
4. Activity profile: `eth_getTransactionCount` (nonce = sent txs), txlist `offset=1` asc/desc (first/last seen), `getminedblocks` (validator/builder).
5. Token? `tokensupply` returns a number for ERC-20s; `tokentx&contractaddress=$X&offset=1` gives `tokenName/tokenSymbol/tokenDecimal`.
6. Labels (exchange, sanctions): not available on free key (`getaddresstag` = PRO+). Use explorer page `https://etherscan.io/address/$X` or Blockscout.

**3.6 Token metadata (free).** `tokentx&contractaddress=$T&page=1&offset=1` → `tokenName tokenSymbol tokenDecimal`; `module=stats&action=tokensupply&contractaddress=$T` → raw supply; `getsourcecode` → contract name, proxy. `tokeninfo` (socials, price) is PRO. Reputation: `statusRep` in tokentx rows (`0` unknown, `1` neutral, `2` unsafe).

**3.7 Balances.**
```
$ES etherscan 1 "module=account&action=balance&address=$A&tag=latest"                         # wei
$ES etherscan 1 "module=account&action=balancemulti&address=$A,$B,$C&tag=latest"              # ≤20
$ES etherscan 1 "module=account&action=tokenbalance&contractaddress=$T&address=$A&tag=latest" # raw
```
Live balanceOf via eth_call: `data=0x70a08231` + 24 zero-bytes + address without `0x` (LIVE, returns hex). Past-block balance: `balancehistory`/`tokenbalancehistory` are PRO and `eth_call` accepts only `latest` → reconstruct from 3.1/3.3 sums up to the block, or use an archive RPC via `api.sh rpc`.

**3.8 Transfer logs with topic filters.**
- `topic0` Transfer(address,address,uint256) = `0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef` (LIVE). Approval = `0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925` (LIVE).
- Pad an address into a topic: `0x` + 24 zeros + 40 hex lowercase: `0x000000000000000000000000ff49627c105fce30eddad08fba158fcbfd346fd1`. topic1 = from, topic2 = to, `data` = amount (uint256 hex).
```
# all ERC-20 tokens received by A (any token contract)
$ES etherscan 1 "module=logs&action=getLogs&fromBlock=$FROM&toBlock=latest&topic0=$T0&topic0_2_opr=and&topic2=$PAD&page=1&offset=1000"
# one token, sent by A
$ES etherscan 1 "module=logs&action=getLogs&address=$T&fromBlock=$FROM&toBlock=latest&topic0=$T0&topic0_1_opr=and&topic1=$PAD&page=1&offset=1000"
```
Logs include `logIndex` (exact dedupe key `transactionHash+logIndex`) and catch tokens tokentx may index differently. Page past 10k by moving `fromBlock` to the last `blockNumber` (hex → decimal) and deduping on `transactionHash+logIndex`. Narrow block ranges avoid `Query Timeout occured`.

**3.9 Decode a transaction.**
```
$ES etherscan 1 "module=proxy&action=eth_getTransactionByHash&txhash=$H"     # from to value input blockNumber blockTimestamp
$ES etherscan 1 "module=proxy&action=eth_getTransactionReceipt&txhash=$H"    # status logs[] gasUsed effectiveGasPrice
$ES etherscan 1 "module=transaction&action=getstatus&txhash=$H"             # revert reason
$ES etherscan 1 "module=account&action=txlistinternal&txhash=$H"            # ETH moved by contracts
```
`input[0:10]` = selector: `0xa9059cbb` transfer(to,amount), `0x23b872dd` transferFrom(from,to,amount), `0x095ea7b3` approve(spender,amount). Arguments = 32-byte words after the selector (address = last 40 hex of a word). For unknown selectors read `functionName` from a txlist row of the sender, or the ABI via `getabi` on `to`. Receipt logs with Transfer topic0 = every token movement in the tx (`address` = token contract).

**3.10 Same 0x address on other chains.** One cheap probe per free chain (≈2 calls × chains):
```
for c in 1 137 42161 59144 5000 130 146 80094 143 999 9745 4326 480 42220 252 167000 50 199 2741 747474 1329 988 4352; do
  $ES etherscan $c "module=account&action=txlist&address=$A&page=1&offset=1&sort=asc";  sleep 0.4
  $ES etherscan $c "module=account&action=tokentx&address=$A&page=1&offset=1&sort=asc"; sleep 0.4
done
```
`message:"No transactions found"` = no activity there. Paid chains (BSC, Base, OP, Avalanche, Gnosis) → Blockscout/RPC (`eth_getTransactionCount`, `eth_getBalance`).

**3.11 Time ↔ block.** `module=block&action=getblocknobytime&timestamp=<unix>&closest=before` → use as `startblock`/`endblock` to cut a date range.

**3.12 Proxy implementation without verification.** `eth_getStorageAt` at EIP-1967 slot `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc` (standard, not tested live); old OpenZeppelin slot `0x7050c9e0f4ca769c69bd3a8ef740bc37934f8e2c036e5a723fd8ee048ed3f8c3` (LIVE on USDC → implementation `0x4350…02dd`, same as `getsourcecode.Implementation`).

## 4. Gotchas observed live (2026-11-09)

1. **Empty vs error both have `status:"0"`.** Empty-result messages seen: `No transactions found` (result `[]`), `No record found` (txnbridge, `[]`), `No data found` (getcontractcreation on EOA, `null`). Errors: `NOTOK` + text in `result`, or the error text in `message` with `result:null` (result-window error).
2. **api.sh exits 3 on some empty results:** its whitelist matches `No records found` (plural), so `No record found` and `No data found` are reported as errors. Treat them as "empty", not failure.
3. **Proxy errors are not caught by api.sh** (exit 0): check `.error` — e.g. bad hash → `{"code":-32602,"message":"invalid argument 0: hex string has length 4, want 64 for common.Hash"}`.
4. **Invalid address is not an error:** `balance&address=0x123` → `status 1`, `result "0"`. Validate `^0x[0-9a-fA-F]{40}$` before calling.
5. **offset > 1000 is silently cut to 1000** (no error); page×offset > 10000 is an error. Always page with `offset=1000` and block windows.
6. PRO error: `Sorry, it looks like you are trying to access an API Pro endpoint. Contact us to upgrade to API Pro.` PRO+/Enterprise: `…an API Exclusive endpoint. Contact us to upgrade your API plan.` Paid chain: `Free API access is not supported for this chain…`. Removed chain: `Missing or unsupported chainid parameter…`. Wrong action or PRO on testnet: `Error! Missing Or invalid Action name`.
7. **Fake tokens and address poisoning are common in tokentx.** Test EOA had 6 fake "USDC"/"USDT" contracts (`statusRep:"2"`, one symbol in homoglyphs `ꓴꓢꓓС`) and look-alike counterparties (`0xe50cc3b3…99d01b` vs `0xe50c3bd5…99d01b`; `0xdf954b…c707` vs `0xdf9343…ec707`, zero-value tx). Key tokens by `contractAddress`, never by symbol; compare full addresses.
8. `getcontractcreation` returns rows in its own order, not input order — match by `contractAddress`.
9. `getsourcecode` on EOA/unverified = `status 1` with empty fields; detect via `ABI=="Contract source code not verified"`. `getabi` on the same = error (exit 3).
10. Source code and ABI work with the free key on paid chains (LIVE: BSC USDT `BEP20USDT`, Base USDC ABI); all other modules there are refused.
11. Logs: `blockNumber`, `timeStamp`, `logIndex`, `gasPrice` are hex; `transactionIndex` came back as `"0x"` (empty). Account-module fields are decimal strings.
12. Missing `fromto_opr` with `from`/`to` → `Error! Missing fromto_opr (and|or) parameter`.
13. `ethprice` on non-Ethereum chains returns the native token's price under the `ethusd` key.
14. `getdeposittxs`/`getwithdrawaltxs` exist only on L2 chainids (chainid 1 → invalid action).
15. Credits ≈ 1 per call (`creditsUsed` rose 56 → 159 over ~103 calls). Check budget with `module=getapilimit&action=getapilimit`.

Not verified live: the per-second rate-limit error text (docs: `Max rate limit reached, please use API Key for higher rate limit`; not provoked, to stay ≤3/s); the community-pool error; `Query Timeout` error; minimal-proxy `Proxy:"2"`; NFT/1155 transfer field set (test address had none); PRO response shapes (from docs examples only).

## 5. Sources (read 2026-11-09)

- https://docs.etherscan.io/llms.txt and https://docs.etherscan.io/llms-full.txt
- https://docs.etherscan.io/rate-limits.md
- https://docs.etherscan.io/supported-chains.md (table renders client-side; chain data taken from https://api.etherscan.io/v2/chainlist)
- https://docs.etherscan.io/changelog.md
- https://docs.etherscan.io/common-error-messages.md
- https://docs.etherscan.io/endpoint-overview.md
- https://docs.etherscan.io/resources/best-practices.md
- https://docs.etherscan.io/resources/security-and-compliance.md
- https://docs.etherscan.io/api-reference/endpoint/<action>.md — all 97 endpoint pages (OpenAPI params parsed), incl. tokentx, txlist, txlistinternal*, advanced-filter-*, getlogs*, getsourcecode, getcontractcreation, fundedby, getaddresstag, getapilimit, chainlist, forwardresolve, topholders, balancemulti
- https://docs.etherscan.io/build-with-ai/mcp.md (keyless MCP)
