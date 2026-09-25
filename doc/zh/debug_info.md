# 调试信息（Debug Info）

qbe.mbt 在 IL 中携带源码位置，并发出调试器所需的汇编指示。行号这类指示就是上游
QBE 已定义的那套，因此其输出同样与 `vendor/qbe` 逐字节一致。

## IL 语法（QBE 已有）

两条语句，原样取自上游 QBE：

    dbgfile "path/to/source.c"   # 顶层：声明源文件
    dbgloc LINE                  # 函数内：源码行
    dbgloc LINE, COL             # ... 带列号

示例：

    dbgfile "hello.c"
    export function w $main() {
    @start
        dbgloc 2
        %y =w add 1, 2
        dbgloc 4, 3
        ret %y
    }

`dbgfile` 可出现在函数/数据之间任意位置；重复路径按首次出现去重并编号。
`dbgloc` 是无结果指令：流经 SSA 各 pass，代码生成时被忽略。`dbgfile` 必须出现在
第一个 `dbgloc` 之前：没有当前文件时上游同样输出 `.loc 0`，汇编器会拒绝。

## 行号表

所有输出 GAS 文本的后端（amd64、arm64、rv64、la64）都会发出：

    .file 1 "hello.c"
    ...
        .loc 1 2
    ...
        .loc 1 4 3

汇编器据此生成 DWARF `.debug_line` 段。`--jit`、`--run-asm`、`--emit obj`
和解释器会跳过 `dbgloc`（它只是元数据）。

## 栈展开（CFI，`-g`）

`-g` / `--debug-info` 会为 amd64 和 arm64 额外发出 DWARF 调用帧信息，汇编器
据此生成 `.eh_frame`（以及 `.debug_frame`）：

    fact:
        .cfi_startproc
        endbr64
        pushq %rbp
        .cfi_def_cfa_offset 16
        .cfi_offset %rbp, -16
        movq %rsp, %rbp
        .cfi_def_cfa_register %rbp
        ...
        leave
        .cfi_def_cfa %rsp, 8
        .cfi_restore %rbp
        .cfi_endproc

arm64 对应发出 `w29`/`w30` 与被调用者保存寄存器的偏移（`x19..`、`d8..`）。
CFI 默认关闭，因此普通输出仍与上游逐字节一致（上游不发出 CFI）。rv64/la64
暂未发出 CFI。

## 编译单元（`.debug_info`，`-g`）

`-g` 还会发出一个最小 DWARF5 编译单元，让调试器能把代码地址映射回源文件/行号：

    .section .debug_abbrev,"",@progbits   # Mach-O：__DWARF,__debug_abbrev
    ...
    .section .debug_info,"",@progbits
        .long 37          # 单元长度
        .short 5          # DWARF 版本
        .byte 1           # DW_UT_compile
        .byte 8           # 地址宽度
        .long 0           # abbrev 偏移
        .byte 0x01        # DW_TAG_compile_unit
        .asciz "qbe.mbt"  # producer
        .short 12         # DW_LANG_C99
        .asciz "hello.c"  # CU 名（第一个 dbgfile）
        .asciz "."        # comp_dir
        .byte 0           # DW_AT_low_pc  -> addrx 0
        .byte 1           # DW_AT_high_pc -> addrx 1
        .long 0           # DW_AT_stmt_list（汇编器生成的 .debug_line）
        .long 8           # DW_AT_addr_base
    .section .debug_addr,"",@progbits
        ...
        .quad main        # addrx 0
        .quad .Ldbgend    # addrx 1（.text 末尾）

CU 的 `DW_AT_low_pc`/`high_pc` 用 `DW_FORM_addrx`，地址放在 `.debug_addr`
（与 clang 相同），因此 `.debug_info` 在 Mach-O 上不含重定位，链接器的
debug map 会重定位 `.debug_addr`。ELF 用 `.debug_*,"",@progbits`，Mach-O
用 `__DWARF,__debug_*`。

macOS 上端到端可用（无需 dSYM，lldb 直接读目标的 debug map）：

    $M -g -t arm64 -G m demo.ssa > demo.s
    clang -c -g demo.s -o demo.o
    clang demo.o -o demo_prog
    lldb -o 'b one.c:3' -o run -o bt ./demo_prog

## 验证

    python compare.py test/dbg           # 与 vendor/qbe 逐字节一致（不带 -g）
    moon test -p parser -p util          # 解析器与指示测试

    M=./_build/native/debug/build/cmd/main/main.exe
    $M -g -t arm64 -G m demo/04_recursion.ssa > out.s
    clang -c -g out.s -o out.o
    llvm-dwarfdump --eh-frame out.o      # 每个 PC 的 CFA 规则

`test/dbg/` 覆盖行号场景（顺序、文件去重、列号、多文件）；三个差分目标在
全部 debug flag 下通过。

## 试用

    M=./_build/native/debug/build/cmd/main/main.exe
    $M -t arm64 -G m test/dbg/001_loc.ssa > out.s
    clang -c -g out.s -o out.o        # 目标文件中出现 __debug_line
    llvm-dwarfdump --debug-line out.o

## 局限与路线图

- 目前是行号表 + 最小 DWARF5 编译单元 + amd64/arm64 的 CFI。还没有变量/类型
  的 DIE：调试器能显示文件/行号、能展开栈，但 `frame variable` 为空。
- 在 macOS 上调试纯汇编构建前先删掉旧的 `*.dSYM`：空的 dSYM 会遮住 lldb 本来
  会使用的目标文件 debug map。
- 计划：builder 侧的变量/类型元数据（`ir_builder` + C ABI + Rust）、rv64/la64
  的 CFI，以及自包含 `.o` / JIT 路径的 DWARF。
