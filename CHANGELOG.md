# 变更记录

本文件遵循 Keep a Changelog 的组织方式。版本在形成可复现发布基线后再打标签；未通过路线图验收门的功能不会写成已支持能力。

## [Unreleased]

### Added

* 增加可运行的 RV64I 五级顺序流水线核心，以及独立 32 位 I-port 和 64 位 D-port 的改进哈佛 RTL 实现。
* 增加 RV64I 解码、立即数、ALU、寄存器堆、前递、load-use 停顿、分支冲刷和基础精确 trap 停机逻辑。
* 增加自检 RV64I 镜像、SystemVerilog 测试平台、原生 Windows Icarus/Verilator 脚本和 GitHub Verilator CI。
* 增加完整 RV64M 解码、握手式乘除单元、EX 停顿和结果前递，覆盖 8 条 64 位指令与 5 条 W 类指令。
* 增加 RV64M 独立镜像、边界参考模型和核心级自检，覆盖除零、最小负数除以 `-1`、连续 M 指令依赖及 W 类符号扩展。
* 将 Git 工作流简化为只维护 `main`，提交信息统一使用中文。
* 增加 RV64 五级顺序流水线、改进哈佛核心接口（独立 32 位 I-port 与 64 位 D-port）、冒险/前递/精确异常边界的目标架构文档。
* 明确 I/D cache 与通道在核心侧分离、下层统一 DRAM 控制器只汇聚到 DRAM，RAM 与 MMIO/块设备/DMA 的层次边界。
* 增加从 RV64I 到 M/A、F/D/C、Zicsr/Zifencei 与特权、Sv39、缓存互连、平台设备及 OpenSBI/Linux/Ubuntu 的分阶段路线图和验收门。
* 增加原生 Windows（不使用 WSL）的 Verilator 主验证流程、Icarus 冒烟流程、仓外临时目录和 Git 分支/提交约定。
* 增加贡献指南与文档维护规则。

### Status

* 当前已形成 RV64IM 可执行基线：Python 参考测试、Verilator lint/仿真和 Icarus 冒烟均通过。
* 当前基线仍不包含 `A/F/D/C`、特权架构、`Sv39`、cache、平台设备或 Linux/Ubuntu 启动；这些功能按路线图分阶段推进。
