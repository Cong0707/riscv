# 贡献指南

感谢参与 RV64 SystemVerilog 处理器项目。这里的“完成”指有可复现的验证证据，而不只是 RTL 能够编译。

## 开始前

请先阅读：

* [`docs/architecture.zh-CN.md`](docs/architecture.zh-CN.md)：流水线、独立 I/D 核心端口、异常边界、缓存/主存/设备层次和未来扩展契约；
* [`docs/roadmap.zh-CN.md`](docs/roadmap.zh-CN.md)：阶段依赖和验收门；
* [`docs/development.zh-CN.md`](docs/development.zh-CN.md)：原生 Windows 工具链、临时目录、验证与 Git 约定。

当前阶段和 RTL 的真实状态以可运行测试、仿真输出和操作记录为准。不要在未验证时宣称支持某个 ISA 扩展、操作系统或总线。

## 提交变更

1. 直接在最新 `main` 上工作，保持工作树可随时验证，不创建长期开发分支。
2. 一个提交只解决一个主题，标题和正文使用中文；生成物和临时文件放在 `D:\Develop\AI\codex-work\riscv`，不提交到仓库。
3. 变更 RTL、接口、测试或文档时，补充对应的验证和操作记录。I/D 端口、ISA、异常、MMU/cache、统一 DRAM 控制器、MMIO/块设备/DMA 边界变化必须同步更新架构文档、路线图门槛和 `CHANGELOG.md`。
4. 在原生 PowerShell 中运行受影响的 Verilator lint/回归；Icarus 通过只作为快速反馈，不能替代 Verilator。
5. 验证失败时先修复或撤销当前未提交改动，不把不完整状态推送到远端 `main`。

## 代码质量

使用明确的 `always_ff`/`always_comb`、显式位宽和流水 `valid`。保持 I-port/D-port 各自的 `ready/valid` 握手字段稳定、复位期间无副作用、异常精确到最老指令。不要通过全局关闭警告、修改测试期望或添加不可复现延时来掩盖错误。

## 行为准则

讨论聚焦事实、复现步骤和可验证的设计取舍。对规范或工具行为存在争议时，附上版本、最小用例和日志，而不是只引用未运行的代码或评论。
