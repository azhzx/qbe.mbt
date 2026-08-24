# azhzx/qbe

> 用Moonbit重写qbe

# 项目文档
> **[Qbe.mbt文档](doc/)**

# 项目简介
qbe.mbt 计划将 Quick Backend (qbe) 的核心后端能力移植到 MoonBit 生态

提供轻量级的编译器后端

提供 SSA 中间表示、IL 文本解析与输出、指令选择、寄存器分配、ABI 处理

# 核心功能范围
提供 qbe 风格的 SSA 中间表示模型，支持函数、基本块、临时变量、指令、跳转、phi 节点、数据段和类型系统；

支持 qbe IL 文本格式的解析、输出和 pretty print，便于与上游 qbe 工具链或自研前端交换中间表示；

提供统一编译入口

支持 amd64

支持基础后端流程

支持常用 IL 指令

提供调试辅助模块

提供不少于 300 个 MoonBit 测试文件，并持续保持核心回归测试通过；

提供 README 示例，覆盖 IL 解析、SSA 构建、寄存器分配、汇编输出和目标架构选择。

# 移植或参考说明
原项目信息
原项目名称：Quick Backend (qbe)

原项目链接：https://github.com/8l/qbe

本项目许可证：Apache 2.0

原项目许可证：MIT

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

使用MoonBit现代ML系语言的写法重新编写代码，而不是复刻 C 的 suckless 结构；

优先实现可在MoonBit中独立运行的核心后端流程

改写原c代码的手动内存管理为MoonBit安全数据结构与枚举类型，降低内存风险；

# 未来计划
- 支持更多平台（包括wasm）的代码生成支持
- 添加方便JIT的相关接口
- 对接mbtcc，验证全流程的端到端的可行性