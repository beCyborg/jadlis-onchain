# crypttrace — command reference (verified 2026-11-09, PyPI crypttrace, installed via uv tool)

Run as `crypttrace …` — the `~/bin/crypttrace` wrapper exports `ETHERSCAN_API_KEY`, `TRONSCAN_API_KEY`, `TRONGRID_API_KEY` from the Keychain (service `jadlis`) and execs the real binary in `~/.local/share/crypttrace-bin/`. Upgrade: `UV_TOOL_BIN_DIR=~/.local/share/crypttrace-bin uv tool upgrade crypttrace`. Local data: `~/.crypttrace/` (label DB, response cache, cases); reports default to `~/crypttrace-reports/`.

Chains (`--chain/-c`, default `eth`): `eth arbitrum polygon` (free Etherscan key) · `bsc base optimism` (refuse on the free key: "Etherscan's free plan does not cover base…" — use `api.sh blockscout` / `api.sh rpc`) · `tron sol ton btc ltc doge` (keyless public endpoints). The value is `eth`, never `ethereum`.

`--asset/-a`: `eth` (= the chain's native coin; on Tron that is TRX) by default, or a token symbol (`usdt`, `usdc`, `dai`, `weth`…) or a contract address. **Most stolen/moved value on Tron is USDT — pass `--asset usdt`, otherwise trace/timeline/victims follow TRX only.**

## Commands

| Command | Purpose | Key options |
|---|---|---|
| `investigate ADDR` | Whole pipeline + "what to do next"; writes a case file | `-c`, `-a`, `-d` depth (3), `-o` folder |
| `profile ADDR` | Native balance, transfer count, first/last seen, label, risk 0–100, top counterparties | `-c` |
| `tokens ADDR` | Token holdings reconstructed from transfer history, USD; spam/counterfeit hidden | `-c`, `--all` (show spam with reason) |
| `trace ADDR` | Hop-by-hop flow tree, labels per node | `-c`, `-a`, `-d` (3), `-b` branching (3), `-D out\|in`, `-o file.graphml\|.csv` |
| `timeline ADDR` | Activity histogram; detects automated sweeps | `-c`, `-a`, `-b` buckets, `--min-value`, `--include-dust` |
| `victims ADDR` | Every address that fed a consolidation wallet | `-c`, `-a`, `-d`, `--top`, `-o csv` |
| `funder ADDR` | Backward chain of first-gas funding toward a KYC/exchange point | `-c`, `-H` hops (6) |
| `cluster ADDR` | Likely same-owner wallets (BTC common input; EVM shared gas funder) | `-c`, `--checks` (60) |
| `offramp ADDR` | Is this an exchange deposit address (cash-out)? | `-c` |
| `crosschain ADDR` | Likely arrivals on other chains after a bridge-out | `-c`, `-w` hours (48), `--tol` (0.05) |
| `freeze ADDR` | Is USDT/USDC here frozen; who can freeze it | `-c` |
| `poisoning ADDR` | Look-alike addresses planted in the history | `-c`, `--limit` (1000) |
| `check ADDR` | "Was my wallet drained?" — thief, other victims, next steps | `-c` |
| `evidence ADDR` | Evidence pack for exchange / police | `-c`, `-l en\|ru`, `-o` |
| `assess ADDR` | Stated conclusion with reasoning | `-c`, `-a`, `-d` |
| `report ADDR` | Full investigation → HTML + Markdown + JSON | `-c`, `-a`, `-d`, `-b`, `-o` |
| `verify ADDR` | Cross-check the tool's totals against the chain | `-c`, `-a`, `--limit` |
| `label ADDR` | Local label DB lookup + risk (no `--chain` option) | — |
| `labels why\|check\|audit` | Evidence behind a label; checksum validation; DB audit | — |
| `update-labels` | Refresh OFAC + ScamSniffer lists (3,470 labels on 2026-11-09) | `--okx` (+~300k OKX deposit addresses, ~80 MB) |
| `store info\|clear\|link SRC DST` | Local cache; `link` = are two addresses connected in collected data | `-c` |
| `watch add\|list\|remove\|run` | Watchlist with cash-out alerts | — |
| `case new\|list\|add\|remove\|note\|show\|refresh` | Investigation as a file in `~/.crypttrace/cases` | — |
| `serve` | Local web UI with interactive graph, `127.0.0.1:8000` | `--port` |
| `chains` | Supported chains | — |

Global flags go BEFORE the command: `crypttrace --fresh trace …` (ignore cache), `--offline` (cache only).

## Behaviour observed live (2026-11-09)

- `profile` shows only the **native** balance (TRX/ETH). A USDT wallet looks empty there — always run `tokens` too.
- `timeline` without `--asset usdt` on Tron counts TRX only; tokens and 100+ dust transfers are dropped by default.
- `trace` follows only the top `-b 3` outflows per hop. On a test wallet tens of thousands of USDT left in about 40 transfers; trace showed 3. For "where did ALL the money go" list every transfer via TronGrid/Etherscan, or raise `-b` and accept a wide tree.
- `trace` labels only what is in the local DB + exchange reserve lists. Big contracts show as ⚪ unknown (WETH `0xC02aaA39…` appeared unlabelled with 45 ETH / 191 tx) — identify unknown hubs through the APIs (`references/etherscan.md` getsourcecode, `references/blockscout.md`, `references/tronscan.md` tags) before calling them a person.
- A ⚪ node with hundreds of tx and six-figure volume is usually a service/exchange/contract, not an individual — say so as an inference, not a fact.
- `verify --chain tron` returns `UNCHECKED — no independent totals for this chain`. On Tron cross-check totals yourself with TronGrid (`references/trongrid.md`).
- `poisoning` on active Tron USDT wallets typically finds 10+ "weak match" look-alikes (same first 1–4 and last 4–6 chars). The real risk: a real counterparty `TAbCd…Xy7M` next to a bait `TAbEf…Xy7M` that sent 1 USDT right after the real transfer. Warn the user never to copy an address from history.
- Risk score 0/100 means "no known bad label", not "clean".

## Wrong answers seen in eval runs (2026-11-09) — cross-check these every time

- `tokens -c tron` answered "No token transfers" for a test wallet, while TronGrid showed two dozen USDT transfers. Never report "no tokens" on Tron from crypttrace alone.
- `tokens -c eth` counted a counterfeit "USDC" (homoglyph symbol, foreign contract) as balance despite its spam filter. Check the contract address of every stablecoin it lists (USDC `0xA0b86991…`, USDT `0xdAC17F95…` on Ethereum).
- `poisoning` reported "300.78 sent to a look-alike" — it was a transfer of a FAKE token emitted by the scammer's contract; the real USDC went to the real address. Before calling a poisoning hit a loss, confirm the token contract is the real one.
- `verify -c eth` also returned `UNCHECKED`. Treat `verify` as optional; cross-check with Etherscan `tokenbalance` or `balanceOf`.
- `offramp -c tron` looks only at TRX forwarding; USDT deposit addresses come back "not an off-ramp". Use the forwarding recipe in SKILL.md.
- From hop 2 on, a `trace` edge shows the counterparty's **whole turnover** (e.g. a DEX router's 45 ETH / 191 tx), not this wallet's money. Only hop-1 edges are this wallet's transfers.
- Errors are explicit (free-plan chain refusal, missing key) — never report them as "empty wallet".
