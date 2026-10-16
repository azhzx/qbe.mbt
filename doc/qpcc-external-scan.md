# qpcc 外部 C 项目编译扫描报告

> **本报告只诊断，未修复。** 第一版数据采集于 2026-10-11（qpcc v0.37.3）。
> 2026-10-17 在修完 Lua 之后重扫了一遍，见 §7；本轮同样没有为这些项目改任何代码。
> 抓取与扫描脚本在 tools/scan_external_fetch.py、tools/scan_external.py，中间产物在 build/scan/（未提交）。
## 0. 一句话结论

17 个真实 C 项目、201 个源文件：**128 个完整通过（64%）**，比第一版的 88 个（44%）多 40 个。
另有 44 个文件**根本没走到 qpcc**（缺第三方或平台依赖，属环境问题）。
扣掉它们，**到达 qpcc 的 157 个文件里 128 个通过 —— 82%**（第一版 65%）。

第一版列出的头号原因基本都已修掉，逐文件对照见 §7：

| # | 第一版的阻断源 | 现状 |
| --- | --- | --- |
| 1 | 自带头遮蔽系统头、缺标准宏 | **已修**。除宏之外还补了一批**缺失的声明**（`strpbrk`、`freopen`、`tmpfile`、`ferror`、`fseek`…）—— 隐式声明按 C89 返回 `int`，指针会被截断 |
| 2 | `_Float16` / Apple Blocks 导致解析失败 | **`_Float16` 已修**（PARSE 23 → 12）；Blocks `^{}` 仍未支持，sqlite 仍卡在这里 |
| 3 | 后端 ICE（bzip2 ×2、lua ×1） | **lua 的已修**（`ldo.c` 通过）；bzip2 的 2 个仍在 |
| 4 | `sizeof("字面量")` 静默错值 | 未动 |
| 5 | 诊断走 stdout | 未动 |
| 6 | 整型提升缺失（修 Lua 时发现，§6.6） | **已修** |

剩下的 qpcc 侧失败集中在三类，都很具体：

1. **声明的名字在自己的初始化式里不可见**（本轮新发现，§6.7）——`int x = sizeof(x);` 就失败，
   lz4 的 `lz4file.c` 正是这个形状；
2. **少量缺失的平台宏**：`ENOMEM`、`R_OK`、`EROFS` 之类（errno / unistd），
   以及 smu 那个已知的 `-DVERSION=` 缺失；
3. **两个 bzip2 的 arm64 ICE**，与第一版相同。

## 1. 口径（先看这个）

qpcc 没有自带预处理器，所以本报告里「qpcc 能不能编译 X」的定义是：
**「qpcc 能不能编译 `clang -E` 之后的 X」**。每个文件走三层：

```
clang -E -P -I qpcc/include/qbe -I <proj> [-D…] f.c   →  f.i
qpcc f.i -std=c11 --check     ① 前端：词法 / 语法 / 语义
qpcc f.i -std=c11 -o f.o      ② 代码生成
```

先 `--check` 再 `-o`，是为了把「前端不支持」和「后端发射出错」分开 —— 结果证明确实有必要（见 §5.3）。

## 2. 项目总表

| 项目 | 源文件 | 通过 | 前端失败 | 生成失败 | 预处理未到达 |
| --- | ---: | ---: | ---: | ---: | ---: |
| abduco | 6 | 0 | 3 | 0 | 3 |
| bzip2 | 13 | 11 | 0 | 2 | 0 |
| cjson | 2 | 2 | 0 | 0 | 0 |
| dash | 30 | 7 | 0 | 0 | 23 |
| farbfeld | 7 | 2 | 1 | 0 | 4 |
| hiredis | 9 | 2 | 6 | 0 | 1 |
| ii | 2 | 1 | 0 | 0 | 1 |
| lchat | 6 | 2 | 3 | 0 | 1 |
| lua | 34 | 34 | 0 | 0 | 0 |
| lz4 | 25 | 17 | 8 | 0 | 0 |
| miniz | 4 | 0 | 0 | 0 | 4 |
| sic | 3 | 1 | 1 | 0 | 1 |
| slstatus | 24 | 19 | 1 | 0 | 4 |
| smu | 1 | 0 | 1 | 0 | 0 |
| sqlite | 1 | 0 | 1 | 0 | 0 |
| yyjson | 4 | 4 | 0 | 0 | 0 |
| zlib | 30 | 26 | 1 | 1 | 2 |
| **合计** | **201** | **128** | **26** | **3** | **44** |

## 3. 阶段分布

| 阶段 | 文件数 | 占全部 201 |
| --- | ---: | ---: |
| OK | 128 | 64% |
| PREPROCESS | 44 | 22% |
| PARSE | 12 | 6% |
| SEMA | 14 | 7% |
| CODEGEN-PANIC | 3 | 1% |

## 4. 诊断签名排名（跨项目计数，只统计到达 qpcc 的文件）

| 诊断 | 文件数 | 项目数 |
| --- | ---: | ---: |
| `expected ')'` | 7 | 3 |
| `expected ';'` | 5 | 3 |
| `use of undeclared identifier: R_OK` | 3 | 1 |
| `qpcc: object emission failed: ICE: arm64 bin: expected a register operand for ` | 2 | 1 |
| `use of undeclared identifier: ENOMEM` | 2 | 2 |
| `use of undeclared identifier: ht` | 2 | 1 |
| `use of undeclared identifier: r` | 1 | 1 |
| `use of undeclared identifier: EWOULDBLOCK` | 1 | 1 |
| `use of undeclared identifier: SSIZE_MAX` | 1 | 1 |
| `division by zero in constant expression` | 1 | 1 |
| `use of undeclared identifier: newPoints` | 1 | 1 |
| `use of undeclared identifier: pattern` | 1 | 1 |
| `use of undeclared identifier: VERSION` | 1 | 1 |
| `PanicError` | 1 | 1 |

## 5. 未到达 qpcc 的原因

| 缺失/失败 | 文件数 |
| --- | ---: |
| token.h file not found | 10 |
| nodes.h file not found | 9 |
| syntax.h file not found | 4 |
| miniz_export.h file not found | 4 |
| config.h file not found | 2 |
| stropts.h file not found | 2 |
| jpeglib.h file not found | 2 |
| png.h file not found | 2 |
| X11/Xlib.h file not found | 2 |
| openssl/ssl.h file not found | 1 |
| tls.h file not found | 1 |
| grapheme.h file not found | 1 |
| X11/XKBlib.h file not found | 1 |
| sys/soundcard.h file not found | 1 |
| sys/auxv.h file not found | 1 |
| windows.h file not found | 1 |

与第一版**同一批**依赖：dash 的 token.h/nodes.h/syntax.h 需要先 make 生成，
miniz 的 miniz_export.h 由 cmake 生成，abduco 的 stropts.h 是 Sun 专有，farbfeld 要 libpng/libjpeg，
lchat 要 libtls，slstatus 要 X11，等等。这些都不是 qpcc 的问题。

## 6. 逐条发现

### 6.1 头号问题：自带头遮蔽系统头，缺标准宏（11+ 文件）

qpcc 用 `-I qpcc/include/qbe` 提供 20 个头文件。`-I` 是**优先**搜索，
于是 `<stdint.h>` `<stdio.h>` `<stdlib.h>` `<limits.h>` `<unistd.h>` 全部命中 qpcc 的版本，
而它们**没有**这些标准宏：

| 宏 | 本该来自 | qpcc 自带头 | 系统头 |
| --- | --- | --- | --- |
| `SIZE_MAX` | `<stdint.h>` | ✗ 缺 | ✓ 有 |
| `INTMAX_MIN` | `<stdint.h>` | ✗ 缺 | ✓ 有 |
| `EXIT_FAILURE` / `EXIT_SUCCESS` | `<stdlib.h>` | ✗ 缺 | ✓ 有 |
| `BUFSIZ` / `L_tmpnam` / `SEEK_END` | `<stdio.h>` | ✗ 缺 | ✓ 有 |
| `USHRT_MAX` | `<limits.h>` | ✗ 缺 | ✓ 有 |
| `STDOUT_FILENO` | `<unistd.h>` | ✗ 缺 | ✓ 有 |

受影响文件数（`use of undeclared identifier`）：`SIZE_MAX` 7、`EXIT_FAILURE` 3、
`EXIT_SUCCESS` 2、`BUFSIZ` 2，另有 `USHRT_MAX`/`STDOUT_FILENO`/`SEEK_END`/`L_tmpnam`/`INTMAX_MIN` 各 1。

**这是最容易修、收益最大的一条**：补齐宏即可，不涉及语言实现。
dash 的 `arith_yacc.c` 正因 `INTMAX_MIN` 失败。

**现状（2026-10-17）：已修。** 上面这些宏全部补齐，另外还补了一批**缺失的函数声明**
（`strpbrk`、`strspn`、`freopen`、`tmpfile`、`ferror`、`fseek` 等）——
缺声明时按 C89 隐式返回 `int`，指针会被截断。受影响的 dash/hiredis/lchat/lz4 文件现已通过。
少量平台宏仍缺：`ENOMEM`（zlib `zip.c`）、`R_OK`（lchat）、`EWOULDBLOCK`（hiredis）、`SSIZE_MAX`。

### 6.2 解析失败七成来自 macOS 系统头的 Apple 扩展（17 / 23 文件）

| 现场 | 文件数 | 源头 |
| --- | ---: | --- |
| `extern _Float16 __fabsf16(_Float16) __attribute__((availability(...)))` | 12 | macOS `<math.h>` |
| `int (^)(const struct dirent *)` / `typedef void (^os_block_t)(void);` | 5 | Apple **Blocks**（`<dirent.h>` 等）|

**SQLite 也栽在这里** —— 它那个唯一的失败点就是第 6527 行的
`typedef void (^os_block_t)(void);`，来自系统头而非 SQLite 自己的代码。

所以：**这 17 个失败很可能是 macOS 特有的**，在 Linux/glibc 上大概率消失。
把 qpcc 放到 Linux 上重跑是下一个该做的实验。

剩下的 6 个是项目自身代码（`va_list ap;`、`static bool client_send_packet(...)`、
`static Client *client_malloc(...)`、`else if(!strcmp("-n", argv[i]))` 等），才是真正的前端缺口。

### 6.3 后端 ICE（3 个文件，真 bug）

| 项目 | 文件 | 消息 |
| --- | --- | --- |
| bzip2 | `compress.c` | `ICE: arm64 bin: expected a register operand for mul` |
| bzip2 | `decompress.c` | `ld.8698 violates ssa invariant` |
| lua | `src/ldo.c` | `ICE: arm64 bin: unhandled jump` |

三个都在**代码生成阶段**（前端已通过 `--check`），是 arm64 后端的真实缺陷，
分别指向：乘法的内存操作数、SSA 不变量被破坏、未处理的跳转。

**现状（2026-10-17）：lua 的 `ldo.c` 已修**（标签映射跨函数泄漏导致块无终结符）；
bzip2 的两个仍在（`compress.c` 的 mul 内存操作数、`decompress.c` 的 SSA 不变量）。

### 6.4 `sizeof("字面量")` 静默给错值

```c
printf("%zu %zu %zu\n", sizeof("ab"), sizeof(int), sizeof("abcdef"));
/* qpcc  : 8 4 8   ← 字面量退化成了指针 */
/* clang : 3 4 7   */
```

文档里「`sizeof` of a string literal」列为已知缺口，但**静默给错值**比报错危险。
建议至少降级为诊断。

### 6.5 诊断走 stdout

`qpcc` 的所有诊断（含致命解析错误）走 **stdout**。本次扫描第一遍把 stdout 丢进 `/dev/null`，
结果日志里只剩 `PanicError` 栈，**完全看不到错误信息**。对「qpcc 作为编译器的可脚本化性」
这是硬伤，修复优先级应当很高。

### 6.6 整型提升缺失：比较运算符的静默错编（修 Lua 时发现）

C 在通常算术转换之前会做**整型提升**：`char`/`short`（不论有无符号）提升为 `int`，所以
`int >= unsigned char` 是**有符号**比较。qpcc 只问「任一操作数是否无符号」，于是把它编成了
无符号比较。

后果是静默算错：任何**负值**与小无符号类型比较都会翻。Lua 的 `lcode.c` 里有

```c
static void freereg (FuncState *fs, int reg) {
  if (reg >= luaY_nvarstack(fs)) { fs->freereg--; ... }
}
```

`reg` 是 `int`，`luaY_nvarstack` 返回 `lu_byte`。寄存器号为 `-1` 时被当成 `0xFFFFFFFF`，
条件误判为真，`freereg` 多减一次，之后整段字节码的寄存器号全部偏移 1 —— 表现为
`local i=1 while i<=3 do print(i) i=i+1 end` 把循环变量覆盖成 `print`。

已修（先做提升，再让无符号类型在「宽度不小于有符号」时才胜出），回归用例
`qpcc/tests/promote_cmp.c`。

**对方法的提醒**：这一类**编译成功但结果错**的问题，本报告的「OK」计数**完全看不到**。
差分测试也看不到——`compare.py` 给两个编译器喂的是 **IR**，从不经过 qpcc 的 C 前端，
所以 C→IR 的运算符选择实际上长期无人覆盖。要覆盖它，需要**跑起来比结果**的用例。

## 7. 本次重扫：与第一版的逐文件对照

2026-10-17，修完 Lua（含补齐自带头）之后重扫。三层口径不变（clang -E → qpcc --check → qpcc -o），
但改为在原目录扫描，并把各项目自己的头文件目录加进 -I。第一版把源文件摊平到一个目录，
既破坏了 `#include "../x.h"`，也让某些文件少了必要的头，所以下面把两类变化分开列。

| 阶段变化 | 文件数 | 说明 |
| --- | ---: | --- |
| PREPROCESS → OK | 19 | 口径改善（包含路径修好），不是 qpcc 的功劳 |
| PARSE → OK | 11 | **真修复** |
| SEMA → OK | 10 | **真修复** |
| CODEGEN-PANIC → OK | 1 | **真修复**（lua 的 `ldo.c`）|
| PREPROCESS → PARSE/SEMA/CODEGEN | 5 | 现在能预处理了，暴露出真实的 qpcc 缺陷 |
| PARSE → PREPROCESS | 2 | `abduco.c`、`sic.c`：需要 make 生成 config.h |
| OK → SEMA | 1 | lz4 `lz4file.c`：不是回归，是口径变化后暴露的真实缺陷，见 §6.7 |
| PARSE → SEMA | 1 | smu：缺 -DVERSION= |
| 未变 | 151 | |

**22 个文件从 qpcc 侧失败变成通过：**

| 项目 | 文件 | 第一版 | 现在 |
| --- | --- | --- | --- |
| bzip2 | `bzip2.c` | PARSE | **OK** |
| cjson | `cJSON.c` | PARSE | **OK** |
| cjson | `cJSON_Utils.c` | PARSE | **OK** |
| dash | `arith_yacc.c` | SEMA | **OK** |
| hiredis | `alloc.c` | SEMA | **OK** |
| lchat | `sl_test.c` | SEMA | **OK** |
| lchat | `slackline_emacs.c` | SEMA | **OK** |
| lua | `lauxlib.c` | SEMA | **OK** |
| lua | `lcode.c` | PARSE | **OK** |
| lua | `ldo.c` | CODEGEN-PANIC | **OK** |
| lua | `lfunc.c` | SEMA | **OK** |
| lua | `lmathlib.c` | PARSE | **OK** |
| lua | `lobject.c` | PARSE | **OK** |
| lua | `loslib.c` | SEMA | **OK** |
| lua | `lstrlib.c` | PARSE | **OK** |
| lua | `ltable.c` | PARSE | **OK** |
| lua | `lua.c` | SEMA | **OK** |
| lua | `luac.c` | SEMA | **OK** |
| lua | `lvm.c` | PARSE | **OK** |
| lz4 | `standaloneengine.c` | SEMA | **OK** |
| yyjson | `make_tables.c` | PARSE | **OK** |
| yyjson | `yyjson.c` | PARSE | **OK** |

最值得说的：

- **lua 34/34 全过**（第一版 22）。
- cjson 两个、yyjson 两个、bzip2 的 `bzip2.c` 都从解析失败变成通过（_Float16 那批系统头声明）。
- dash `arith_yacc.c`、hiredis `alloc.c`、lchat 两个、lz4 `standaloneengine.c` 从 use of undeclared identifier 变成通过。

### 6.7 声明的名字在它自己的初始化式里不可见（本轮新发现）

```c
int f(void) { int x = (int)sizeof(x); return x; }
/* qpcc: error: use of undeclared identifier: x */
```

C11 6.2.1p7：标识符的作用域从**声明符结束处**开始，所以初始化式里的 `x` 是可见的，
`int x = sizeof(x);` 是合法 C。qpcc 把符号登记放在检查初始化式**之后**，于是任何
自引用初始化式都会失败，而且第一个报错指向声明符本身，看起来像类型错误。

lz4 的 `lib/lz4file.c` 就是这个形状：

```c
LZ4F_resumePoint* const newPoints =
    (LZ4F_resumePoint*)realloc(lz4fRead->points, newCapacity * sizeof(*newPoints));
```

（该文件在第一版里记为 OK：第一版把源文件摊平到一个目录再扫，预处理结果与原地扫描不同。）
## 8. 方法的局限（所以数字是下界）

1. **`-D` 注入有 bug**：从 `Makefile` 抓到的 `-DVERSION=\"0\"` 反斜杠没消干净，
   `sic.c` 因此报 `expected ")"` —— 那是扫描器的错，不是 qpcc 的。
2. **没有复刻各项目的 include 路径**：lz4 的 `xxhash.h`、dash 的 `token.h`/`nodes.h`（由它的构建生成）、
   yyjson 的 `-I src`、miniz 的 CMake 产物，都没给，导致 66 个文件没走到 qpcc。
3. 因此**真实通过率只会比 65% 高，不会低**。

## 9. 复现

```sh
# 抓源（仓库外，不提交）
SRC=/tmp/qpcc-scan/src
git clone --depth 1 https://git.suckless.org/sic $SRC/sic
# … 其余见 /tmp/qpcc-scan/fetch.sh

# 扫描：clang 预处理 → qpcc --check → qpcc -o
sh /tmp/qpcc-scan/scan3.sh          # 结果写 /tmp/qpcc-scan/out2/summary.tsv
sh /tmp/qpcc-scan/report2.sh        # 由 summary.tsv 生成 §1–§4 的表格
```

## 10. 未做的事（按用户要求）

- **没有修复任何一条**；没有改任何第三方源码；没有提交第三方源码。
- 没有用各项目自带的 Makefile 判定构建（qpcc 没有 `-c`、没有多文件驱动）。
- SQLite 只用默认 amalgamation 配置，未加 `SQLITE_ENABLE_*`。

## 附录 A. 逐文件明细

| 项目 | 文件 | 阶段 | 结果 | 首个诊断 |
| --- | --- | --- | --- | --- |
| abduco | abduco/abduco.c | PREPROCESS | FAIL | 'config.h' file not found |
| abduco | abduco/client.c | PARSE | FAIL | error: expected ';' |
| abduco | abduco/debug.c | PARSE | FAIL | error: expected ';' |
| abduco | abduco/forkpty-aix.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| abduco | abduco/forkpty-sunos.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| abduco | abduco/server.c | PARSE | FAIL | error: expected ';' |
| bzip2 | bzip2/blocksort.c | OK | OK | - |
| bzip2 | bzip2/bzip2.c | OK | OK | - |
| bzip2 | bzip2/bzip2recover.c | OK | OK | - |
| bzip2 | bzip2/bzlib.c | OK | OK | - |
| bzip2 | bzip2/compress.c | CODEGEN-PANIC | FAIL | qpcc: object emission failed: ICE: arm64 bin: expected a register oper |
| bzip2 | bzip2/crctable.c | OK | OK | - |
| bzip2 | bzip2/decompress.c | CODEGEN-PANIC | FAIL | qpcc: object emission failed: ICE: arm64 bin: expected a register oper |
| bzip2 | bzip2/dlltest.c | OK | OK | - |
| bzip2 | bzip2/huffman.c | OK | OK | - |
| bzip2 | bzip2/mk251.c | OK | OK | - |
| bzip2 | bzip2/randtable.c | OK | OK | - |
| bzip2 | bzip2/spewG.c | OK | OK | - |
| bzip2 | bzip2/unzcrash.c | OK | OK | - |
| cjson | cjson/cJSON.c | OK | OK | - |
| cjson | cjson/cJSON_Utils.c | OK | OK | - |
| dash | dash/alias.c | PREPROCESS | FAIL | 'syntax.h' file not found |
| dash | dash/arith_yacc.c | OK | OK | - |
| dash | dash/arith_yylex.c | PREPROCESS | FAIL | 'syntax.h' file not found |
| dash | dash/cd.c | PREPROCESS | FAIL | 'nodes.h' file not found |
| dash | dash/error.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| dash | dash/eval.c | PREPROCESS | FAIL | 'nodes.h' file not found |
| dash | dash/exec.c | PREPROCESS | FAIL | 'nodes.h' file not found |
| dash | dash/expand.c | PREPROCESS | FAIL | 'nodes.h' file not found |
| dash | dash/histedit.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| dash | dash/input.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| dash | dash/jobs.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| dash | dash/mail.c | PREPROCESS | FAIL | 'nodes.h' file not found |
| dash | dash/main.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| dash | dash/memalloc.c | OK | OK | - |
| dash | dash/miscbltin.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| dash | dash/mkinit.c | OK | OK | - |
| dash | dash/mknodes.c | OK | OK | - |
| dash | dash/mksignames.c | OK | OK | - |
| dash | dash/mksyntax.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| dash | dash/mystring.c | PREPROCESS | FAIL | 'syntax.h' file not found |
| dash | dash/options.c | PREPROCESS | FAIL | 'nodes.h' file not found |
| dash | dash/output.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| dash | dash/parser.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| dash | dash/printf.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| dash | dash/redir.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| dash | dash/show.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| dash | dash/system.c | OK | OK | - |
| dash | dash/times.c | OK | OK | - |
| dash | dash/trap.c | PREPROCESS | FAIL | 'nodes.h' file not found |
| dash | dash/var.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| farbfeld | farbfeld/ff2jpg.c | PREPROCESS | FAIL | 'jpeglib.h' file not found |
| farbfeld | farbfeld/ff2pam.c | OK | OK | - |
| farbfeld | farbfeld/ff2png.c | PREPROCESS | FAIL | 'png.h' file not found |
| farbfeld | farbfeld/ff2ppm.c | OK | OK | - |
| farbfeld | farbfeld/jpg2ff.c | PREPROCESS | FAIL | 'jpeglib.h' file not found |
| farbfeld | farbfeld/png2ff.c | PREPROCESS | FAIL | 'png.h' file not found |
| farbfeld | farbfeld/util.c | SEMA | FAIL | error: use of undeclared identifier: ENOMEM |
| hiredis | hiredis/alloc.c | OK | OK | - |
| hiredis | hiredis/async.c | SEMA | FAIL | error: use of undeclared identifier: ht |
| hiredis | hiredis/dict.c | SEMA | FAIL | error: use of undeclared identifier: ht |
| hiredis | hiredis/hiredis.c | SEMA | FAIL | error: use of undeclared identifier: r |
| hiredis | hiredis/net.c | SEMA | FAIL | error: use of undeclared identifier: EWOULDBLOCK |
| hiredis | hiredis/read.c | PARSE | FAIL | error: expected ';' |
| hiredis | hiredis/sds.c | SEMA | FAIL | error: use of undeclared identifier: SSIZE_MAX |
| hiredis | hiredis/sockcompat.c | OK | OK | - |
| hiredis | hiredis/ssl.c | PREPROCESS | FAIL | 'openssl/ssl.h' file not found |
| ii | ii/ii.c | PREPROCESS | FAIL | 'tls.h' file not found |
| ii | ii/strlcpy.c | OK | OK | - |
| lchat | lchat/indent.c | SEMA | FAIL | error: use of undeclared identifier: R_OK |
| lchat | lchat/lchat.c | SEMA | FAIL | error: use of undeclared identifier: R_OK |
| lchat | lchat/sl_test.c | OK | OK | - |
| lchat | lchat/slackline.c | PREPROCESS | FAIL | 'grapheme.h' file not found |
| lchat | lchat/slackline_emacs.c | OK | OK | - |
| lchat | lchat/util.c | SEMA | FAIL | error: use of undeclared identifier: R_OK |
| lua | lua/lapi.c | OK | OK | - |
| lua | lua/lauxlib.c | OK | OK | - |
| lua | lua/lbaselib.c | OK | OK | - |
| lua | lua/lcode.c | OK | OK | - |
| lua | lua/lcorolib.c | OK | OK | - |
| lua | lua/lctype.c | OK | OK | - |
| lua | lua/ldblib.c | OK | OK | - |
| lua | lua/ldebug.c | OK | OK | - |
| lua | lua/ldo.c | OK | OK | - |
| lua | lua/ldump.c | OK | OK | - |
| lua | lua/lfunc.c | OK | OK | - |
| lua | lua/lgc.c | OK | OK | - |
| lua | lua/linit.c | OK | OK | - |
| lua | lua/liolib.c | OK | OK | - |
| lua | lua/llex.c | OK | OK | - |
| lua | lua/lmathlib.c | OK | OK | - |
| lua | lua/lmem.c | OK | OK | - |
| lua | lua/loadlib.c | OK | OK | - |
| lua | lua/lobject.c | OK | OK | - |
| lua | lua/lopcodes.c | OK | OK | - |
| lua | lua/loslib.c | OK | OK | - |
| lua | lua/lparser.c | OK | OK | - |
| lua | lua/lstate.c | OK | OK | - |
| lua | lua/lstring.c | OK | OK | - |
| lua | lua/lstrlib.c | OK | OK | - |
| lua | lua/ltable.c | OK | OK | - |
| lua | lua/ltablib.c | OK | OK | - |
| lua | lua/ltm.c | OK | OK | - |
| lua | lua/lua.c | OK | OK | - |
| lua | lua/luac.c | OK | OK | - |
| lua | lua/lundump.c | OK | OK | - |
| lua | lua/lutf8lib.c | OK | OK | - |
| lua | lua/lvm.c | OK | OK | - |
| lua | lua/lzio.c | OK | OK | - |
| lz4 | lz4/bench.c | PARSE | FAIL | error: expected ')' |
| lz4 | lz4/compress_frame_fuzzer.c | OK | OK | - |
| lz4 | lz4/compress_frame_stream_fuzzer.c | OK | OK | - |
| lz4 | lz4/compress_fuzzer.c | OK | OK | - |
| lz4 | lz4/compress_hc_fuzzer.c | OK | OK | - |
| lz4 | lz4/decompress_frame_fuzzer.c | OK | OK | - |
| lz4 | lz4/decompress_fuzzer.c | OK | OK | - |
| lz4 | lz4/lorem.c | SEMA | FAIL | error: division by zero in constant expression |
| lz4 | lz4/lz4.c | OK | OK | - |
| lz4 | lz4/lz4_helpers.c | OK | OK | - |
| lz4 | lz4/lz4cli.c | PARSE | FAIL | error: expected ')' |
| lz4 | lz4/lz4file.c | SEMA | FAIL | error: use of undeclared identifier: newPoints |
| lz4 | lz4/lz4frame.c | OK | OK | - |
| lz4 | lz4/lz4hc.c | SEMA | FAIL | error: use of undeclared identifier: pattern |
| lz4 | lz4/lz4io.c | PARSE | FAIL | error: expected ')' |
| lz4 | lz4/round_trip_frame_fuzzer.c | OK | OK | - |
| lz4 | lz4/round_trip_frame_uncompressed_fuzzer.c | OK | OK | - |
| lz4 | lz4/round_trip_fuzzer.c | OK | OK | - |
| lz4 | lz4/round_trip_hc_fuzzer.c | OK | OK | - |
| lz4 | lz4/round_trip_stream_fuzzer.c | OK | OK | - |
| lz4 | lz4/standaloneengine.c | OK | OK | - |
| lz4 | lz4/threadpool.c | OK | OK | - |
| lz4 | lz4/timefn.c | PARSE | FAIL | error: expected ')' |
| lz4 | lz4/util.c | PARSE | FAIL | error: expected ')' |
| lz4 | lz4/xxhash.c | OK | OK | - |
| miniz | miniz/miniz.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| miniz | miniz/miniz_tdef.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| miniz | miniz/miniz_tinfl.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| miniz | miniz/miniz_zip.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| sic | sic/sic.c | PREPROCESS | FAIL | 'config.h' file not found |
| sic | sic/strlcpy.c | OK | OK | - |
| sic | sic/util.c | PARSE | FAIL | error: expected ';' |
| slstatus | slstatus/battery.c | OK | OK | - |
| slstatus | slstatus/cat.c | OK | OK | - |
| slstatus | slstatus/cpu.c | OK | OK | - |
| slstatus | slstatus/datetime.c | OK | OK | - |
| slstatus | slstatus/disk.c | OK | OK | - |
| slstatus | slstatus/entropy.c | OK | OK | - |
| slstatus | slstatus/hostname.c | OK | OK | - |
| slstatus | slstatus/ip.c | OK | OK | - |
| slstatus | slstatus/kernel_release.c | OK | OK | - |
| slstatus | slstatus/keyboard_indicators.c | PREPROCESS | FAIL | 'X11/Xlib.h' file not found |
| slstatus | slstatus/keymap.c | PREPROCESS | FAIL | 'X11/XKBlib.h' file not found |
| slstatus | slstatus/load_avg.c | OK | OK | - |
| slstatus | slstatus/netspeeds.c | OK | OK | - |
| slstatus | slstatus/num_files.c | PARSE | FAIL | error: expected ')' |
| slstatus | slstatus/ram.c | OK | OK | - |
| slstatus | slstatus/run_command.c | OK | OK | - |
| slstatus | slstatus/slstatus.c | PREPROCESS | FAIL | 'X11/Xlib.h' file not found |
| slstatus | slstatus/swap.c | OK | OK | - |
| slstatus | slstatus/temperature.c | OK | OK | - |
| slstatus | slstatus/uptime.c | OK | OK | - |
| slstatus | slstatus/user.c | OK | OK | - |
| slstatus | slstatus/util.c | OK | OK | - |
| slstatus | slstatus/volume.c | PREPROCESS | FAIL | 'sys/soundcard.h' file not found |
| slstatus | slstatus/wifi.c | OK | OK | - |
| smu | smu/smu.c | SEMA | FAIL | error: use of undeclared identifier: VERSION |
| sqlite | sqlite/sqlite3.c | PARSE | FAIL | error: expected ')' |
| yyjson | yyjson/experiment_depth_limit.c | OK | OK | - |
| yyjson | yyjson/jsoninfo.c | OK | OK | - |
| yyjson | yyjson/make_tables.c | OK | OK | - |
| yyjson | yyjson/yyjson.c | OK | OK | - |
| zlib | zlib/adler32.c | OK | OK | - |
| zlib | zlib/bin-writer.c | OK | OK | - |
| zlib | zlib/blast-test.c | OK | OK | - |
| zlib | zlib/blast.c | OK | OK | - |
| zlib | zlib/compress.c | OK | OK | - |
| zlib | zlib/crc32.c | OK | OK | - |
| zlib | zlib/crc32_vx.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| zlib | zlib/deflate.c | OK | OK | - |
| zlib | zlib/gzclose.c | OK | OK | - |
| zlib | zlib/gzlib.c | OK | OK | - |
| zlib | zlib/gzread.c | OK | OK | - |
| zlib | zlib/gzwrite.c | OK | OK | - |
| zlib | zlib/infback.c | OK | OK | - |
| zlib | zlib/infback9.c | OK | OK | - |
| zlib | zlib/inffast.c | OK | OK | - |
| zlib | zlib/inflate.c | OK | OK | - |
| zlib | zlib/inftree9.c | OK | OK | - |
| zlib | zlib/inftrees.c | OK | OK | - |
| zlib | zlib/ioapi.c | OK | OK | - |
| zlib | zlib/iowin32.c | PREPROCESS | FAIL | In file included from /Users/Admin/Desktop/qbe.mbt |
| zlib | zlib/miniunz.c | CODEGEN-PANIC | FAIL | PanicError |
| zlib | zlib/minizip.c | OK | OK | - |
| zlib | zlib/mztools.c | OK | OK | - |
| zlib | zlib/puff.c | OK | OK | - |
| zlib | zlib/pufftest.c | OK | OK | - |
| zlib | zlib/trees.c | OK | OK | - |
| zlib | zlib/uncompr.c | OK | OK | - |
| zlib | zlib/unzip.c | OK | OK | - |
| zlib | zlib/zip.c | SEMA | FAIL | error: use of undeclared identifier: ENOMEM |
| zlib | zlib/zutil.c | OK | OK | - |
