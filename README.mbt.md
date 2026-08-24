# azhzx/qbe

用moonbit重写qbe

# 项目简介
qbe.mbt 计划将 Quick Backend (qbe) 的核心后端能力移植到 MoonBit 生态，为 MoonBit 及其他语言工具链提供轻量级、可嵌入的编译器后端。项目面向需要在 MoonBit 中构建代码生成器、编译器后端或语言原型的开发者，提供 SSA 中间表示、IL 文本解析与输出、指令选择、寄存器分配、ABI 处理以及 amd64、arm64、riscv64 汇编输出等能力。通过 MoonBit API 和与上游 qbe 对照的测试体系，qbe.mbt 可作为 MoonBit 语言实现、教学编译器、AOT/JIT 原型和原生代码生成实验的基础设施。

# 核心功能范围
提供 qbe 风格的 SSA 中间表示模型，支持函数、基本块、临时变量、指令、跳转、phi 节点、数据段和类型系统；

支持 qbe IL 文本格式的解析、输出和 pretty print，便于与上游 qbe 工具链或自研前端交换中间表示；

提供统一编译入口 new_backend(target).compile(module)，支持按目标架构分发后续流程；

支持 amd64 等主要目标架构的基础指令选择与汇编文本生成；

支持基础后端流程，包括寄存器分配、栈帧布局、参数传递、调用约定和 ABI 处理；

支持常用 IL 指令，包括算术、比较、位运算、内存访问、跳转、返回、phi 节点和类型转换；

提供目标架构元数据、寄存器集合、指令匹配表、IR 验证和调试辅助模块；

提供与上游 qbe 参考实现对照的差异测试、随机 IL 用例和迁移记录；

提供不少于 300 个 MoonBit 测试文件，并持续保持核心回归测试通过；

提供 README 示例，覆盖 IL 解析、SSA 构建、寄存器分配、汇编输出和目标架构选择。

# 移植或参考说明
原项目信息
原项目名称：Quick Backend (qbe)

原项目链接：https://github.com/8l/qbe

原项目许可证：MIT

本项目许可证：MIT

原项目许可证原文
```
© 2015-2017 Quentin Carbonneaux quentin@c9x.me

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
```

与原项目相比，本项目会做以下简化和重新设计：
使用 MoonBit 原生包结构、类型系统和测试方式组织代码，而不是复刻 C 的 suckless 结构；

优先实现可在 MoonBit 中独立运行的核心后端流程，弱化对 C 工具链、POSIX 环境和 Makefile 构建方式的依赖；

对暂未完整支持的优化 pass、ABI 变体、调试格式和特殊指令保留兼容入口和明确错误行为，作为后续扩展；

将 C 中的手动内存管理、指针运算、联合体和隐式类型转换改写为 MoonBit 安全数据结构与枚举类型，降低内存风险；

以 MoonBit API 和 IL 文本输入输出为主要交付接口，方便接入 MoonBit 编译器、CLI、JIT 原型和教学实验环境

# 未来计划
- 支持更多平台（包括wasm）的代码生成支持
- 添加方便JIT的相关接口
- 对接mbtcc，验证全流程的端到端的可行性