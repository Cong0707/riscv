# 变更记录

本文件遵循 Keep a Changelog 的组织方式。版本在形成可复现发布基线后再打标签；未通过路线图验收门的功能不会写成已支持能力。

## [Unreleased]

### Added

* 增加 RV64 五级顺序流水线、改进哈佛核心接口（独立 32 位 I-port 与 64 位 D-port）、冒险/前递/精确异常边界的目标架构文档。
* 明确 I/D cache 与通道在核心侧分离、下层统一 DRAM 控制器只汇聚到 DRAM，RAM 与 MMIO/块设备/DMA 的层次边界。
* 增加从 RV64I 到 M/A、F/D/C、Zicsr/Zifencei 与特权、Sv39、缓存互连、平台设备及 OpenSBI/Linux/Ubuntu 的分阶段路线图和验收门。
* 增加原生 Windows（不使用 WSL）的 Verilator 主验证流程、Icarus 冒烟流程、仓外临时目录和 Git 分支/提交约定。
* 增加贡献指南与文档维护规则。

### Status

* 当前条目只记录工程文档和目标契约；不表示相应 RTL、仿真平台或操作系统启动功能已经实现。
