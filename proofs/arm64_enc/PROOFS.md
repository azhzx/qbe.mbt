# Formal verification of the AArch64 encoders

This package (`azhzx/qbe/proofs/arm64_enc`) is an experimental, independent
proof package for `object/arm64_enc.mbt`. It is built with `moon prove`
(Why3-backed) and is **not** part of the runtime build: the runtime encoders in
`object/` are untouched.

## What is proved

For each reference encoder we prove that the runtime `Int` word it returns,
read as a 32-bit bit-vector, equals the AArch64 encoding formula:

```
word(enc_*_ref(args)) == <BV32 field composition>
```

Currently:

| Encoder | Word |
| --- | --- |
| `enc_add_reg_ref` | ADD (shifted register): `sf op S 01011 ...` |
| `enc_movz_ref` | MOVZ (wide immediate): `sf opc 100101 hw imm16 Rd` |

Run:

```sh
moon prove proofs/arm64_enc   # 2 goals proved
moon test  proofs/arm64_enc   # conformance against object/
```

Reports land in `_build/verif/`.

## Model

- `BV32` is represented by Why3 `bv.BV32` (`#proof_external("bv.BV32","t")`).
- `word : Int -> BV32` is `bv.BV32.of_int`, i.e. the low 32 bits of the word.
- `band/bor/shl` on `BV32` map to `bw_and`/`bw_or`/`lsl`.

## Trusted surface

MoonBit cannot currently lower the bitwise/shift operators `&`, `|`, `<<` in a
contracted body, and `Int` is a 32-bit signed type modelled as mathematical
integers. The package therefore axiomatizes exactly three runtime primitives
(`bits.mbt`, all marked `proof_axiomatized`) with their `bv.BV32` meaning:

- `band(a,b) = a & b`  is `bw_and (word a) (word b)`
- `bor(a,b) = a | b`   is `bw_or  (word a) (word b)`
- `shl(a,s) = a << s`  is `lsl    (word a) s`

Everything above them (the field composition, opcode constants, input masks)
is then proved. The reference encoders are linked to the shipped ones by the
conformance tests in `enc_wbtest.mbt`, which compare them exhaustively over all
register values (and representative immediates).

## Limitations / next steps

- Only 2 of the ~110 encoders are proved so far. The next step is the
  representative set (`add_imm`, `adrp`, `bcond`, `cbz`, `ldp_stp`, `bitfield`,
  `fadd_d`, ...), then the rest mechanically.
- Field-extraction lemmas stated through `bv.BV32.nth` timed out with the local
  Z3-only configuration; the CI job installs a solver set and is currently
  report-only. Raising the prover budget or adding Alt-Ergo/CVC5 should let us
  prove `nth`-level specifications too.
- `words_to_bytes` (little-endian serialization) is not covered yet.
