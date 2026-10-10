# qpcc 外部 C 项目编译扫描报告

> **本报告只诊断，未修复。** 数据采集于 2026-10-11，qpcc v0.37.3。
> 原始日志在 `/tmp/qpcc-scan/out2/`（未提交），复现命令见文末。

## 0. 一句话结论

17 个真实 C 项目、201 个源文件：**88 个完整通过（44%）**。
另有 66 个文件**根本没走到 qpcc**（缺第三方或平台依赖，属环境问题）。
扣掉它们，**到达 qpcc 的 135 个文件里 88 个通过 —— 65%**。

而失败原因高度集中：**两个原因解释了大半。**

| # | 阻断源 | 命中文件 | 性质 |
| --- | --- | ---: | --- |
| 1 | qpcc 自带头**遮蔽**系统头，缺 9 个标准宏 | 11+ | **qpcc 的锅，最易修** |
| 2 | 解析失败里 73% 是 macOS 系统头的 **Apple 扩展**（`_Float16`、Blocks `^{}`）| 17 / 23 | 平台相关 |
| 3 | 后端 ICE（bzip2 ×2、lua ×1）| 3 | **qpcc 真 bug** |
| 4 | `sizeof("字面量")` 静默给错值 | — | **qpcc 真 bug** |
| 5 | 诊断输出走 stdout，`2>/dev/null` 会丢掉全部信息 | — | qpcc 的锅 |

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
| abduco | 6 | 0 | 4 | 0 | 2 |
| bzip2 | 13 | 10 | 1 | 2 | 0 |
| cjson | 2 | 0 | 2 | 0 | 0 |
| dash | 30 | 5 | 1 | 0 | 24 |
| farbfeld | 7 | 2 | 1 | 0 | 4 |
| hiredis | 9 | 1 | 7 | 0 | 1 |
| ii | 2 | 1 | 0 | 0 | 1 |
| lchat | 6 | 0 | 5 | 0 | 1 |
| lua | 34 | 22 | 11 | 1 | 0 |
| lz4 | 25 | 5 | 5 | 0 | 15 |
| miniz | 4 | 0 | 0 | 0 | 4 |
| sic | 3 | 1 | 2 | 0 | 0 |
| slstatus | 24 | 19 | 1 | 0 | 4 |
| smu | 1 | 0 | 1 | 0 | 0 |
| sqlite | 1 | 0 | 1 | 0 | 0 |
| yyjson | 4 | 0 | 2 | 0 | 2 |
| zlib | 30 | 22 | 0 | 0 | 8 |

## 3. 阶段分布

| 阶段 | 文件数 | 占全部 201 |
| --- | ---: | ---: |
| OK | 88 | 44% |
| PREPROCESS | 66 | 33% |
| PARSE | 23 | 11% |
| SEMA | 21 | 10% |
| CODEGEN-PANIC | 3 | 1% |

## 4. 诊断签名排名（跨项目计数，只统计到达 qpcc 的文件）

| 诊断 | 文件数 | 项目数 |
| --- | ---: | ---: |
| expected ';' | 15 | 7 |
| expected ')' | 8 | 6 |
| use of undeclared identifier: SIZE_MAX | 7 | 2 |
| use of undeclared identifier: EXIT_FAILURE | 3 | 2 |
| use of undeclared identifier: EXIT_SUCCESS | 2 | 1 |
| use of undeclared identifier: BUFSIZ | 2 | 2 |
| use of undeclared identifier: pattern | 1 | 1 |
| use of undeclared identifier: USHRT_MAX | 1 | 1 |
| use of undeclared identifier: STDOUT_FILENO | 1 | 1 |
| use of undeclared identifier: SEEK_END | 1 | 1 |
| use of undeclared identifier: L_tmpnam | 1 | 1 |
| use of undeclared identifier: INTMAX_MIN | 1 | 1 |
| qpcc: object emission failed: ld.8698 violates ssa invariant | 1 | 1 |
| qpcc: object emission failed: ICE: arm64 bin: unhandled jump | 1 | 1 |
| qpcc: object emission failed: ICE: arm64 bin: expected a register operand for mul | 1 | 1 |
| division by zero in constant expression | 1 | 1 |

## 5. 未到达 qpcc 的原因（缺依赖）

| 缺失的头 | 文件数 |
| --- | ---: |
| 'xxhash.h' | 13 |
| 'token.h' | 9 |
| 'nodes.h' | 9 |
| 'syntax.h' | 4 |
| 'miniz_export.h' | 4 |
| 'yyjson.h' | 2 |
| 'stropts.h' | 2 |
| 'png.h' | 2 |
| 'jpeglib.h' | 2 |
| 'X11/Xlib.h' | 2 |
| 'windows.h' | 1 |
| 'tls.h' | 1 |
| 'system.h' | 1 |
| 'sys/soundcard.h' | 1 |
| 'sys/auxv.h' | 1 |
| 'parser.h' | 1 |
| 'openssl/ssl.h' | 1 |
| 'lz4hc.h' | 1 |

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

## 7. 方法的局限（所以数字是下界）

1. **`-D` 注入有 bug**：从 `Makefile` 抓到的 `-DVERSION=\"0\"` 反斜杠没消干净，
   `sic.c` 因此报 `expected ")"` —— 那是扫描器的错，不是 qpcc 的。
2. **没有复刻各项目的 include 路径**：lz4 的 `xxhash.h`、dash 的 `token.h`/`nodes.h`（由它的构建生成）、
   yyjson 的 `-I src`、miniz 的 CMake 产物，都没给，导致 66 个文件没走到 qpcc。
3. 因此**真实通过率只会比 65% 高，不会低**。

## 8. 复现

```sh
# 抓源（仓库外，不提交）
SRC=/tmp/qpcc-scan/src
git clone --depth 1 https://git.suckless.org/sic $SRC/sic
# … 其余见 /tmp/qpcc-scan/fetch.sh

# 扫描：clang 预处理 → qpcc --check → qpcc -o
sh /tmp/qpcc-scan/scan3.sh          # 结果写 /tmp/qpcc-scan/out2/summary.tsv
sh /tmp/qpcc-scan/report2.sh        # 由 summary.tsv 生成 §1–§4 的表格
```

## 9. 未做的事（按用户要求）

- **没有修复任何一条**；没有改任何第三方源码；没有提交第三方源码。
- 没有用各项目自带的 Makefile 判定构建（qpcc 没有 `-c`、没有多文件驱动）。
- SQLite 只用默认 amalgamation 配置，未加 `SQLITE_ENABLE_*`。

## 附录 A. 逐文件明细

| 项目 | 文件 | 阶段 | 结果 | 首个诊断 |
| --- | --- | --- | --- | --- |
| abduco | abduco/abduco.c | PARSE | FAIL | expected ')' |
| abduco | abduco/client.c | PARSE | FAIL | expected ';' |
| abduco | abduco/debug.c | PARSE | FAIL | expected ')' |
| abduco | abduco/forkpty-aix.c | PREPROCESS | FAIL | 'stropts.h' file not found |
| abduco | abduco/forkpty-sunos.c | PREPROCESS | FAIL | 'stropts.h' file not found |
| abduco | abduco/server.c | PARSE | FAIL | expected ';' |
| bzip2 | bzip2/blocksort.c | OK | OK | - |
| bzip2 | bzip2/bzip2.c | PARSE | FAIL | expected ';' |
| bzip2 | bzip2/bzip2recover.c | OK | OK | - |
| bzip2 | bzip2/bzlib.c | OK | OK | - |
| bzip2 | bzip2/compress.c | CODEGEN-PANIC | FAIL | qpcc: object emission failed: ICE: arm64 bin: expected a register operand for mul |
| bzip2 | bzip2/crctable.c | OK | OK | - |
| bzip2 | bzip2/decompress.c | CODEGEN-PANIC | FAIL | qpcc: object emission failed: ld.8698 violates ssa invariant |
| bzip2 | bzip2/dlltest.c | OK | OK | - |
| bzip2 | bzip2/huffman.c | OK | OK | - |
| bzip2 | bzip2/mk251.c | OK | OK | - |
| bzip2 | bzip2/randtable.c | OK | OK | - |
| bzip2 | bzip2/spewG.c | OK | OK | - |
| bzip2 | bzip2/unzcrash.c | OK | OK | - |
| cjson | cjson/cJSON.c | PARSE | FAIL | expected ';' |
| cjson | cjson/cJSON_Utils.c | PARSE | FAIL | expected ';' |
| dash | dash/src/alias.c | PREPROCESS | FAIL | 'syntax.h' file not found |
| dash | dash/src/arith_yacc.c | SEMA | FAIL | use of undeclared identifier: INTMAX_MIN |
| dash | dash/src/arith_yylex.c | PREPROCESS | FAIL | 'syntax.h' file not found |
| dash | dash/src/bltin/printf.c | PREPROCESS | FAIL | 'parser.h' file not found |
| dash | dash/src/bltin/times.c | PREPROCESS | FAIL | 'system.h' file not found |
| dash | dash/src/cd.c | PREPROCESS | FAIL | 'nodes.h' file not found |
| dash | dash/src/error.c | PREPROCESS | FAIL | 'token.h' file not found |
| dash | dash/src/eval.c | PREPROCESS | FAIL | 'nodes.h' file not found |
| dash | dash/src/exec.c | PREPROCESS | FAIL | 'nodes.h' file not found |
| dash | dash/src/expand.c | PREPROCESS | FAIL | 'nodes.h' file not found |
| dash | dash/src/histedit.c | PREPROCESS | FAIL | 'token.h' file not found |
| dash | dash/src/input.c | PREPROCESS | FAIL | 'token.h' file not found |
| dash | dash/src/jobs.c | PREPROCESS | FAIL | 'token.h' file not found |
| dash | dash/src/mail.c | PREPROCESS | FAIL | 'nodes.h' file not found |
| dash | dash/src/main.c | PREPROCESS | FAIL | 'token.h' file not found |
| dash | dash/src/memalloc.c | OK | OK | - |
| dash | dash/src/miscbltin.c | PREPROCESS | FAIL | 'token.h' file not found |
| dash | dash/src/mkinit.c | OK | OK | - |
| dash | dash/src/mknodes.c | OK | OK | - |
| dash | dash/src/mksignames.c | OK | OK | - |
| dash | dash/src/mksyntax.c | PREPROCESS | FAIL | 'token.h' file not found |
| dash | dash/src/mystring.c | PREPROCESS | FAIL | 'syntax.h' file not found |
| dash | dash/src/options.c | PREPROCESS | FAIL | 'nodes.h' file not found |
| dash | dash/src/output.c | PREPROCESS | FAIL | 'syntax.h' file not found |
| dash | dash/src/parser.c | PREPROCESS | FAIL | 'token.h' file not found |
| dash | dash/src/redir.c | PREPROCESS | FAIL | 'nodes.h' file not found |
| dash | dash/src/show.c | PREPROCESS | FAIL | 'token.h' file not found |
| dash | dash/src/system.c | OK | OK | - |
| dash | dash/src/trap.c | PREPROCESS | FAIL | 'nodes.h' file not found |
| dash | dash/src/var.c | PREPROCESS | FAIL | 'nodes.h' file not found |
| farbfeld | farbfeld/ff2jpg.c | PREPROCESS | FAIL | 'jpeglib.h' file not found |
| farbfeld | farbfeld/ff2pam.c | OK | OK | - |
| farbfeld | farbfeld/ff2png.c | PREPROCESS | FAIL | 'png.h' file not found |
| farbfeld | farbfeld/ff2ppm.c | OK | OK | - |
| farbfeld | farbfeld/jpg2ff.c | PREPROCESS | FAIL | 'jpeglib.h' file not found |
| farbfeld | farbfeld/png2ff.c | PREPROCESS | FAIL | 'png.h' file not found |
| farbfeld | farbfeld/util.c | SEMA | FAIL | use of undeclared identifier: SIZE_MAX |
| hiredis | hiredis/alloc.c | SEMA | FAIL | use of undeclared identifier: SIZE_MAX |
| hiredis | hiredis/async.c | SEMA | FAIL | use of undeclared identifier: SIZE_MAX |
| hiredis | hiredis/dict.c | SEMA | FAIL | use of undeclared identifier: SIZE_MAX |
| hiredis | hiredis/hiredis.c | SEMA | FAIL | use of undeclared identifier: SIZE_MAX |
| hiredis | hiredis/net.c | SEMA | FAIL | use of undeclared identifier: SIZE_MAX |
| hiredis | hiredis/read.c | PARSE | FAIL | expected ';' |
| hiredis | hiredis/sds.c | SEMA | FAIL | use of undeclared identifier: SIZE_MAX |
| hiredis | hiredis/sockcompat.c | OK | OK | - |
| hiredis | hiredis/ssl.c | PREPROCESS | FAIL | 'openssl/ssl.h' file not found |
| ii | ii/ii.c | PREPROCESS | FAIL | 'tls.h' file not found |
| ii | ii/strlcpy.c | OK | OK | - |
| lchat | lchat/filter/indent.c | SEMA | FAIL | use of undeclared identifier: BUFSIZ |
| lchat | lchat/lchat.c | SEMA | FAIL | use of undeclared identifier: STDOUT_FILENO |
| lchat | lchat/sl_test.c | SEMA | FAIL | use of undeclared identifier: EXIT_SUCCESS |
| lchat | lchat/slackline.c | PREPROCESS | FAIL | 'grapheme.h' file not found |
| lchat | lchat/slackline_emacs.c | SEMA | FAIL | use of undeclared identifier: EXIT_SUCCESS |
| lchat | lchat/util.c | SEMA | FAIL | use of undeclared identifier: EXIT_FAILURE |
| lua | lua/src/lapi.c | OK | OK | - |
| lua | lua/src/lauxlib.c | SEMA | FAIL | use of undeclared identifier: BUFSIZ |
| lua | lua/src/lbaselib.c | OK | OK | - |
| lua | lua/src/lcode.c | PARSE | FAIL | expected ';' |
| lua | lua/src/lcorolib.c | OK | OK | - |
| lua | lua/src/lctype.c | OK | OK | - |
| lua | lua/src/ldblib.c | OK | OK | - |
| lua | lua/src/ldebug.c | OK | OK | - |
| lua | lua/src/ldo.c | CODEGEN-PANIC | FAIL | qpcc: object emission failed: ICE: arm64 bin: unhandled jump |
| lua | lua/src/ldump.c | OK | OK | - |
| lua | lua/src/lfunc.c | SEMA | FAIL | use of undeclared identifier: USHRT_MAX |
| lua | lua/src/lgc.c | OK | OK | - |
| lua | lua/src/linit.c | OK | OK | - |
| lua | lua/src/liolib.c | OK | OK | - |
| lua | lua/src/llex.c | OK | OK | - |
| lua | lua/src/lmathlib.c | PARSE | FAIL | expected ';' |
| lua | lua/src/lmem.c | OK | OK | - |
| lua | lua/src/loadlib.c | OK | OK | - |
| lua | lua/src/lobject.c | PARSE | FAIL | expected ';' |
| lua | lua/src/lopcodes.c | OK | OK | - |
| lua | lua/src/loslib.c | SEMA | FAIL | use of undeclared identifier: L_tmpnam |
| lua | lua/src/lparser.c | OK | OK | - |
| lua | lua/src/lstate.c | OK | OK | - |
| lua | lua/src/lstring.c | OK | OK | - |
| lua | lua/src/lstrlib.c | PARSE | FAIL | expected ';' |
| lua | lua/src/ltable.c | PARSE | FAIL | expected ';' |
| lua | lua/src/ltablib.c | OK | OK | - |
| lua | lua/src/ltm.c | OK | OK | - |
| lua | lua/src/lua.c | SEMA | FAIL | use of undeclared identifier: EXIT_FAILURE |
| lua | lua/src/luac.c | SEMA | FAIL | use of undeclared identifier: EXIT_FAILURE |
| lua | lua/src/lundump.c | OK | OK | - |
| lua | lua/src/lutf8lib.c | OK | OK | - |
| lua | lua/src/lvm.c | PARSE | FAIL | expected ';' |
| lua | lua/src/lzio.c | OK | OK | - |
| lz4 | lz4/lib/lz4.c | OK | OK | - |
| lz4 | lz4/lib/lz4file.c | OK | OK | - |
| lz4 | lz4/lib/lz4frame.c | OK | OK | - |
| lz4 | lz4/lib/lz4hc.c | SEMA | FAIL | use of undeclared identifier: pattern |
| lz4 | lz4/lib/xxhash.c | OK | OK | - |
| lz4 | lz4/ossfuzz/compress_frame_fuzzer.c | PREPROCESS | FAIL | 'xxhash.h' file not found |
| lz4 | lz4/ossfuzz/compress_frame_stream_fuzzer.c | PREPROCESS | FAIL | 'xxhash.h' file not found |
| lz4 | lz4/ossfuzz/compress_fuzzer.c | PREPROCESS | FAIL | 'xxhash.h' file not found |
| lz4 | lz4/ossfuzz/compress_hc_fuzzer.c | PREPROCESS | FAIL | 'xxhash.h' file not found |
| lz4 | lz4/ossfuzz/decompress_frame_fuzzer.c | PREPROCESS | FAIL | 'xxhash.h' file not found |
| lz4 | lz4/ossfuzz/decompress_fuzzer.c | PREPROCESS | FAIL | 'xxhash.h' file not found |
| lz4 | lz4/ossfuzz/lz4_helpers.c | PREPROCESS | FAIL | 'xxhash.h' file not found |
| lz4 | lz4/ossfuzz/round_trip_frame_fuzzer.c | PREPROCESS | FAIL | 'xxhash.h' file not found |
| lz4 | lz4/ossfuzz/round_trip_frame_uncompressed_fuzzer.c | PREPROCESS | FAIL | 'xxhash.h' file not found |
| lz4 | lz4/ossfuzz/round_trip_fuzzer.c | PREPROCESS | FAIL | 'xxhash.h' file not found |
| lz4 | lz4/ossfuzz/round_trip_hc_fuzzer.c | PREPROCESS | FAIL | 'xxhash.h' file not found |
| lz4 | lz4/ossfuzz/round_trip_stream_fuzzer.c | PREPROCESS | FAIL | 'xxhash.h' file not found |
| lz4 | lz4/ossfuzz/standaloneengine.c | SEMA | FAIL | use of undeclared identifier: SEEK_END |
| lz4 | lz4/programs/bench.c | PREPROCESS | FAIL | 'xxhash.h' file not found |
| lz4 | lz4/programs/lorem.c | SEMA | FAIL | division by zero in constant expression |
| lz4 | lz4/programs/lz4cli.c | PREPROCESS | FAIL | 'lz4hc.h' file not found |
| lz4 | lz4/programs/lz4io.c | PREPROCESS | FAIL | 'lz4.h' file not found |
| lz4 | lz4/programs/threadpool.c | OK | OK | - |
| lz4 | lz4/programs/timefn.c | PARSE | FAIL | expected ')' |
| lz4 | lz4/programs/util.c | PARSE | FAIL | expected ')' |
| miniz | miniz/miniz.c | PREPROCESS | FAIL | 'miniz_export.h' file not found |
| miniz | miniz/miniz_tdef.c | PREPROCESS | FAIL | 'miniz_export.h' file not found |
| miniz | miniz/miniz_tinfl.c | PREPROCESS | FAIL | 'miniz_export.h' file not found |
| miniz | miniz/miniz_zip.c | PREPROCESS | FAIL | 'miniz_export.h' file not found |
| sic | sic/sic.c | PARSE | FAIL | expected ')' |
| sic | sic/strlcpy.c | OK | OK | - |
| sic | sic/util.c | PARSE | FAIL | expected ';' |
| slstatus | slstatus/components/battery.c | OK | OK | - |
| slstatus | slstatus/components/cat.c | OK | OK | - |
| slstatus | slstatus/components/cpu.c | OK | OK | - |
| slstatus | slstatus/components/datetime.c | OK | OK | - |
| slstatus | slstatus/components/disk.c | OK | OK | - |
| slstatus | slstatus/components/entropy.c | OK | OK | - |
| slstatus | slstatus/components/hostname.c | OK | OK | - |
| slstatus | slstatus/components/ip.c | OK | OK | - |
| slstatus | slstatus/components/kernel_release.c | OK | OK | - |
| slstatus | slstatus/components/keyboard_indicators.c | PREPROCESS | FAIL | 'X11/Xlib.h' file not found |
| slstatus | slstatus/components/keymap.c | PREPROCESS | FAIL | 'X11/XKBlib.h' file not found |
| slstatus | slstatus/components/load_avg.c | OK | OK | - |
| slstatus | slstatus/components/netspeeds.c | OK | OK | - |
| slstatus | slstatus/components/num_files.c | PARSE | FAIL | expected ')' |
| slstatus | slstatus/components/ram.c | OK | OK | - |
| slstatus | slstatus/components/run_command.c | OK | OK | - |
| slstatus | slstatus/components/swap.c | OK | OK | - |
| slstatus | slstatus/components/temperature.c | OK | OK | - |
| slstatus | slstatus/components/uptime.c | OK | OK | - |
| slstatus | slstatus/components/user.c | OK | OK | - |
| slstatus | slstatus/components/volume.c | PREPROCESS | FAIL | 'sys/soundcard.h' file not found |
| slstatus | slstatus/components/wifi.c | OK | OK | - |
| slstatus | slstatus/slstatus.c | PREPROCESS | FAIL | 'X11/Xlib.h' file not found |
| slstatus | slstatus/util.c | OK | OK | - |
| smu | smu/smu.c | PARSE | FAIL | expected ')' |
| sqlite | sqlite/sqlite3.c | PARSE | FAIL | expected ')' |
| yyjson | yyjson/misc/experiment_depth_limit.c | PREPROCESS | FAIL | 'yyjson.h' file not found |
| yyjson | yyjson/misc/jsoninfo.c | PREPROCESS | FAIL | 'yyjson.h' file not found |
| yyjson | yyjson/misc/make_tables.c | PARSE | FAIL | expected ';' |
| yyjson | yyjson/src/yyjson.c | PARSE | FAIL | expected ';' |
| zlib | zlib/adler32.c | OK | OK | - |
| zlib | zlib/compress.c | OK | OK | - |
| zlib | zlib/contrib/blast/blast-test.c | OK | OK | - |
| zlib | zlib/contrib/blast/blast.c | OK | OK | - |
| zlib | zlib/contrib/crc32vx/crc32_vx.c | PREPROCESS | FAIL | 'sys/auxv.h' file not found |
| zlib | zlib/contrib/infback9/infback9.c | OK | OK | - |
| zlib | zlib/contrib/infback9/inftree9.c | OK | OK | - |
| zlib | zlib/contrib/minizip/ioapi.c | PREPROCESS | FAIL | In file included from /tmp/qpcc-scan/src/zlib/contrib/minizip/ioapi.c:29: |
| zlib | zlib/contrib/minizip/iowin32.c | PREPROCESS | FAIL | 'windows.h' file not found |
| zlib | zlib/contrib/minizip/miniunz.c | PREPROCESS | FAIL | In file included from /tmp/qpcc-scan/src/zlib/contrib/minizip/miniunz.c:61: |
| zlib | zlib/contrib/minizip/minizip.c | PREPROCESS | FAIL | In file included from /tmp/qpcc-scan/src/zlib/contrib/minizip/minizip.c:63: |
| zlib | zlib/contrib/minizip/mztools.c | PREPROCESS | FAIL | In file included from /tmp/qpcc-scan/src/zlib/contrib/minizip/mztools.c:15: |
| zlib | zlib/contrib/minizip/unzip.c | PREPROCESS | FAIL | In file included from /tmp/qpcc-scan/src/zlib/contrib/minizip/unzip.c:74: |
| zlib | zlib/contrib/minizip/zip.c | PREPROCESS | FAIL | In file included from /tmp/qpcc-scan/src/zlib/contrib/minizip/zip.c:35: |
| zlib | zlib/contrib/puff/bin-writer.c | OK | OK | - |
| zlib | zlib/contrib/puff/puff.c | OK | OK | - |
| zlib | zlib/contrib/puff/pufftest.c | OK | OK | - |
| zlib | zlib/crc32.c | OK | OK | - |
| zlib | zlib/deflate.c | OK | OK | - |
| zlib | zlib/gzclose.c | OK | OK | - |
| zlib | zlib/gzlib.c | OK | OK | - |
| zlib | zlib/gzread.c | OK | OK | - |
| zlib | zlib/gzwrite.c | OK | OK | - |
| zlib | zlib/infback.c | OK | OK | - |
| zlib | zlib/inffast.c | OK | OK | - |
| zlib | zlib/inflate.c | OK | OK | - |
| zlib | zlib/inftrees.c | OK | OK | - |
| zlib | zlib/trees.c | OK | OK | - |
| zlib | zlib/uncompr.c | OK | OK | - |
| zlib | zlib/zutil.c | OK | OK | - |
