# 原生 Windows 开发规范

## 1. 目标与边界

本项目在 Windows 原生环境开发和验证，明确不使用 WSL、Linux 虚拟机或依赖 Bash 的隐式构建步骤。PowerShell 是默认命令行；脚本如需跨平台，应使用明确的 PowerShell 入口或 CMake/Ninja，而不是假设 `/bin/sh` 存在。

Verilator 是主要仿真、lint、覆盖率和长回归工具，作为工业级可综合 SystemVerilog 流程的基准。Icarus Verilog 只做快速冒烟回归，不能替代 Verilator 或综合器对最终语义的检查。

## 2. 目录与产物

仓库只保存源代码、测试向量、脚本、配置和必要的黄金结果。所有临时文件、构建目录、波形、覆盖率数据库、仿真日志和下载镜像放在：

```powershell
$env:RISCV_WORK_ROOT = 'D:\Develop\AI\codex-work\riscv'
```

建议按提交和工具分层，例如 `$env:RISCV_WORK_ROOT\verilator\debug\<commit>`、`iverilog\smoke\<commit>`、`waves\`、`logs\`。仓库内不得出现临时 `.obj`、`.pdb`、`.vcd`、`.fst`、`coverage.dat` 或生成的可执行文件。操作记录使用日期加中文名称的 Markdown，存放在 `D:\Develop\AI\codex操作记录\riscv`，并在记录中写明工具版本、命令、输入哈希、结果和已知问题。

## 3. 工具链

建议固定并记录以下工具版本：

* Git for Windows；
* PowerShell 7；
* Verilator（建议使用 MSYS2 UCRT64/CLANG64 提供的原生 Windows 包，并从 PowerShell 调用；MSYS2 不是 WSL）；
* 与 Verilator 包匹配的 MinGW-w64/Clang C++ 编译器，以及 CMake/Ninja；未经项目回归确认前不假定 MSVC 可直接替代；
* CMake 与 Ninja（若采用 CMake 驱动）；
* Icarus Verilog（可选）；
* RISC-V GNU toolchain（`riscv64-unknown-elf-*`，后续再加入 Linux 交叉工具链）；
* Python 仅用于确定性测试辅助，不承担核心 RTL 语义。

工具版本应由脚本或操作记录打印。下载工具或镜像时保存来源、版本和 SHA-256；不要把个人目录、凭据或未审计二进制提交进仓库。

## 4. 推荐验证层次

1. **静态检查**：Verilator lint、编译器警告、SystemVerilog 语法和未驱动信号检查。
2. **单元测试**：ALU、立即数、解码、寄存器堆、前递和内存适配器；使用确定性时钟和复位。
3. **流水定向测试**：加载后使用、分支冲刷、存储前递、内存背压、异常优先级。
4. **架构测试**：按路线图阶段接入 RV64I/M/A/F/D/C 和特权测试；保存失败指令和提交轨迹。
5. **参考模型差分**：裸机阶段可用解释器，稳定后接 Spike 或其他经过版本固定的参考模拟器。
6. **软件启动**：OpenSBI、Linux、Ubuntu 只在前置硬件验收门通过后加入长回归。

每一层都要能单独运行。长回归失败时，先用同一输入缩小到最早出错的层级，不用后续软件日志覆盖早期流水证据。

仿真平台应同时驱动独立的 I-port（32 位取指）和 D-port（64 位加载/存储），并能对两条通道施加独立背压。下层模型可在统一 DRAM 控制器处汇聚到 DRAM，但测试输出必须保留 I/D 来源。RAM 初始化镜像、MMIO 设备模型和块设备/磁盘镜像分开管理；块设备通过 MMIO 控制器和 DMA 验证，不能把磁盘镜像当作 RAM 文件加载。

## 5. Verilator 基线

Verilator 回归至少包含 lint、可执行仿真、随机背压和波形选项。示例命令（模块名和文件列表以仓库实际入口为准）：

```powershell
verilator --lint-only --Wall --Wno-fatal <top-and-sources>.sv
verilator --cc --exe --build --trace --timing <top-and-sources>.sv <tb>.cpp
```

* 统一声明时钟周期、复位时序和仿真结束条件，避免依赖主机墙钟。
* 长回归设置明确的周期上限和失败退出码；测试结束必须关闭波形并刷新日志。
* 对 `ready/valid`、流水寄存器 `valid`、提交信号和异常出口增加断言或监视器。
* 运行目录、`obj_dir` 和波形输出必须通过参数指向 `RISCV_WORK_ROOT`。
* Verilator 警告若暂时不能修复，记录规则、触发文件和移除条件；禁止无理由全局关闭警告。

## 6. Icarus 快速回归

Icarus 适合在编辑后快速检查小模块和短指令序列。由于其 SystemVerilog 覆盖范围和时序模型与 Verilator 不完全相同：

* 只把通过 Icarus 的结果当作冒烟信号；
* 不以 Icarus 通过替代 Verilator lint、长回归或架构测试；
* 记录使用的标准开关（例如 `-g2012`）和输出路径；
* 发现两个仿真器结果不一致时，以可复现的时序分析和 Verilator/参考模型结果为主，不能简单修改测试迎合其中一个。

## 7. SystemVerilog 编码约定

* 时序逻辑使用 `always_ff @(posedge clk...)`，组合逻辑使用 `always_comb`；避免同一信号多处驱动。
* 用 `logic`、`typedef`、`enum` 和 package 表达接口与状态；端口方向和位宽显式写出。
* 所有流水项带 `valid`，复位值和气泡行为明确；组合块给所有输出默认值，禁止锁存器。
* I-port/D-port 的 `valid` 不依赖 `ready`，各自在握手前保持请求字段；响应错误必须走统一异常路径。不要在核心内重新合并两个端口。
* MMIO 访问标记为 device/uncached 并绕过 D-cache；块设备寄存器、DMA 描述符和磁盘介质使用独立的测试模型与日志。
* 优先使用参数化宽度和局部常量，不复制散落的魔数；改变接口时同步更新架构文档和测试。
* RTL 注释解释时序、协议或不明显的设计理由，不写逐行翻译式注释。
* 综合友好代码与仿真专用代码分离；`$display`、文件 I/O 和断言控制用 `ifdef` 或测试平台封装。

## 8. Git 分支与提交

### 8.1 分支

* `main`：可发布、通过当前验收门的基线，禁止直接推送。
* `develop`：阶段集成分支；若团队规模较小，可以在 `main` 上按同等保护规则工作，但须保留阶段标签。
* `feature/<短名>`：单一功能或文档变更；从最新集成分支创建，完成后合并并删除。
* `fix/<短名>`：缺陷修复；提交信息说明触发条件和回归测试。
* `experiment/<短名>`：不会进入稳定分支的探索，必须标明不可用于阶段验收。

分支名使用 ASCII 小写、短横线或斜线，不把日期和机器用户名作为唯一标识。禁止重写共享分支历史；修复应以新提交完成。

### 8.2 提交

采用 Conventional Commits 风格：`feat(core): ...`、`fix(mem): ...`、`test(rv64i): ...`、`docs: ...`、`build: ...`。提交正文说明：改变了什么、为何改变、如何验证、是否影响 ISA/协议/时序。一个提交尽量对应一个可审查主题，不混入格式化噪声、生成物或无关重构。

提交前至少执行受影响范围的 Verilator lint 和定向测试；改变流水、内存或特权边界时执行对应阶段的完整回归，并在操作记录中保存命令和结果。

## 9. 合并与审查

Pull request/合并请求应包含目的、架构影响、验证命令、失败/已知限制、波形或提交轨迹位置。审查优先检查：精确异常、I/D 两条 `valid/ready` 通道稳定性、前递和冲刷、复位、未定义位、缓存/DRAM 来源标记、MMIO/DMA 边界、综合可行性及跨仿真器差异。

涉及以下任一项必须同时更新架构文档和 CHANGELOG：ISA 编码或结果、I/D 端口握手、提交顺序、异常/CSR、MMU/cache 边界、统一 DRAM 控制器、MMIO/块设备/DMA 或顶层平台地址图。

## 10. 本地操作记录

每次具有诊断价值的操作写入 `D:\Develop\AI\codex操作记录\riscv\YYYY-MM-DD-中文名称.md`。记录应能让另一位开发者在原生 Windows 上重放：工作区提交、工具版本、PowerShell 命令、输入文件哈希、关键日志摘要、验证结论和后续行动。敏感凭据、用户目录枚举和与挑战无关的系统信息不得写入记录。
