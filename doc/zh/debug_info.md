# 调试信息（Debug Info）

qbe.mbt 在 IL 中携带源码位置，并发出调试器所需的汇编指示。这些指示就是上游
QBE 已定义的那套，因此调试输出同样与 `vendor/qbe` 逐字节一致。

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
`dbgloc` 是无结果的指令：它流经 SSA 各 pass，代码生成时被忽略。

## 发出的内容

所有输出 GAS 文本的后端（amd64、arm64、rv64、la64）都会发出：

    .file 1 "hello.c"
    ...
        .loc 1 2
    ...
        .loc 1 4 3

汇编器据此生成 DWARF `.debug_line` 段。`--jit`、`--run-asm`、`--emit obj`
和解释器会跳过 `dbgloc`（它只是元数据）。

## 验证

    python compare.py test/dbg           # 与 vendor/qbe 逐字节一致
    moon test -p parser -p util          # 解析器与指示测试

`test/dbg/` 覆盖行号场景（顺序、文件去重、列号、多文件）；三个差分目标在
全部 debug flag 下通过。

## 试用

    M=./_build/native/debug/build/cmd/main/main.exe
    $M -t arm64 -G m test/dbg/001_loc.ssa > out.s
    clang -c -g out.s -o out.o        # 目标文件中出现 __debug_line
    llvm-dwarfdump --debug-line out.o

## 局限与路线图

- 目前只有行号表，还没有 DWARF `.debug_info`：
  - 在 ELF（Linux）上 `lldb`/`gdb` 已经可以按源码断点、单步；
  - 在 macOS 上，链接器只有在目标文件带有编译单元时才建立 DWARF debug map，
    所以终端里用 `lldb` 还需要下面的 `.debug_info` 里程碑。`.file`/`.loc`
    的输出本身不变。
- 尚无 CFI（`.cfi_*`），优化后的栈展开不保证可用。
- 计划：CFI/`.eh_frame`，再补最小 `.debug_info` 编译单元，最后做 builder 侧的
  变量/类型元数据（`ir_builder` + C ABI + Rust）。
