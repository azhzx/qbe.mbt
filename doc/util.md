# `util` Package API Reference

Package path: `azhzx/qbe/util`

General-purpose utility package providing error types, string interning, formatting, and terminal output primitives. Depended upon by almost all other packages.

[中文版本 (Chinese Version)](zh/util.md)

## Error Types

```moonbit
pub(all) suberror QbeError {
  ParseError(String, Int, String)  // (file, line, msg)
  CompileError(String)              // (msg)
  Ice(String)                       // (msg) - internal compiler error
}
```

All compilation stages throw this error via `raise`. The `ParseError::parse_error` constructor uses named parameters `file~`, `line~`, `msg~`.

## String Interning - `Interner`

Maps symbol strings to unique integer IDs for fast comparison in later stages:

```moonbit
pub struct Interner {
  table : Map[String, Int]
  values : Array[String]
}

pub fn Interner::new() -> Interner
pub fn Interner::intern(Self, String) -> Int   // intern string, return id
pub fn Interner::get(Self, Int) -> String      // reverse lookup by id
pub fn Interner::lookup(Self, String) -> Int   // query, returns -1 if not interned
```

There is also a **module-level** global interner:

```moonbit
pub fn intern(s : String) -> Int
```

Used for generating symbol labels (e.g., floating-point constant labels).

## Output Primitives

```moonbit
pub async fn iprint(String) -> Unit  // output to stdout (final assembly)
pub async fn eprint(String) -> Unit  // output to stderr (debug dump and errors)
```

These functions are `async`, corresponding to QBE's `printf`/`fprintf(stderr, ...)`.

## Formatting Helpers

| Function | Purpose |
| --- | --- |
| `fmt_fixed(Double, Int) -> String` | Fixed-point decimal formatting (for floating-point constant output) |
| `lpad(String, Int) -> String` | Left-pad to specified width |
| `rpad(Int, Int) -> String` | Right-pad numbers |

## Sorting

```moonbit
pub fn qsort_int(Array[Int], Int, Int, (Int, Int) -> Int) -> Unit
```

Quick sort, used for sorting temporary variables by ID and similar scenarios.

## Dependencies

- `moonbitlang/core/debug`: Used for `QbeError`'s `Debug` implementation.
