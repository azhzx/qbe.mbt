# 用 QPCC 自举 QBE:踩过的坑

这份文档记录一件事:**用本仓库的 QPCC 去编译 `vendor/qbe`,再让编译出来的 `qbe` 去编译 QBE 自己的测试语料**。
这条路走通了,但它几乎把 QPCC 里所有"平时看不出来"的错误都逼了出来。
把这些坑写下来,是为了让下一个人少走弯路——**其中一半的坑是工具链和判据的坑,不是编译器的坑,但它们一样会让你得出错误结论。**

## 0. 先立规矩:自举验收怎么做

```sh
sh examples/qpcc-selfhost/build-qbe-with-qpcc.sh          # 完整:编译 + 链接 + 对比 76 个用例
sh examples/qpcc-selfhost/build-qbe-with-qpcc-no-test.sh  # 只编译链接,快
```

产物固定在仓库根的 `.qpcc_build/`(已进 `.gitignore`)。

**判据有两条,不要混用:**

| 判据 | 含义 | 用途 |
|---|---|---|
| **逐字节一致** | 自举 qbe 和 clang 建的参考 qbe 输出完全相同 | 严格,但会把"合法的次优代码"也算成失败 |
| **语义正确** | 两边输出的汇编各自汇编+链接+运行,退出码/stdout 相同 | 这才是"对不对"的判据 |

经验:**先看语义,再谈逐字节。** 一个多出来的 `movl` 不是 bug,一个错的跳转才是。

---

## 1. QPCC 的坑

### 1.1 `typedef` 会丢掉自己的符号性(commit `3f36ffc`)

**现象**:自举 qbe 对所有浮点类参数报 `missing first operand in par`。

**根因**:`declspec_to_type` 处理 `uint x`(`uint` = `typedef unsigned int`)时,发现声明里没写 `unsigned`,
就用 `CInt(!uns)` 重新推导,把 `uint` 变成了**有符号**。

后果在 QBE 里被放大:

```c
struct Ins { uint op:30; uint cls:2; };   /* cls 在 32 位字的最高两位 */
```

`cls` 有符号时用**算术右移**读取,`cls=2` 读成 **-2**,数组下标越界。

**教训**:typedef 的符号性/宽度必须**继承**,不能被声明说明符二次覆盖。位域读取选 `Shr` 还是 `Sar` 取决于底层类型,
所以"符号性丢失"这一类 bug 的症状通常是**完全无关的地方**(浮点参数、数组越界)。

### 1.2 变参实参没有做默认实参提升(commit `baade27`)

**现象**:自举 qbe 在**任何条件分支**上段错误。

**根因**:`check_call` 对所有实参都按原类型传递,没有做数组退化 / `float`→`double`。

触发点:

```c
fprintf(f, "%sbb%d\n", T.asloc, id0 + b->id);
```

`T.asloc` 是 `struct Target` 里的 `char asloc[4]`,被**按值拷贝**而不是传地址,于是 `.L` 这 2 个字节被当成指针。

**教训**:C 的默认实参提升是**语义要求**,不是优化。漏了它,`char[N]` 成员会静默变成"传内容"。

### 1.3 文件作用域的数组复合字面量没有静态对象(commit `30ae032`)

**现象**:自举 qbe 在 `runmatch` 里对 NULL 解引用。

**根因**:

```c
static uchar *matcher[] = {
	[Pob] = (uchar[]){ 1, 3, 0, 3, 1, 0 },
};
```

数组复合字面量在**文件作用域**有静态存储期,`ptr_reloc` 却没有为它生成重定位 → 指针是 NULL。

**教训**:复合字面量在不同作用域的存储期不同;全局初始化器里出现的复合字面量必须有自己的匿名对象。

### 1.4 switch body 里嵌在 `if` 中的 `case` 被整个丢掉(commit `6bdaae1`)

**现象**:自举 qbe 无法解析 `vastart` / `blit`,报 `label, instruction or jump expected`。

**根因**:`check_switch` 只扫描 switch body 的**顶层项**。QBE 的指令解析器是 Duff device:

```c
switch (t) {
case Ttmp: ... break;
default:
	if (isstore(t)) {
	case Tblit:
	case Tcall:
	case Ovastart:          /* ← 嵌在 if 里 */
		r = R; k = Kw; op = t;
		break;
	}
	err("label, instruction or jump expected");
}
```

这些 `case` 根本没进 case 列表,自然永远匹配不到。

**教训**:`case` 是**语句列表里的标签**,可以出现在任何嵌套深度。实现 switch 时要么按标签建块,
要么老老实实把整棵语句树扫一遍。

### 1.5 `case X:` 不会穿透进 `default:`(commit `ecfefa9`)

**现象**:自举 qbe 的 `-h` 什么都不打印。

**根因**:QPCC 把 `default` 当成"所有 case 之后的兜底",于是

```c
switch (c) {
case 'd': ... break;
case 'h':
default:                    /* ← 和 case 'h' 共用一段函数体 */
	... usage ...
	exit(c != 'h');
}
```

里 `case 'h'` 的块是空的,直接跳到 switch 末尾。IR 铁证:

```
@switch.test.41
	%t.223 =w ceqw %t.219, 104          ; 匹配 'h' 成功
	jnz %t.223, @switch.case.36, @switch.default.37
@switch.case.36
	jmp @switch.end.32                  ; 空块,跳走了 ✗
```

**教训**:`default` **不是** out-of-band 的分支,它是语句列表里的一个位置。
穿透链必须按**源码顺序**排:`case... → default → case...`。

**这条修完,自举 qbe 的语料成绩从 21/76 直接跳到 53/76** —— 因为 QBE 自己代码里到处都是 `case X: default:`。
一个 C 语义错误,一次带走 32 个用例。

### 1.6 (进行中)结构体指针算术被算错

**现象**:`abi5 abi6 abi8 env queen tls` 六个用例报 `sysv abi requires alignments of 16 or less`。

**定位过程**(值得记录):

1. `alloc()` 返回时内存**是全零的**(给它加自检确认)→ 排除"未初始化"
2. `AClass` 的 `sizeof`/字段偏移**与 clang 一致**(写进 `qpcc/tests/alias_shape.c`)→ 排除布局
3. 在检查点打印指针:

```
DBG chk ac=0x6000009800a0 a=0x60000098007a off=-38 inmem=196608 align=524288
```

`a` 落在 `ac` **之前 38 字节**处。起点应该是 `&ac[2] = ac+80`,减一个元素(40)应得 `ac+40`;
实际却是 `ac-38` —— 说明 `&ac[i1-i0]` 被算成了 `ac+2`(加了 **2 字节**而不是 `2*40`)。

**待修**:`Ins`/结构体指针的 `&p[i]` 与 `--p` 缩放。这是当前最高优先级的 QPCC 正确性 bug。

---

## 2. 工具链 / 环境的坑(这些最坑人)

### 2.1 macOS 没有 `timeout(1)`,`timeout ... || echo ok` 会给出假绿

我犯过的最严重的错误:对比脚本里写 `timeout 20 $qbe f.ssa`,macOS 上 `timeout` 不存在 → 返回 **127** →
输出为空 → **两个空字符串比较相等** → 76 个用例全部报"一致"。

**真实成绩当时是 20/76,我报了 76/76。**

**教训**:
- 对比脚本必须**同时比较退出码和输出**,并且把"命令没跑起来"(127)当成失败
- 不要用 `$(...)` 比较"可能什么都没输出"的东西
- 看门狗用 `( sleep N; kill -9 $pid ) &` 自己写,不要依赖 `timeout`

### 2.2 zsh 不对未加引号的变量做分词

```sh
INC="-nostdinc -I a -I b"
clang -E -P $INC file.c        # zsh: $INC 是一整个参数 → "unknown argument"
```

在 bash 里正常,zsh 里必炸。写脚本时:**要么用数组,要么把参数完整写出来**,不要依赖未加引号的变量展开。
(同理 zsh 的 `print -r --` 在 bash 里不存在。)

### 2.3 `vendor/qbe` 是 submodule,`git checkout` 要在里面执行

```sh
# 错的(从父仓库)
git checkout -- vendor/qbe/parse.c          # pathspec did not match
# 对的
cd vendor/qbe && git checkout -- parse.c
```

调完试**一定要确认 submodule 干净**,否则你的临时调试代码会被当成"源码"编进下一个结论里。

### 2.4 QBE 的测试用例是 CRLF

`vendor/qbe/test/*.ssa` 是 CRLF。直接喂给 qbe 会解析失败,必须先 `tr -d '\r'`。

### 2.5 链接 QBE 用 `xcrun ld`,不要用 clang

```sh
xcrun ld -syslibroot $(xcrun --show-sdk-path) -o qbe -lSystem *.o
```

用 clang 链接本仓库产出的目标文件会报 `ld: -lto_library library filename must be 'libLTO.dylib'`。

### 2.6 别忘了 `vendor/qbe/tools/`

`tools/lexh.c` 是**构建主机工具**,不属于 qbe。编它会在 `division by zero in constant expression` 上失败。
只编 `vendor/qbe/*.c`、`amd64/*.c`、`arm64/*.c`、`rv64/*.c`。

---

## 3. vendor/qbe 里需要知道的事实

- **`alloc()` 会清零**(`alloc` → `emalloc` → `calloc(1, n)`)。所以 C 代码里大量依赖"未初始化字段为 0"。
  一旦发现某处读到垃圾,优先怀疑**结构布局/偏移**而不是"没清零"。
- **`struct Tmp` 很大(128 字节)**,`struct Alias` 40 字节,`alias.slot` 在 +32,`tmp[i].alias` 在 +72。
  这些偏移错了不会崩在明显的地方,而是 `escapes()` 里对 NULL 解引用。见 `qpcc/tests/alias_shape.c`。
- **`parseline` 是 Duff device**,`blit`/`call`/`vastart` 三个无结果的指令靠它。
- **`escapes()` 假设 `alias.type` 是奇数时 `alias.slot` 一定非空**,`fillalias` 负责建立这个不变式。
- **optab / kwmap 是运行时填的**:`lexinit()` 把 `optab[i].name` 拷进 `kwmap[i]` 再算 `lexh[]` 哈希。
  用 lldb 在进程刚启动时读 `kwmap` 只会看到 0,**要在 `lex()` 里读**。

---

## 4. 调试方法论(省时间的做法)

1. **先分类,再定位**。23 个失败归成 4 个根因,和"23 个独立 bug"是两种工作量。
2. **临时插桩 + 立刻还原**。在 `vendor/qbe` 里加 `fprintf(stderr, "DBG ...")`,编一次看值,然后
   `cd vendor/qbe && git checkout -- <file>`。比 lldb 猜地址快得多。
3. **插桩只打标量**。第一版我打了 `a->type->align`,而 `a->type` 正是垃圾指针 → 调试代码自己崩了,
   把"数据是垃圾"这个**关键证据**变成了一个普通段错误。
4. **反汇编读寄存器**:`lldb -b -o run -k 'register read x19 x20'`,配合 `otool -tvV` 看偏移。
   上面 1.6 的 `off=-38` 就是这样来的。
5. **写最小 fixture 进 `qpcc/tests/`**。`sh qpcc/test.sh` 是 clang oracle,能立刻告诉你"是 QPCC 的错还是个例"。
6. **布局类 bug 用 `__builtin_offsetof` 写成断言**,进 oracle。已经这么做了:`alias_shape.c`。

---

## 5. 当前状态(随时更新)

```
clang oracle       126/126
moon test          353/353
QBE 源码 → arm64    19/19
自举 qbe / 76 用例  53 一致 / 23 不同
```

23 个不同按根因:

| 组 | 数量 | 用例 | 状态 |
|---|---|---|---|
| 结构体指针算术 | 6 | `abi5 abi6 abi8 env queen tls` | 已定位到 `&ac[i1-i0]`,待修 |
| `simpl`/`getcon` 挂死 | 7 | `abi4 abi9 ifc isel2 mem1 mem2 mem3` | 待查 |
| `escapes` NULL slot | 2 | `_bf99 vararg2` | 已排除越界与布局 |
| 输出差异(语义可能正确) | 8 | `abi1 abi3 dark dynalloc fold1 isel5 isel6 max` | 需语义判据复核 |

---

## 6. 一句话总结

> 自举不是"证明编译器能用",而是**一台专门暴露编译器假设的机器**。
> 它逼出来的 bug,大多不是"少写了一个 case",而是**某个 C 语义细节被实现时的捷径吃掉了**。
> 而比这些 bug 更危险的,是**验收脚本本身在撒谎**。
