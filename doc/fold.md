# `fold` Package API Reference

Package path: `azhzx/qbe/fold`

Constant folding. Identifies instructions whose operands are all constants, directly computes the result and replaces it with a reference to that constant. Corresponds to `fold.c` in the original QBE project.

[中文版本 (Chinese Version)](zh/fold.md)

## Entry Point

```moonbit
pub fn fold(
  @types.Fn,
  Bool,                  // -dF debug switch
  @util.Interner,        // used for generating floating-point constant labels
  Array[@types.Typ],
) -> String
```

`fold()` is called after SSA construction and before ABI processing:

```moonbit
@ssa.copy(fn_, dbg.c, interner, typs)
@ssa.filluse(fn_)
@util.eprint(@fold.fold(fn_, dbg.f, interner, typs))   // <- fold
@util.eprint(@abi_amd64.abi(fn_, typs, dbg.a, interner, typs))
```

## Folding Scope

Supported folding rules (partial list):

| Operation | Folding Rule |
| --- | --- |
| `Add`/`Sub`/`Mul`/`Div`/`Rem`/`Udiv`/`Urem` | Integer arithmetic, result truncated to `Int64` then wrapped as `Con::int` |
| `And`/`Or`/`Xor` | Bitwise operations, computed at 64-bit width |
| `Sar`/`Shr`/`Shl` | Shifts |
| `Ceq*`/`Cslt*`/`Cugt*`/... | Comparisons folded to `0`/`1` |
| `Cast` | Integer ↔ float bit reinterpretation |
| `Copy` | Direct constant propagation |
| `Extsb`/`Extub`/`Extsh`/... | Sign/zero extension |

Any operation with `canfold = true` in `OpInfo` enters the folding path.

## Debug Output

When `Bool = true`, returns `-dF` debug dump text listing each folded instruction and its replacement result; non-debug mode returns an empty string.

## Dependencies

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## Notes

- Folding is **conservative**: if any operand is not `Ref::RCon`, the instruction remains unchanged.
- Floating-point constants produced by folding are interned via `Interner` and ultimately output in the `.rodata` segment during the emit phase.
