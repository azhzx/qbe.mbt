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

## 11. 一句话总结

> 这些 bug 大多**不是"少写了一个 case"**,而是**某个语义细节被实现时的捷径吃掉了**:typedef 的符号性、默认实参提升、复合字面量的存储期、`default` 在语句列表里的位置、gvn 的支配性、指针缩放的字节数……
>
> 而比这些 bug 更危险的,是**验收脚本本身在撒谎**。
