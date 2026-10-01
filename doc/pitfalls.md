# QPCC / qbe.mbt 踩坑总集

这份文档收集本仓库里**已经修掉的真 bug**,以及围绕它们的工具链陷阱。

两个来源:
- **写 QPCC(A1–A9 + 自举)**:C 语义细节被实现时的捷径吃掉
- **qbe.mbt 后端本身**:IR pass、寄存器分配、指令选择、编码器

> 结论先行:**自举不是"证明编译器能用",而是一台专门暴露编译器假设的机器。**
> 而比这些 bug 更危险的,是**验收脚本自己会撒谎**。

---

## 目录

1. QPCC 前端 / sema
2. QPCC codegen / 初始化器 / 数据
3. qbe.mbt:IR 与 pass
4. qbe.mbt:arm64 后端
5. qbe.mbt:其他后端
6. 调试信息与工具
7. 工具链 / 环境陷阱
8. vendor/qbe 须知
9. 调试方法论
10. 当前状态

---

## 1. QPCC 前端 / sema

### 1.1 `typedef` 会丢掉自己的符号性(`3f36ffc`)

**现象**:自举 qbe 对所有浮点类参数报 `missing first operand in par`。

**根因**:`declspec_to_type` 处理 `uint x`(`uint` = `typedef unsigned int`)时,发现声明里没写 `unsigned`,就用 `CInt(!uns)` 重新推导,把 `uint` 变成了**有符号**。

后果在 QBE 里被放大:

```c
struct Ins { uint op:30; uint cls:2; };   /* cls 在 32 位字最高两位 */
```

`cls` 有符号时用**算术右移**读取,`cls=2` 读成 **-2** → 数组下标越界。

**教训**:typedef 的符号性/宽度必须**继承**,不能被声明说明符二次覆盖。症状会出现在看起来完全无关的地方(浮点参数、数组越界),因为真正的传播路径是"位域读取选 `Shr` 还是 `Sar`"。

### 1.2 变参实参没有默认实参提升(`baade27`)

**现象**:自举 qbe 在**任何条件分支**上段错误。

**根因**:`check_call` 对所有实参按原类型传递,没做数组退化 / `float`→`double`。

```c
fprintf(f, "%sbb%d\n", T.asloc, id0 + b->id);
```

`T.asloc` 是 `struct Target` 里的 `char asloc[4]`,被**按值拷贝**而不是传地址 → `.L` 两个字节被当成指针。

**教训**:默认实参提升是 C 的**语义要求**,不是优化。

### 1.3 `->` 没解引用;`&&`/`||` 不短路(`2ab37cd`)

三个自举暴露的 bug:

1. sema 用**指针本身**而不是它的解引用去构造 `TMember`/`PBitField`,于是 `p->f` 读写的是指针的栈槽
2. 条件把 `&&`/`||` 两边都求值,`if (!f || strcmp(...))` 会解引用 NULL
3. stdio shim 没声明 `ungetc`/`fscanf`/`getc`/`putc`,变成隐式变参

顺带:`ARM64_RELOC_ADDEND` 被移除 —— `adrp`/`ldr` 只算基地址,偏移用额外指令加,和 clang 一致。

### 1.4 不完整数组边界没从初始化器推导(`2835172`)

```c
int x[] = { 1, 2, 3 };   /* 类型边界保持 0 */
```

局部 alloca 只有 8 字节,初始化器写越界,破坏相邻槽位。现在从初始化器(含 designator)推导边界。

### 1.5 `static` 局部变量没进数据段(`0c78f61`)

`static` 局部现在放数据段(零初始化、持久),符合 C;但如果初始化器含 `&&label`(代码生成期常量),它必须保持函数局部。

### 1.6 switch body 里嵌在 `if` 中的 `case` 被整个丢掉(`6bdaae1`)

**现象**:自举 qbe 无法解析 `vastart`/`blit`,报 `label, instruction or jump expected`。

**根因**:`check_switch` 只扫 switch body 的**顶层项**。QBE 的指令解析器是 Duff device:

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

**教训**:`case` 是**语句列表里的标签**,可以出现在任意嵌套深度。

### 1.7 `case X:` 不穿透进 `default:`(`ecfefa9`)

**现象**:自举 qbe 的 `-h` 什么都不打印。

**根因**:QPCC 把 `default` 当成"所有 case 之后的兜底":

```c
switch (c) {
case 'd': ... break;
case 'h':
default:                    /* ← 共用一段函数体 */
	... usage ...
	exit(c != 'h');
}
```

IR 铁证:

```
@switch.test.41
	%t.223 =w ceqw %t.219, 104          ; 匹配 'h' 成功
	jnz %t.223, @switch.case.36, @switch.default.37
@switch.case.36
	jmp @switch.end.32                  ; 空块,跳走了 ✗
```

**教训**:`default` **不是** out-of-band 分支,它是语句列表里的一个位置。穿透链必须按**源码顺序**:`case... → default → case...`。

**这一条修完,自举成绩从 21/76 跳到 53/76** —— QBE 自己代码里到处是 `case X: default:`。

---


### 1.8 指针差被推成指针类型(`c1e7596`)

**现象**:`abi5 abi6 abi8 env queen tls` 六个用例报 `sysv abi requires alignments of 16 or less`,而参考 qbe 处理它们毫无问题。

**根因是一条类型推导**:

```moonbit
// qpcc/sema/expr.mbt  check_binary
(CPtr(e), _) => if op == "+" || op == "-" { CPtr(e) } else { lt }
```

`p - q`(两个指针)的结果类型被判成 **`CPtr(elem)`**。C 里它是 `ptrdiff_t`,整数。

然后 codegen 靠**下标的类型**决定要不要缩放:

```moonbit
// qpcc/codegen/codegen.mbt  gen_bin
(CPtr(el), _) =>
  if !is_ptr_ty(r.ty) {        // 下标的类型是整数才缩放
    ... idx * sizeof(el) ...
  } else if op == "-" { ... }  // 否则当成 ptr+ptr,完全不缩放
```

于是 `&arr[b - a]` 算成了**字节偏移**。QBE 的 amd64 ABI 正好这么写:

```c
// vendor/qbe/amd64/sysv.c  selcall
for (stk=0, a=&ac[i1-i0]; a>ac;)
	if ((--a)->inmem) {
		if (a->align > 4)
			err("sysv abi requires alignments of 16 or less");
```

`&ac[2]` 本该是 `ac+80`,实际是 `ac+2` → `--a` 落到 `ac-38` → 读到**分配区之外**的垃圾 → 假报错。

**定位过程**(值得复用):

```
1. 给 alloc() 加自检,确认返回的内存确实全零      → 排除"未初始化"
2. 写 alias_shape.c 断言 AClass 布局(40/偏移)    → 排除"结构偏移";sizeof=40 ✓
3. 在检查点打印指针: off=-38, start=ac+2         → 反推"缩放 = 1"
4. 八种下标写法逐一二分:
     ac[n] long 变量              ✓
     ac[(long)(i1-i0)]            ✓
     ac[i1-i0]  裸指针差           ✗   ← 精确定位
     ac[3] / ac[d] / ac[(int)(...)]   ✓
```

**教训**:C 里"指针"和"整数"的区分贯穿每一步类型推导。把 `ptrdiff_t` 推成指针,后果是**另一个模块**(codegen 的缩放判据)做了一个看似合理的决定。修复只在 sema 加了 3 行,但它解释了 6 个用例。

顺带:同一个 fixture 还暴露出 QPCC **不支持声明式里引用自身**(`AClass *ac = f(sizeof ac[0]);` —— clang 作为 GNU 扩展接受,QPCC 报 `use of undeclared identifier`),这是另一个待修的小问题。

---
## 2. QPCC codegen / 初始化器 / 数据

### 2.1 聚合初始化:零填充 / 位域 / 元素类型(`83c3d73`)

复合字面量和聚合初始化器现在会:

1. **先清零整个对象**(C 要求初始化器省略的成员为 0)
2. 把标量元素**转换成目标元素类型**(之前 `char` 数组字面量按字存储)
3. 用**掩码读-改-写**写位域成员

自举症状:`lnk = (Lnk){0}` 没把 `lnk.thread` 清零 → `only data may have thread linkage`;`(char[16]){4,0,1,...}` 按 4 字节写,冲掉了自己的 `x29` 保存槽。

### 2.2 全局位域初始化器覆盖邻居(`4554693`)

位域成员的初始化器按**整个声明宽度**写,把相邻位域全部覆盖。QBE 的 `optab` 就是这个结构(`canfold`/`hasid`/`commutes`/`pinned` 打包在一个字里),于是 `canfold` 永远是错的 → 常量折叠失效 → `i->to` 非法 → `die("unreachable")`。

### 2.3 复合成员没被拷贝(`7a60303`)

`store_scalar` 对聚合类型是 `_ => ()`,于是 `(Ins){ .op = ..., .to = to, .arg = { a0, a1 } }` 里的 `.to`/`.arg` **整个丢失**。改用 `memcpy`。

### 2.4 嵌套 designator 只应用了第一层(`e6e591e`)

```c
static char *sec[2][3] = { [0][0] = "ab", [0][1] = "cd", [0][2] = "ef" };
```

三个都落到 slot 0,最后一个把字符串**字节**拷进了指针槽。在 QBE 的 amd64 emitter 里发现。

### 2.5 全局重定位没排序(`986ff47`)

数据发射按顺序走重定位,但**递减**的数组 designator(比如倒着写的关键字表)产生的重定位顺序是乱的,地址落到了错误的偏移。现在按偏移排序。

### 2.6 文件作用域的数组复合字面量没有静态对象(`30ae032`)

```c
static uchar *matcher[] = {
	[Pob] = (uchar[]){ 1, 3, 0, 3, 1, 0 },
};
```

文件作用域的数组复合字面量有**静态存储期**,`ptr_reloc` 却没生成重定位 → 指针是 NULL → `runmatch` 崩。

### 2.7 重定位 addend 被丢弃;`&arr[i]` 不认识(`9f8d2c0`)

- 目标文件发射器把每个数据重定位点的 8 字节**清零**,丢掉了 `ARM64_RELOC_UNSIGNED` 内联携带的 addend;`static struct Ins *cur = &buf[4]` 因此指向 `&buf[0]`
- `ptr_reloc` 只认识 `&name`,`&buf[i]` 完全不产生重定位

### 2.8 基本块重名(`2a88953`)

`new_block` 没有每函数序号,重复的 `switch.case`/`switch.test` 标签会**相撞**。这既是真实的 codegen bug(fixture `switchfall`),也是大输入上跑 SSA 检查的前提。

---

## 3. qbe.mbt:IR 与 pass

### 3.1 gvn 的价值号替换没有支配性保证(`aa5494f`)

`gvn` 的 killins 用"规范化指令"替换定义时,没检查替换值是否**支配**使用点,于是引入了 SSA 支配性违规。

### 3.2 gvn 的 phi 去重没有支配性保证(`77d45f7`)

`dedupphi` 只凭"参数相同"就替换 phi,现在要求替换值支配该 phi 所在块。和上一条一起,最后一个失败文件消失:**QBE 全部源码通过 QPCC 编成 Mach-O arm64 目标文件(19/19)**。

### 3.3 coalesce / gvn / gcm 之后没有去重定义(`f647da1`)

新增共享的 `gvn_dedup_defs`,在每个 pass 之后保证**每个临时量只有一个定义**,并重新启用槽合并。

### 3.4 mem/promote 的槽提升过于激进(`2835172`、`0c78f61`、`8124942`)

三个阶段:

1. 只提升"所有使用都在同一个块"的槽,避免把 load 放到定义它的 store 之前
2. 允许使用**跨块**的槽(SSA 构造会补 phi);但**读先于写**的槽留在内存里,避免出现无定义的 SSA 使用
3. 找不到可见定义时不再 abort,直接把槽留在内存

**教训**:这个 pass 的每次"放松"都对应一类真实的 SSA 违规,收紧时要能说出"为什么这样就安全"。

---

## 4. qbe.mbt:arm64 后端

### 4.1 `add/sub` 立即数没编码 `lsl #12`;溢出槽拷贝;`nrglob`(`fc9d6f8`)

- `add/sub` 立即数缺 `lsl #12` 形式
- 二进制发射器不会处理**到/从栈槽**的 copy
- `spill` 没有给 `nrglob` 留寄存器槽

这一条同时把 `gvn`/`gcm` 重新打开。

### 4.2 大符号偏移被截断(`545f726`)

偏移超过 `0xfffff` 的符号常量用 `add #imm12, lsl #12` 发射,**高位被掩掉**。现在放不进移位 imm12 的偏移走 `movz`/`movk` 进保留的 `IP0`(x16)。用 `&arr[1 << 20]` 发现。

### 4.3 PAGEOFF12 的小 addend 没内联(`98db849`)

同类问题的小偏移版本。

### 4.4 比较条件取反的默认值错(`6eda93f`)

`arm64_cmpop` 对**自反**条件(`eq`/`ne`/`fne`/`feq`)必须是恒等,却对所有情况返回 `eq`,于是"两个常量交换后的比较"编成了错的条件。**之前被 gvn 的常量折叠掩盖着。**

### 4.5 浮点常量(`c0f4c36`、`d04eb96`、`754ebdb`)

- `ir_builder::fconst/sconst` 现在把浮点常量绑定到临时量(copy),匹配 QBE 的 parser,保证后端看到的是寄存器操作数
- 二进制加载器要能物化单/双精度常量(`movz`/`movk` 进 GP 视图再 `fmov`),并且**不能依赖指令 class**(流水线可能改变它)
- 单个 `MOV` 产生浮点常量后要补 `fmov`;常量驻留(intern)时浮点常量必须**彼此区分**

### 4.6 二进制编码器的位运算 bug(`1f6ef7a`)

差分测试(`tools/check_route_b.py` 对比 route B 的 `__text` 与 clang 汇编 route A 文本)找出来的:

- `enc_br`/`enc_blr` 用了 `0xD6<<21` 而不是 `<<24`(**生产 bug**)
- `MOVN`、`ORR` 位掩码立即数、`ADD`/`SUB` 扩展寄存器形式
- 完整的位掩码立即数编码器(含 `1L<<64` 和 `>>64` 的环绕保护)

**教训**:**差分测试比单元测试有效**。手写编码器和"参考实现"逐字节对比,能抓到语义正确但编码错误的 bug。

---

## 5. qbe.mbt:其他后端

### 5.1 la64:`Addr` 在 isel 里被当成 no-op(`b66d64b`)

`isel_la64` 把 `Addr` 当内部 no-op,于是 `la64_selvastart` 为寄存器保存区物化的 addr 被丢掉,发射器把一个**未初始化寄存器**存进 `va_list`。rv64 的 isel 会发射它,照做即可。

### 5.2 la64:助记符 / 标签 / 聚合 ABI(`6b303b7`)

- 发射 `add.l` 风格助记符(LoongArch 用 `.d`)
- 每函数块 id 被复用 → `.L1` 重名 / 标签丢失
- 聚合 ABI 不完整

移植 rv64 的 ABI(聚合参数寄存器分配、`Cfpint` 转换、`Cptr` blob、返回寄存器),修 FP 大于比较(`clt`/`cle` 写反了),int↔float 转换走 FPR,物化立即数并保留 scratch 寄存器。**可汇编的参考测试从 220 涨到 338。**

### 5.3 wasm:validator-clean

同一条提交里让 wasm 输出通过 validator。

---

## 6. 调试信息与工具

### 6.1 必须发 DWARF4,不能发 DWARF5(`6f9b92f`)

macOS 的 lldb 直接拒绝:`This version of LLDB does not support DWARF version 5 or later`。编译单元改成 DWARF4(版本 4 头、low/high PC 用 `DW_FORM_addr`、不要 `.debug_addr`)。

**教训**:macOS CI 的冒烟测试抓到的 —— 只在 Linux 上验证 DWARF 会漏。

### 6.2 GitHub 的 macOS runner 上 lldb 不在 PATH(`8edcd64`)

回退到 `xcrun lldb`;并且用 `|| true` 捕获输出,免得 `set -e` 把诊断信息吞掉。

---

## 7. 工具链 / 环境陷阱

### 7.1 macOS 没有 `timeout(1)`,`timeout ... || echo ok` 给出假绿

我犯过的最严重错误:对比脚本写 `timeout 20 $qbe f.ssa`,macOS 上 `timeout` 不存在 → 返回 **127** → 输出为空 → **两个空字符串判等** → 76 个用例全报"一致"。

**真实成绩当时是 20/76,我报了 76/76。**

**教训**:对比脚本必须**同时比较退出码和输出**,并把"命令没跑起来"(127)当失败;不要用 `$(...)` 比较"可能什么都没输出"的东西;看门狗自己写 `( sleep N; kill -9 $pid ) &`。

### 7.2 zsh 不对未加引号的变量分词

```sh
INC="-nostdinc -I a -I b"
clang -E -P $INC file.c        # zsh: $INC 是一整个参数 → "unknown argument"
```

bash 正常,zsh 必炸。**要么用数组,要么把参数完整写出来。**(同理 zsh 的 `print -r --` 在 bash 里不存在。)

### 7.3 `vendor/qbe` 是 submodule

```sh
git checkout -- vendor/qbe/parse.c          # ✗ pathspec did not match
cd vendor/qbe && git checkout -- parse.c    # ✓
```

调完试**一定要确认 submodule 干净**,否则临时调试代码会被当成源码编进下一个结论。

### 7.4 QBE 的测试用例是 CRLF

`vendor/qbe/test/*.ssa` 是 CRLF,必须先 `tr -d '\r'`。

### 7.5 链接 QBE 用 `xcrun ld`,不要用 clang

```sh
xcrun ld -syslibroot $(xcrun --show-sdk-path) -o qbe -lSystem *.o
```

用 clang 链接本仓库产出的目标文件会报 `ld: -lto_library library filename must be 'libLTO.dylib'`。

### 7.6 别编 `vendor/qbe/tools/`

`tools/lexh.c` 是**构建主机工具**,不属于 qbe,编它会在 `division by zero in constant expression` 上失败。

### 7.7 两个脚本不要共用输出目录

`build-qbe-with-qpcc.sh` 开头会 `rm -rf` 自己的输出目录。曾经和 quick 脚本共用 `.qpcc_build/`,于是跑到一半 corpus 被删掉,对比只做了 31/76 就"结束"了。现在各用各的目录。

---

## 8. vendor/qbe 须知

- **`alloc()` 会清零**(`alloc` → `emalloc` → `calloc(1, n)`)。C 代码大量依赖"未初始化字段为 0"。读到垃圾时**优先怀疑结构布局/偏移**,而不是"没清零"。
- **`struct Tmp` 128 字节**,`struct Alias` 40 字节,`alias.slot` 在 +32,`tmp[i].alias` 在 +72。这些偏移错了不会崩在明显的地方,而是 `escapes()` 里对 NULL 解引用。见 `qpcc/tests/alias_shape.c`。
- **`parseline` 是 Duff device**,`blit`/`call`/`vastart` 三个无结果的指令靠它。
- **`escapes()` 假设 `alias.type` 是奇数时 `alias.slot` 一定非空**,`fillalias` 负责建立这个不变式。
- **`optab`/`kwmap` 是运行时填的**:`lexinit()` 把 `optab[i].name` 拷进 `kwmap[i]` 再算 `lexh[]` 哈希。用 lldb 在进程刚启动时读 `kwmap` 只会看到 0,**要在 `lex()` 里读**。
- **`Ins` / `Typ` / `AClass` 的字段宽度**决定位域读取和指针缩放,布局测试值得长期保留。

---

## 9. 调试方法论

1. **先分类,再定位**。23 个失败归成 4 个根因,和"23 个独立 bug"是两种工作量。
2. **临时插桩 + 立刻还原**。在 `vendor/qbe` 里加 `fprintf(stderr, "DBG ...")`,编一次看值,然后 `cd vendor/qbe && git checkout -- <file>`。比 lldb 猜地址快得多。
3. **插桩只打标量**。第一版我打了 `a->type->align`,而 `a->type` 正是垃圾指针 → 调试代码自己崩了,把"数据是垃圾"这个**关键证据**变成了一个普通段错误。
4. **反汇编读寄存器**:`lldb -b -o run -k 'register read x19 x20'`,配合 `otool -tvV` 看偏移。
5. **写最小 fixture 进 `qpcc/tests/`**。`sh qpcc/test.sh` 是 clang oracle,能立刻区分"QPCC 的错"和"个例"。
6. **布局类 bug 用 `__builtin_offsetof` 写成断言**进 oracle(`alias_shape.c`)。
7. **手写编码器/后端用差分测试**:和参考实现逐字节对比(见 4.6)。


### 9.1 先验期望值,再宣布"复现"

这一条是**我自己踩的坑**,值得单独写出来。

为了追 `blit` 的死循环,我写了一个最小复现,其中 `probe(11)` 我期望它返回 11,
于是程序返回 1 时我判定"复现成功",并据此继续追了好几轮。

实际上:**重新算一遍就知道 `probe(11)` 的 `off` 最后是 `11-8-2-1 = 0`**,返回 1 才是**正确行为**。
那个"复现"根本不存在。

**教训**:
- 最小复现的**期望值必须手算或与参考实现对照**,不能凭印象
- 更稳的做法:让复现程序**自己打印值**,并且**先用 clang 编译同一份源码**确认它会返回 0
- 如果 clang 也返回非 0,那说明**测试写错了**,不是编译器错了

### 9.2 插桩打印要 `fflush`,否则 `kill -9` 会吞掉全部证据

追挂死时用 `fprintf(stderr, ...)` 打点,然后 4 秒后 `kill -9`。
**stderr 没 flush,所有 DBG 全部丢失**,看起来像"这段代码没执行"。

修正:每次打印后加 `fflush(stderr);`,或者干脆**不用打印**,改成"加了上限就退出、看退出码变化"
(本文档里最终确认 `blit` 是死循环,用的就是后者)。

### 9.3 多变参的插桩输出本身可能不可信

`fprintf(stderr, "%d %d %d %d", a, b, c, d)` 打出来的值曾被误导过。
**单变参、多次打印**更可靠;或者改用全局计数 + 退出码来传递信息。

---

## 10. 当前状态

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

### 10.1 还没修的:结构体指针算术

`sysv abi requires alignments of 16 or less` 的真正根因:

```
DBG chk ac=0x6000009800a0 a=0x60000098007a off=-38 inmem=196608 align=524288
```

`a` 落在 `ac` **之前 38 字节**。起点应是 `&ac[2] = ac+80`,减一个元素(40)应得 `ac+40`;实际是 `ac-38` —— 反推起点为 `ac+2`,即 `&ac[i1-i0]` 被加成了 **2 字节**而不是 `2*sizeof(AClass)`。

已排除:`AClass` 布局(40 字节、偏移全对)、`alloc` 未清零(加自检确认全零)、下标越界。

---


## 11. FIXME:amd64 目标没有语义验证

**状态:已知缺口,故意留在这里。**

自举 qbe 默认目标是 `amd64_sysv`,之前所有的 76 用例对比都用它。问题是:

| 目标 | 能否在这台 macOS/arm64 上汇编 | 能否运行 |
| --- | --- | --- |
| `amd64_sysv`(默认) | ❌ 产出的是 **Linux x86-64** 汇编,`.type`/`.size` 是 ELF 指令 | — |
| `amd64_apple` | ✅ 能汇编 | ❌ `Bad CPU type in executable`(没有 Rosetta) |
| `arm64_apple` | ✅ | ✅ |

所以 **`semantic-check.sh` 只能跑 arm64_apple**。这带来两个后果:

1. **C 类那 11 个"仅输出不同"的 fixture 无法在本机做语义判定** —— 它们的差异出现在
   amd64 目标上,而 amd64 的产物在这里既汇编不了也跑不了。
2. **arm64 目标此前一次都没被量过** —— 见下。

**要补上这块,需要其中一条:**
- 一台能跑 x86-64 的机器(Intel Mac,或装了 Rosetta 的 Apple Silicon)
- 一个 Linux x86-64 环境(qemu-user 也能用)
- 或者 CI 上加一个 `ubuntu-latest` job,用 `-t amd64_sysv` 跑 `semantic-check.sh`

在补上之前,**不要根据 amd64 的字节对比结果宣称"自举 qbe 正确"** ——
那条路径既没有语义验证,也不是 QPCC 自己产出的目标。

---

## 12. arm64 目标:整片没测过的维度

第一次用 `-t arm64_apple` 跑 `semantic-check.sh`,结果:

```
$ qbe-qpcc -t arm64_apple env.ssa
Abort trap: 6          # SIGABRT
$ vendor/qbe/qbe -t arm64_apple env.ssa
(正常)
```

已跑出的部分分类(~29/76):

```
total 59: both correct 6, only reference 52, only qpcc 0, neither 1
```

也就是说:**arm64 目标上,自举 qbe 编 59 个 fixture 有 52 个语义错误**(不是"次优代码",是真的算错)。
只有 6 个和参考版一样正确。
`dark` 是 neither:参考版崩溃(rc=139),自举版直接编译失败(rc=134)。

**这已经不是"代码质量差异",是真的编错了。**而且它正好是 QPCC 自己产出的目标 ——
换句话说:**对自举 qbe 唯一重要的那个后端,此前从未被验证过。**

下一步从这里开始:先追 `env.ssa` 的 arm64 SIGABRT(断言失败通常直接指出被编坏的不变式,
一个 bug 可能带过一大批)。


## 14. 自举 qbe 的 arm64 错码:根因锁定到 `gcm`

这一节记录一个**已经定位、但还没修好**的 bug。

### 定位方法(一步二分,非常有效)

`pipeline.mbt` 把 QPCC 的优化 pass 按顺序列出。逐个注释掉再重编自举 qbe,
就能判断错码来自哪一段:

```
关掉全部优化 pass        → 自举 qbe 的 arm64 输出与参考版逐字节相同 ✓
只关掉 gcm               → 同样逐字节相同 ✓        ← 根因在 gcm
关掉 gvn(单独)           → QPCC 自己 ICE(有依赖,不能这么测)
```

`gcm` 在 `gvn/gcm.mbt`(QBE `gcm.c` 的 MoonBit 移植)。注意:这里说的不是
"QPCC 编 C 时出错",而是 **qbe.mbt 自己用 MoonBit 写的 gcm pass 编错了 C 代码** ——
正是 `/doc/pitfalls.md` 想收集的那类 bug。

### 进一步二分

`gcm` 内部三个阶段,`gcmmove` / `sink` / `schedblk`,**单独关掉任何一个都能修好**。
说明 bug 要么在它们共用的机制里(`add_one` / `addgcmins` / `gcmbid`),
要么是阶段间的相互作用。

### 已找到的与 C 的确切分歧

| 位置 | C | MoonBit | 危害 |
| --- | --- | --- | --- |
| `cheap()` | 含 `Oneg` | **漏了 `Neg`** | 偏保守,少下沉,不会错码 |
| `bestbid()` | 比较 `blk->loop`(循环头 id) | 比较 `loop_depth`(嵌套深度) | 启发式差异,位置仍在支配链上,语义安全 |
| 坐标系 | 只有 rpo 下标 | `Blk.rpo_id` 与 `Blk.id` **两套** | 需逐一核对每个数组建在哪套上 |

### 下一步(按优先级)

1. 在 `gcm` 前后 dump IL(`--emit qbe` 加 `-dG`),拿 `env.ssa` 的一个小函数,
   逐条比对"参考版 gcm 之后"与"MoonBit gcm 之后"的 IR —— 差异指令就是元凶。
2. 特别检查 `schedins` 跳过 `Nop` 而 C 不跳过这一处(可能是 `Oblit0/Oblit1`
   这类必须相邻的指令被打散)。
3. 检查 `add_one`:C 用 `fn->rpo[t->gcmbid]`,MoonBit 用 `fn->blks[gb]` ——
   只有在 `Blk.id == rpo 下标` 时才等价。

### 临时缓解

把 `pipeline.mbt` 里那次 `@gvn.gcm(...)` 注释掉,**自举 qbe 的 arm64 输出立刻正确**。
这是可用的退路,但会损失 gcm 带来的代码质量,不是修复。


### 14.1 一次失败的尝试:支配性自检不可靠

为了定位 `gcm` 的具体缺陷,我给它加了一个自检:遍历所有临时量,断言
"定义块支配所有使用块"。结果它在**每个函数**上都 abort,包括 `blit`、`emitf`、`classify`。

看起来像是找到了一个"到处都错"的惊天 bug。但把同一段自检**移到 `gcm` 之前**运行
——那时支配性按定义必然成立——**它同样 abort**。

所以是**自检写错了**,不是 gcm 错了。可能的原因:
- QPCC 的 IR 在这个阶段并非严格 SSA(有 slot 残留、或 phi 的支配规则不同)
- phi 参数的正确性判据是"定义支配**前驱**块",而不是支配 phi 所在块
- `def_order` 里可能含不可达块的陈旧指令

**教训**:写"不变量自检"之前,必须**先证明这个不变量在已知正确的输入上成立**。
拿它去跑一个必然正确的场景(这里是"gcm 之前"),如果也失败,那就是自检的错。
这一步只花了两次重编,却避免了一轮完全错误的追查方向。


### 14.2 IR 对比的两个否定结果(有用,别重复走)

想用"QPCC 的 IR"和"参考版 qbe 的 IR"直接对比来揪出 gcm 那一处错误。两个结果:

**结果一:gcm 产出的 IR 是合法的,只是语义错了。**

```sh
qpcc <file>.c --emit qbe > x.ssa      # gcm 已跑过
./vendor/qbe/qbe -t arm64_apple x.ssa  # 参考版消费它
→ rc=0,无任何报错
```

如果 gcm 产生了 use-before-def 这类**结构**错误,参考版 qbe 的 `ssacheck` 会当场拒绝。
它没有。所以缺陷不是"IR 非法",而是"IR 合法但算错了" —— 这决定了排查方向
(不要去找支配性违规,要去找**值**的变化)。

**结果二:`--emit qbe` 不经过优化流水线。**

用两个只差 gcm 开关的 QPCC 构建分别 `--emit qbe`,对 `simpl.c` 得到的两份 IL:

```
off.ssa  649 行
on.ssa   649 行
diff     (空)
```

**逐字节相同**。也就是说 `b.emit_il()` 打印的状态**不包含 gcm 的效果** ——
`--emit qbe` 走的是另一条路径,不经过 `pipeline.mbt` 的优化 pass。

所以想用 IR dump 做对比,**必须给流水线内部加 dump 钩子**(在 `@gvn.gcm` 前后各写一次),
不能指望 `--emit qbe`。


## 15. 第三次"检查器错了":被测对象是陈旧的

这一节的教训比前两次更贵,因为它污染了**一整轮**的结论。

`examples/qpcc-selfhost/semantic-check.sh` 默认读 `QBE_NEW=.qpcc_build/qbe-qpcc`。
而这个文件**只有跑 demo 脚本时才会更新** —— 我从没在改动 QPCC 之后重建它。

于是那个二进制停留在 **`c1e7596`(指针差修复)之前**。之后所有 arm64 测量,
包括那份"59 个里 52 个语义错误"的报告,**测的都是修复前的编译器**。

发现的方式是并排跑两个二进制:

```
.qpcc_build/qbe-qpcc   (旧, 早于 c1e7596)   env: SIGABRT
/tmp/v_base/qbe        (用当前树重建)       env: 与参考版逐字节相同
```

**教训:测量"编译器"时,先确认被测的那个二进制就是刚建的那个。**

### 15.1 顺便澄清:"海森"适用范围没我说的那么广

| 打印加在哪 | 谁编译它 | 会不会海森 |
| --- | --- | --- |
| `vendor/qbe/*.c`(被编译的**输入**) | **QPCC** | 会 —— 改的是被观测对象 |
| `gvn/*.mbt`(**编译器**自己) | `moon build` | 不会 —— 纯观测 |

**QPCC 从来不是 QPCC 编出来的。** 所以往 QPCC 的 MoonBit 源码里插桩是可靠的;
只有往被编译的 C 源里插桩才会扰动。

### 15.2 三次错误的共同形状

| 次数 | 犯错的角色 | 破绽 |
| --- | --- | --- |
| 1 | 支配性自检 | 在**必然正确**的位置(gcm 之前)也报错 |
| 2 | 块内顺序判据 | 同上,phi 的记账写错 |
| 3 | **被测二进制** | 与刚构建的产物**不一致** |

**三次的识别方法都一样:拿它去跑一个已知答案的场景。**



### 15.3 修正后的 arm64 基线

用**当前树重建**的二进制重跑 `semantic-check.sh`:

     both correct          : 23
     only reference correct: 13
     only qpcc correct     :  0
     neither               :  1

对比陈旧二进制上的 6 / 52 —— **陈旧二进制解释了大约 45 个失败**。

仍然失败的 13 个:`abi1 abi3 abi4 abi5 abi6 abi8 abi9 echo fold1 ifc isel2 isel5 isel6`,
外加 `dark`(参考版 rc=139、自举版 LINK-FAIL,两边都不对)。

**第 12 节里 52 个语义错误那个数字作废**,以本节为准。

**推论:`c1e7596`(指针差被推成指针类型)修好的东西远比我当时看到的多。**
那个修复提交之后我一直在用旧二进制测,所以既没看到它的收益,
又围绕一个部分已经不存在的现象追了很多轮。

## 13. 一句话总结

> 这些 bug 大多**不是"少写了一个 case"**,而是**某个语义细节被实现时的捷径吃掉了**:typedef 的符号性、默认实参提升、复合字面量的存储期、`default` 在语句列表里的位置、gvn 的支配性、指针缩放的字节数……
>
> 而比这些 bug 更危险的,是**验收脚本本身在撒谎**。

## 16. 第 3 项(自举 qbe 正确性)的工作清单

目标:让 `examples/qpcc-selfhost/semantic-check.sh` 报 0 个
`only reference correct` 和 0 个 `neither`。

### 16.1 可信基线(当前树重建的二进制)

    both correct          : 23
    only reference correct: 13
    neither               :  1

13 个失败按症状分组:

| 症状 | fixtures |
| --- | --- |
| 挂死(rc=137) | `abi1` `abi9` `ifc` `isel2` |
| 段错误(rc=139) | `abi4` `abi8` |
| 输出不同 | `abi3` `abi5` `abi6` `echo` `fold1` `isel5` `isel6` |

### 16.2 挂死组已定位到 blit(lldb,非侵入,无海森)

    frame #0: getcon + 48/88/136
    frame #1: blit + 812
    frame #2: ins + 904
    frame #3: simpl + 168

四个挂死的 fixture 全部卡在 `simpl.c:blit` 的内层循环里反复调用 `getcon`。
这是**在运行中的二进制上读栈**得到的,没有改任何源码,所以不受海森影响。

### 16.3 已排除:blit 自身逻辑没被编错

把 `blit` 原样抽出(保留结构体表、`abs`、`p++` 走表),用 stub 顶替
`newtmp`/`getcon`/`emit`,QPCC 与 clang 在 **0/1/2/3/4/8/11/15/16/20**
十个尺寸上结果**完全一致**。见 `qpcc/repro_blit.c`(标注为否定结果)。

### 16.4 下一步

`blit` 只在**传入的 size 是坏的**时候才空转:`fwd = sz >= 0; sz = abs(sz);`
之后 `for (p=tbl; sz; p++)` 会走出表外,读到垃圾 `size`,内层循环就可能永不终止。

所以下一个靶子是**调用方** —— `simpl.c:ins` 里的
`blit((i-1)->arg, rsval(i->arg[0]), fn)`。需要检查:

1. `rsval(i->arg[0])` 是否被编错(`(int)r.val ^ 0x10000000) - 0x10000000`)
2. `(i-1)->arg` 这个结构体数组参数是否被正确传递
3. `i` 与 `i-1` 的指针运算是否被编错

这三条都可以沿用 16.3 的办法:抽成 C 级最小复现,QPCC vs clang 比对。

### 16.5 最终基线(harness 完整跑完)

    both correct          : 39
    only reference correct: 20
    neither               :  1

(中途读到的 23/13 是日志还没写完,以本节的完工数字为准。)

### 16.6 第 4 次工具错误:QPCC 驱动会剥掉 #define

为了给 `blit` 的调用方做 C 级最小复现,我写了:

```c
#define INT(x)   (Ref){RInt, (x)&0x1fffffff}
...
r = INT(i);
```

QPCC 编译后链接报 `Undefined symbols: _INT` —— 看起来像"宏没展开",
我一度以为抓到了真 bug。

**实际原因**:QPCC 的驱动会剥掉所有 `#` 开头的行(包括 `#define`),
所以宏从来就没被定义过,`INT(i)` 变成了对函数 `INT` 的调用。

**正确做法**:和自举构建一样,先用 clang 预处理:

```sh
clang -E -P foo.c > foo.i && qpcc foo.i -o foo.o
```

**加上预处理之后,7 个 `INT` 用例(常量/变量/数组元素/函数实参/表达式/结构体字段)全部通过。**
那个"误编译"不存在。

### 16.7 四次错误的共同形状

| 次数 | 犯错的角色 | 识别方法 |
| --- | --- | --- |
| 1 | 支配性自检 | 在必然正确处应当沉默,它却报错 |
| 2 | 块内顺序判据 | 同上(phi 记账写错) |
| 3 | 被测二进制 | 时间戳必须是刚构建的 |
| 4 | **测试流程**(缺预处理) | 先用参考实现跑同一份输入 |

**共同根因不变:拿没验证过的装置去测量,然后相信结果。**
第 4 次能当场识破,是因为这次先测了装置:**先用已知能工作的方式跑一遍**。

### 16.8 一条客观观察:blit 循环内有未回收的栈分配

对自举 qbe 的 `_blit` 反汇编:

    00000001000489ac	b	0x100048690      ← 循环回边

    00000001000486c0	sub	sp, sp, x1
    0000000100048720	sub	sp, sp, x1
    0000000100048780	sub	sp, sp, x1
    00000001000487dc	sub	sp, sp, x1
    0000000100048878	sub	sp, sp, x1
    0000000100048910	sub	sp, sp, x4
    ...
    00000001000489e0	mov	sp, x29          ← 只在函数出口回收一次

回边跳到 `0x100048690`,而六条 `sub sp` 全在 `0x100048690` 与回边之间 ——
**即循环体内每轮都下调 `sp`,却没有任何配对的 `add sp` 把它们还回去。**
整个函数只在末尾用 `mov sp, x29` 恢复一次。

这是**客观的汇编事实**,不依赖任何推断。但它是否就是挂死的原因,**尚未证实**:
我写了一个长循环的 C 级复现,期望值算错导致输出刷屏,没有得到结论 ——
**不能把它当成已确认的根因。**

可疑之处:按 64 字节/轮 × 4e6 轮算,栈应当溢出;复现却没给出干净的信号,
说明要么触发条件不对,要么这条泄漏在该规模下还不足以致命。

**下一步**:写一个**期望值正确、输出受控**(只在最后打印一次)的复现,
只测"循环 N 轮后局部变量是否仍然正确",用 clang 作对照。

### 16.9 那条栈观察仍未证实,而且我的简化没复现出来

写了一个受控复现(期望值正确、只在最后打印一次):

```c
int main(void) {
  long i, acc = 0, n = 2000000L;
  for (i = 0; i < n; i++) {
    struct T t = { { 1,2,...,16 } };   /* 循环体内的聚合初始化 */
    acc += t.a[0] + t.a[15];
  }
  ... 校验 acc == 17*n ...
}
```

结果:

    QPCC 编的 main: sub_sp=1  restore=1     ← 平衡
    clang 编的 main: sub_sp=0 restore=0
    两者都输出 OK,rc=0

**QPCC 把循环体内的聚合初始化处理成了静态数据,没有每轮下调 sp。**
所以这个形状**不能**复现 blit 里的六条无配对 sub sp。

**结论:blit 里那个模式来自别处**(可能是 emit(...) 的按值结构体传参,
或 tbl 数组本身的构造方式),还需要更贴近的还原。

**在证实之前,16.8 那条观察只是一条观察,不是根因。**

## 17. 一个新的最小失败:负数常量存进静态 64 位变量

```c
static long long g;
int main(void) { g = -1; return g == -1 ? 0 : 1; }
```

QPCC 存进去的是 `0x00000000FFFFFFFF`,应为 `0xFFFFFFFFFFFFFFFF`。
复现见 `qpcc/repro_neg2.c`。

### 17.1 已排除的范围

| 假设 | 结论 |
| --- | --- |
| arm64 后端没下降 `extsw` | ❌ 六种扩展(extsw/extuw/extsb/extub/extsh/extuh)两边生成的汇编**逐字相同** |
| `foldint` 折叠 `Extsw` 算错 | ❌ `fold/fold_wbtest.mbt` 已有断言 `-2147483648`,通过 |
| `ssa/copy.mbt` 的 `iscopy` 把它当复制消掉 | ❌ `i.cls == Kl && t.cls == Kw` 时明确返回 false |
| 局部变量也一样 | ❌ 局部 `long long` 正确;`static int` 正确;从 int 变量赋值也正确 |

### 17.2 剩下的线索

`--emit qbe` 打出来的 IR 是**对的**:

    %t.1 =w sub 0, 1
    %t.2 =l extsw %t.1        ← 正确
    storel %t.2, $g

但 `--emit qbe` **不经过优化流水线**(见 14.2),所以真正进后端的 IR 已经被改坏。
真实汇编是 `mov w0, #-1` / `str x0` —— 一个 **32 位**常量,说明 `extsw` 被折叠成了
**`Kw` 类别的常量**,而不是 `Kl`。

### 17.3 下一步

在**优化后**的 IR 上定位(而不是 `--emit qbe`):

1. 检查 `fold`/`gvn` 里把扩展指令折成常量时,新常量的 **class** 是 `Kw` 还是 `Kl`
2. 检查 IR builder 的 `iconst`,对 `Kl` 类的负常量是否只写了低 32 位
3. 用 `-d` 系列 dump 优化各阶段(参考版 qbe 有 `-dM`/`-dG` 等)

### 17.4 二分定位到 gvn

用 C 级最小复现(秒级反馈)逐个关掉优化 pass,而不是等自举构建:

    cp pipeline.mbt.bak pipeline.mbt && moon build      rc=1  (bug 存在)
    关 G (gvn_dedup_defs)                               rc=1
    关 C (coalesce)                                     rc=1
    关 V (gvn)                                          rc=0  ← 修好了
    关 S (simplcfg)                                     rc=1
    关 M (gcm)                                          rc=1
    关 I (ifconvert)                                    rc=1

关掉 gvn 就没问题了,所以病灶在 gvn/gvn.mbt。

注意 gvn.mbt 里的折叠表达式本身是对的:

    @types.Extsw => l << 32 >> 32      // 符号扩展,正确
    @types.Extuw => l & 0xFFFFFFFF

所以问题不在算出来的值,而在折叠结果怎么落地 -- 生成的常量或替代指令
用的是 Kw 类而不是 Kl,于是后端发出 mov w0, #-1(32 位)再接 str x0。

下一步:在 gvn.mbt 里找把折叠结果写成常量或 copy 的地方,看它的 cls 取
i.cls 还是硬编码的 Kw。

方法学收获:C 级最小复现让 pass 二分从每次 3-5 分钟变成每次约 2 分钟,
六次二分不到 15 分钟。这是本轮最有用的工具组合。

### 17.5 决定性证据:gvn 删掉了 sxtw

同一份 C,只切 gvn 开关,对比 `main` 的汇编:

    gvn 关(正确)                 gvn 开(错误)
      mov  w1, #0x1                 mov  w0, #-0x1
      mov  w0, #0x0                 str  x0, [x1]     <-- 少了 sxtw
      sub  w0, w0, w1               cmn  x0, #0x1
      sxtw x0, w0   <-- 在这里      b.eq
      str  x0, [x1]
      cmp  x0, x1
      b.eq

**`gvn` 把符号扩展 `sxtw` 整条删掉了**,于是 32 位的 `0xFFFFFFFF` 被当成 64 位值
使用 —— 正是 `mov w0, #-1` 后直接 `str x0` 的来源。

### 17.6 嫌疑点

`gvn.mbt:1428`:

    if i.cls == Kw && (i.op == Extsw || i.op == Extuw) {
      return i.arg1                      // 无条件返回操作数
    }

以及 `gvn.mbt:1435` 的守卫:

    if i.cls.wide() > fn_.tmps[tid].cls.wide() {
      return Ref::none()                 // 只有这条路径挡了加宽
    }

**1428 这条早退发生在 1435 的守卫之前**,而且不检查操作数的类别。
如果 `i.cls` 是 `Kw` 但操作数实际承载的是需要 64 位的值,这一行就会把加宽删掉。

下一步:确认这条早退是否应当要求 `i.cls == fn_.tmps[tid].cls`(或至少
`i.cls.wide() <= 操作数.wide()`),并写一个白盒测试固定住。

### 17.7 排除 copyref,锁定 foldref

`gvn` 里替换指令的分支有两个:

    let r  = copyref(st, b, i)
    if !r.is_none() && gvn_dom_ok(st, r, b.id, idx)      { killins(st, i, r);  return }
    let r2 = foldref(st.fn_, i)
    if !r2.is_none() && gvn_dom_ok(st, r2, b.id, idx)   { ... }

两者都**只查支配性,不查类别**。我给 `copyref` 分支加了一个类别守卫
(`gvn_class_ok`:替换值的类别宽度不得小于被替换指令),重建后 rc **仍是 1**。

⇒ **病灶不在 copyref,而在 foldref。**

`foldref` 会把 `%t.2 =l extsw %t.1` 折成一个常量。它折叠出的值应当是
`-1`(64 位),但实测发出的汇编是 `mov w0, #-1`(32 位)再接 `str x0` ——
说明折出来的常量在**被使用时按 32 位处理**了。

那个守卫已撤回(没修好,且改动有风险,不应留在树里)。

**下一步**:看 `foldref` 对扩展指令的处理,以及它产出的常量被替换进指令时
`i.cls` 是否仍然正确。

### 17.8 确证在 foldref,并排除两种"关掉折叠"的做法

实验(每次都从干净的 gvn.mbt 出发,只改一处,重建后跑秒级复现):

| 改动 | 复现 rc | oracle |
| --- | --- | --- |
| 关掉整个 foldref 分支 | **0** ✓ | 126/129 ✗ (坏 3 个) |
| 关掉 Extsw+Extuw 折叠 | **0** ✓ | 128/129 ✗ (坏 fold_shift) |
| 只关 Extsw 折叠 | **0** ✓ | 128/129 ✗ (还是 fold_shift) |
| 给 c_opfold 的 32 位截断加 sext 豁免 | 1 ✗ | 129/129 |

**结论:**

1. 病灶确证在 `foldref`(关掉它,复现就消失)。
2. **不能靠关掉折叠来修** —— `fold_shift` 依赖它。
3. 我那个"截断加豁免"的猜想**是错的**:改了之后 rc 仍是 1,说明 `cls.wide()` 本来就是 1,
   截断根本没发生,值在更早的地方就已经是 `0xFFFFFFFF` 了。

`c_opfold` 的收尾确实有这么一段截断:

    let c2 = if cls.wide() == 0 {
      Con::{ bits: ConBits::{ i: c.bits.i & 0xFFFFFFFF, ... } }
    } else { c }

而且 `extsw` 在 ops.h 里确实带 canfold 标志:

    O(extsw, T(e,w,e,e, e,x,e,e), F(1,0,0,0,0,0,0,0,0,0)) X(0,0,1) V(0)

但既然截断不是原因,下一个要说清的问题是:
**`foldref` 折出的那个 con,值究竟是 `-1` 还是 `0xFFFFFFFF`** ——
以及 `killins` 把它替换进指令后,消费方按哪个宽度读。

**下一步(明确):**

在 `foldref` 返回前打一行调试输出(打印 `i.op`、`i.cls`、`i.arg1` 的 con 值、
以及折出的 `c.bits.i`),只在 `Extsw` 时打印。这是**非 Heisenberg** 的 ——
QPCC 由 `moon build` 编译,不经 QPCC 自己 —— 所以可以直接看真实值。

**临时改动已全部撤回,树是干净的。**

### 17.9 决定性调试结果:折叠是正确的

在 `foldref` 里只对 `Extsw`/`Extuw` 打了调试输出(QPCC 由 moon build 编译,
**非 Heisenberg**),跑最小复现:

    DBG cls=1 a1=4294967295 a2=0 got=-1
    DBG cls=1 a1=4294967295 a2=0 got=-1

解读:

* `cls=1` 是 `Kl`(64 位)
* `a1=4294967295` 是操作数常量 `0xFFFFFFFF`(来自 `sub 0,1` 在字宽下的折叠,正确)
* **`got=-1` —— 折叠结果完全正确**

**所以 `foldref` 是无辜的。** 它折出了正确的 `-1`,并把正确的 con 放进常量池
(调试打印读的就是常量池里的值)。

### 17.10 真正的病灶:物化 Kl 常量时用错了指令宽度

失败程序的汇编是:

    mov  w0, #-1      <-- 32 位 move
    str  x0, [x1]     <-- 再存 64 位

`mov w0, ...` 会**清零 x0 的高 32 位**,所以存进去的是 `0x00000000FFFFFFFF`。
对一个 `Kl` 常量,这里应当发 `mov x0, #-1`。

这段代码在 `vendor/qbe/arm64/emit.c` 里 —— 也就是 **QPCC 编译 QBE 的 emit.c 时
把常量物化编错了**。

### 17.11 为什么二分指向 gvn

`gvn` 关掉时,`sub 0,1` 和 `extsw` 不会被折成常量,`emit.c` 拿到的是**寄存器**,
于是走不到那条错误的常量物化路径。**gvn 只是"触发器",不是病因。**

这也解释了为什么"关掉 foldref 分支"能让复现消失 —— 同上,它只是让常量不再产生。

### 17.12 下一步

在 `vendor/qbe/arm64/emit.c` 里找 `Kl` 常量的物化(类似 `emitcon`/`mov` 的选型),
看它对**负数**或**能塞进 32 位的值**的判断分支。

注意:**改 `vendor/qbe/*.c` 是 Heisenberg 的**(那是被测输入)。所以正确路径是
用**最小 C 复现**还原 `emit.c` 里那个判断,再用 QPCC 编译它,对比 clang。
