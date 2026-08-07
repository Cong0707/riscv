# 变更记录

本文件遵循 Keep a Changelog 的组织方式。版本在形成可复现发布基线后再打标签；未通过路线图验收门的功能不会写成已支持能力。

## [Unreleased]

### Added

* 增加可运行的 RV64I 五级顺序流水线核心，以及独立 32 位 I-port 和 64 位 D-port 的改进哈佛 RTL 实现。
* 增加 RV64I 解码、立即数、ALU、寄存器堆、前递、load-use 停顿、分支冲刷和基础精确 trap 停机逻辑。
* 增加自检 RV64I 镜像、SystemVerilog 测试平台、原生 Windows Icarus/Verilator 脚本和 GitHub Verilator CI。
* 增加完整 RV64M 解码、握手式乘除单元、EX 停顿和结果前递，覆盖 8 条 64 位指令与 5 条 W 类指令。
* 增加 RV64M 独立镜像、边界参考模型和核心级自检，覆盖除零、最小负数除以 `-1`、连续 M 指令依赖及 W 类符号扩展。
* 增加 RV64A 单核功能基线，覆盖 `LR.W/D`、`SC.W/D` 和 `AMOSWAP/ADD/XOR/AND/OR/MIN/MAX/MINU/MAXU.W/D`。
* 增加阻塞式 D-port 原子读改写、W 形式旧值符号扩展、本地 reservation、普通 store 清 reservation，以及 SC 失败不写内存的语义。
* 在当前顺序单发射、单 outstanding 模型下以强顺序满足 `aq/rl`；外部原子事务属性留待互连阶段实现。
* 增加 RV64C 整数压缩指令解压、标准 HINT 处理和保留编码分类；依赖 F/D 的压缩浮点形式保持非法。
* 增加 `IALIGN=16`、2/4 字节指令长度元数据、半字 PC 和对齐 32 位 I-port 上的跨取指字拼接。
* 增加 RV64C 混合宽度镜像和核心级自检，覆盖 30 个签名、18 次跨字拼接、压缩跳转链接地址、全部整数压缩指令组和 `C.UNIMP` 原始异常值。
* 将 Git 工作流简化为只维护 `main`，提交信息统一使用中文。
* 增加 RV64 五级顺序流水线、改进哈佛核心接口（独立 32 位 I-port 与 64 位 D-port）、冒险/前递/精确异常边界的目标架构文档。
* 明确 I/D cache 与通道在核心侧分离、下层统一 DRAM 控制器只汇聚到 DRAM，RAM 与 MMIO/块设备/DMA 的层次边界。
* 增加从 RV64I 到 M/A、F/D/C、Zicsr/Zifencei 与特权、Sv39、缓存互连、平台设备及 OpenSBI/Linux/Ubuntu 的分阶段路线图和验收门。
* 增加原生 Windows（不使用 WSL）的 Verilator 主验证流程、Icarus 冒烟流程、仓外临时目录和 Git 分支/提交约定。
* 增加贡献指南与文档维护规则。

### Status

* 当前已形成 `RV64IMAC` 功能基线；A 扩展当前限定于单核阻塞式 D-port，不表示阶段 2 的全部系统验收已经关闭。
* 阶段 2 尚缺外部总线原子锁定/独占属性、随机并发、访问错误和编译器自旋锁验收。
* 多核 cache 一致性和 DMA reservation 监听属于后续互连阶段，当前同样未提供。
* 当前基线仍不包含 `F/D`、压缩浮点形式、特权架构、`Sv39`、cache、平台设备或 Linux/Ubuntu 启动；这些功能按路线图分阶段推进。
