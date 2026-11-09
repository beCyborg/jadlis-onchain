# Changelog — jadlis-onchain

Формат: [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/), версии — [SemVer](https://semver.org/lang/ru/).

## [1.0.0] — 2026-11-09 — первый выпуск / first release

### Для человека
- Скилл `/onchain` разбирает адреса Tron и EVM: что это за адрес, куда ушли деньги, что на нём лежит, связаны ли адреса, нет ли отравления и открытых разрешений.
- Установщик `scripts/setup.sh` ставит crypttrace и помощник для ключей. Три бесплатных ключа заводишь сам по ссылкам из его вывода.
- Скилл только читает данные: подписать или отправить транзакцию он не может.

### For agents
- Added: `skills/onchain/SKILL.md` — routing table (question → crypttrace command → API gap-filler), check-before-concluding rules, recipes (exchange deposits by forwarding, address links, safety), answer format, run contract.
- Added: `skills/onchain/scripts/api.sh` — read-only gateway to Etherscan V2, TronGrid (GET + POST `/wallet*`), Tronscan, Blockscout v2, Blockscout metadata labels (`bsmeta`) and public JSON-RPC; keys from env or Keychain service `jadlis`, never printed; write/sign/broadcast paths exit 4; HTTP-200 errors, 3xx redirects and JSON-RPC errors exit 3; one retry on 429 and on 5xx.
- Added: `skills/onchain/scripts/evm-presence.sh` (one 0x address across 9 EVM chains; stablecoin balances where no free indexer exists), `skills/onchain/scripts/tron-addr.py` (base58 ↔ hex, ABI address params).
- Added: `skills/onchain/references/{crypttrace,etherscan,trongrid,tronscan,blockscout}.md` — live-verified 2026-11-09, incl. crypttrace's observed wrong answers.
- Added: `scripts/setup.sh` — installs `crypttrace[web]` via `uv tool` (Python 3.12) into `~/.local/share/crypttrace-bin`, writes the `crypttrace` wrapper and `crypttrace-key` into `~/.local/bin` (`--bin-dir`), loads label lists; `--check` reports keys by name and length only.
- Added: `skills/onchain/evals/evals.json` — 3 evals on public addresses (Binance Tron wallet, Ronin bridge exploiter, WETH).
