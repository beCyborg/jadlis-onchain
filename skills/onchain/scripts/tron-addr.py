#!/usr/bin/env python3
"""tron-addr.py — Tron address conversions for contract reads (stdlib only, offline).

  tron-addr.py hex   T...            -> 41-prefixed hex (21 bytes)
  tron-addr.py b58   41.../0x...     -> base58check T-address
  tron-addr.py param T... [T... ...] -> ABI-encoded address arguments for
                                        triggerconstantcontract "parameter"
                                        (each address = 20 bytes left-padded to 32)

Example (USDT allowance owner->spender):
  P=$(tron-addr.py param <owner> <spender>)
  api.sh trongrid-post /wallet/triggerconstantcontract \
    '{"owner_address":"<owner>","contract_address":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
      "function_selector":"allowance(address,address)","parameter":"'$P'","visible":true}'
"""
import hashlib
import sys

ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


def _checksum(b: bytes) -> bytes:
    return hashlib.sha256(hashlib.sha256(b).digest()).digest()[:4]


def to_hex(addr: str) -> str:
    n = 0
    for c in addr:
        if c not in ALPHABET:
            raise ValueError(f"not base58: {addr}")
        n = n * 58 + ALPHABET.index(c)
    raw = n.to_bytes(25, "big")
    if raw[0] != 0x41 or _checksum(raw[:21]) != raw[21:]:
        raise ValueError(f"bad Tron address checksum: {addr}")
    return raw[:21].hex()


def to_b58(h: str) -> str:
    h = h.lower().removeprefix("0x")
    if len(h) == 40:
        h = "41" + h
    raw = bytes.fromhex(h)
    if len(raw) != 21 or raw[0] != 0x41:
        raise ValueError(f"expected 21-byte 41-prefixed hex: {h}")
    full = raw + _checksum(raw)
    n = int.from_bytes(full, "big")
    out = ""
    while n:
        n, r = divmod(n, 58)
        out = ALPHABET[r] + out
    return out


def main() -> int:
    if len(sys.argv) < 3 or sys.argv[1] not in ("hex", "b58", "param"):
        print(__doc__, file=sys.stderr)
        return 1
    cmd, args = sys.argv[1], sys.argv[2:]
    try:
        if cmd == "hex":
            print(to_hex(args[0]))
        elif cmd == "b58":
            print(to_b58(args[0]))
        else:
            print("".join(to_hex(a)[2:].rjust(64, "0") for a in args))
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
