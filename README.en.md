[Русский](README.md) · English

# Paste a wallet address — the agent tells you whose it is, where the money went and what is risky

`jadlis-onchain` is the `/onchain` skill for Claude Code. It analyses addresses and transactions on Tron
(TRX, USDT TRC-20) and on EVM chains: Ethereum, Polygon, Arbitrum, Base, Optimism, BSC.
The skill only reads the chain. It cannot sign or send a transaction.

```
claude plugin install jadlis-onchain --marketplace https://github.com/beCyborg/jadlis-hub.git
```

For Claude Code older than 2.1.292 — two commands:

```
claude plugin marketplace add https://github.com/beCyborg/jadlis-hub.git
claude plugin install jadlis-onchain@jadlis
```

This is my working setup published as is, not a product.

## What it does

| Question | What the skill does |
|---|---|
| Whose address is this? | Collects labels from four sources: crypttrace (OFAC, ScamSniffer, exchange wallets), Tronscan, the Blockscout label service, the contract name from Etherscan. It presents a label as a label, not as proven ownership. |
| Where did the money go? | Traces USDT, not only TRX or ETH. Checks against the full transfer list: `crypttrace trace` shows only the three largest outflows. |
| Are there exchanges among the recipients? | Finds exchange deposit addresses: an address that forwards the whole amount within minutes to a labelled exchange wallet. Gives the evidence level for each row. |
| Where is a 0x address active? | Checks one address on nine EVM chains: outgoing transactions, balance, tokens. On chains without free history it reads USDC and USDT balances straight from the contracts. |
| Are these addresses linked? | Looks for direct transfers and shared counterparties. For a 0x/T pair it checks whether they share one key. Cross-chain swaps are matched by time and amount and reported as an inference. |
| Is it safe? | Finds look-alike addresses (address poisoning), unlimited USDT spending approvals, frozen USDT/USDC, spam tokens with links. |

What is inside:

- `skills/onchain/SKILL.md` — which tool for which question, mandatory checks, recipes, answer format.
- `skills/onchain/scripts/api.sh` — a gateway to Etherscan V2, TronGrid, Tronscan, Blockscout and public RPCs. It injects the key and never prints it. It blocks calls that sign or send a transaction.
- `skills/onchain/references/` — references built from the official docs. Every claim in them was checked with a live call on 2026-11-09. They also list where crypttrace answers wrongly.

## Installing

1. Install the plugin with the command above.
2. Run the installer. It installs crypttrace via uv, the key wrapper and the `crypttrace-key` helper:

   ```
   bash "$(claude plugin list --json | jq -r '.[] | select(.id|startswith("jadlis-onchain@")) | .installPath')/scripts/setup.sh"
   ```

   It needs `uv`, `jq`, `curl`, `python3`. `~/.local/bin` must be on `PATH`. The same script with `--check` shows the state without changing anything.
3. Get three free keys. Each one is an email and a password, no card:
   - Etherscan: https://etherscan.io/register, then https://etherscan.io/myapikey. Opens history on Ethereum, Polygon, Arbitrum, Linea and 20 more chains.
   - Tronscan: https://tronscan.org/#/myaccount/apiKeys. Gives labels and risk on Tron. Tronscan is throttling keyless access.
   - TronGrid: https://www.trongrid.io/register, then a key in the dashboard. Raises the Tron rate limit.
4. Copy each key and run `crypttrace-key etherscan`, `crypttrace-key tronscan`, `crypttrace-key trongrid`. The key goes from the clipboard into the macOS Keychain. Only its length is printed.

On Linux, instead of step 4 set `ETHERSCAN_API_KEY`, `TRONSCAN_API_KEY`, `TRONGRID_API_KEY`.

## Using it

Paste an address or a transaction hash into Claude Code and ask:

```
Check TMuA6YqfCeX8EhbfYEg5y7S4DqzSJireY9: is it an exchange, what does it hold?
Whose address is 0x098B716B8Aaf21512996dC57EB0615e2383E2f96 and is it sanctioned?
Where did the USDT from T… go? Are there exchanges among the recipients?
```

The skill picks the chain from the address format. The answer opens with a verdict per address, followed by a table, money flows and explorer links. Facts and inferences are labelled separately.

## Limits, cost, updating

- The keys are free. Limits: Etherscan — 3 calls per second and 100,000 per day, TronGrid with a key — 100,000 per day.
- Transfer history on Base, BSC, Avalanche and Gnosis is not available on the free tier. Etherscan gives it only on a paid plan, and Blockscout for these chains is closed to scripts. There the skill shows current balances only and says plainly that history was not checked.
- A label is the source's label, not proven ownership. A risk score of 0 means "no known bad label", not "clean".
- Tested on macOS. Linux needs the manual environment-variable step.
- Updates are off by default for recipients. Update by hand:

  ```
  claude plugin update jadlis-onchain@jadlis
  ```

  Or turn on auto-update once: `/plugin` → Marketplaces → jadlis.
