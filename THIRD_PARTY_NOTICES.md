# Third-party notices

qbe.mbt is licensed under the Apache License 2.0 (see [LICENSE](LICENSE)). It
reimplements and redistributes other open-source software; the notices below
are reproduced as required by their licenses.

## QBE

`vendor/qbe` (git submodule) and the MoonBit sources ported from it are derived
from QBE:

    © 2015-2026 Quentin Carbonneaux <quentin@c9x.me>

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the "Software"),
    to deal in the Software without restriction, including without limitation
    the rights to use, copy, modify, merge, publish, distribute, sublicense,
    and/or sell copies of the Software, and to permit persons to whom the
    Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
    THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    DEALINGS IN THE SOFTWARE.

Upstream: <https://c9x.me/compile/> (vendored mirror: <https://github.com/ripe-lang/qbe>)

## MoonBit standard libraries

- `moonbitlang/x` — Apache License 2.0
- `moonbitlang/async` — Apache License 2.0

## MoonBit runtime (bundled in the `qopple` Rust crate)

The `qopple` crate redistributes prebuilt MoonBit runtime objects
(`libmoonbitrun.o`, `libruntime.a`, `libbacktrace.a`) so it can be built
without the MoonBit toolchain. The MoonBit compiler and runtime are licensed
under the Apache License 2.0; the toolchain `CREDITS.md` additionally lists:

- wasm-opt / Binaryen — Apache License 2.0
- simdutf — MIT License
- tcc — GNU LGPL v2.1

These are components of the MoonBit toolchain; qbe.mbt redistributes only the
runtime objects named above.

## QPCC (Qopple C Compiler)

`qpcc/` is an original MoonBit program written for this repository. Its design
is informed by:

- chibicc — MIT License, Copyright (c) 2019 Rui Ueyama
  (<https://github.com/rui314/chibicc>)
- mbtcc — Apache License 2.0 (<https://github.com/moonbitlang/mbtcc>)

No third-party source code was copied into `qpcc/`.
