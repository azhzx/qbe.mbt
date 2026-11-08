# QBE 逐项一致性审计与修复计划

> 执行依据：用户要求逐文件、函数、结构体对齐 vendor/qbe；不是重新设计编译器。

**Goal:** 修复已确认会导致错误的简化移植，保留有依据的安全差异。
**Architecture:** 上游 661ceb22 为行为依据，现有 HEAD 938fc19 与工作区初始未提交改动作为基线。按不重叠子系统并行阅读，具体错误先失败回归后最小转写修复。
**Tech Stack:** MoonBit native / upstream C QBE / 现有 compare.py 与 backend gates。
**Spec:** 用户本轮要求及 AGENTS.md。

## 约束
- 不改 vendor，不覆盖初始 lexer/parser 未提交更改，不提交或重置用户工作区。
- 不以历史 ledger 或通过现有测试代替逐声明检查；逐项标记已读、安全差异、错误、未覆盖。
- 共享 helper 不复制；C 位宽、无符号、值复制/对象别名、哨兵、遍历顺序都需要证据。
- 新自动化仅 .mbtx；可直接运行已有 Python 验证工具。
- 子域仅修改自己的分配范围；全仓格式与接口生成由 lead 最后统一运行。

## 工作项
- [x] 读取 git 修复历史、当前差异与上游版本。初始修改：lexer/lexer.mbt、lexer/lexer_wbtest.mbt、parser/func.mbt、parser/parser_wbtest.mbt，以及未跟踪 parser/variadic_wbtest.mbt。
- [ ] Frontend/driver/shared emit：lead 核对 parse.c/main.c/emit.c，函数及结构体映射写入独立报告。
- [ ] Core optimization：cfg/ssa/mem/fold/ifopt/gvn 全声明复核。
- [ ] Register allocation：live/spill/rega 全声明复核。
- [ ] Types/util：all.h/ops.h/util.c/abi.c 字段及表格复核。
- [ ] AMD64：sysv/winabi/isel/emit/targ 全声明复核。
- [ ] ARM64：abi/isel/emit/targ 全声明复核。
- [ ] RV64：abi/isel/emit/targ 全声明复核。
- [ ] 每个确认偏差：记录上游分支 → 编写实际失败回归 → 转写最小修复 → 定向测试和参考差分 → 记录证据。
- [ ] 汇总各域覆盖清单、复审跨域影响。无上游对应的扩展单独标注，不假称已与 C 对齐。
- [ ] 运行 moon check、moon test、上游 debug/assembly 差分、相关 backend gates，moon info && moon fmt，检查 mbti 和 git diff。

## 重点边界
1. 整数转换、负数/无符号比较、超大字段计数与固定表上限。
2. 空块、不可达块、phi 更新和迭代期间数组变动。
3. 聚合/变参 ABI、寄存器用尽、栈对齐和返回值。
4. 数据字面量、符号引用、转义字符串、浮点舍入与解析边界。
5. 公共对象浅复制和 C 按值复制不等价，辅助算法重复实现漂移。

## 基线验证
- make -C vendor/qbe：成功，已是最新构建。
- moon test：失败于 run_asm 的宿主 clang 链接，报 ld: -lto_library library filename must be libLTO.dylib；不是本轮修改引入。需确认环境解决方式并完整复跑，不以过滤结果称全量通过。
