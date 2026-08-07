# RV64 处理器工程

这是一个从 `RV64I` 起步、面向 `RV64GC`、特权架构、`Sv39` 和 Linux/Ubuntu 启动的 SystemVerilog 处理器项目。当前已形成可运行的 `RV64IMA` 功能基线，并采用现代改进哈佛结构：核心拥有独立 32 位取指端口和独立 64 位数据端口；更高层计划接入独立 I/D cache、MMU、DRAM 控制器、MMIO fabric 和块设备/DMA。

## 当前交付

- `rtl/rv64_core.sv`：五级 `IF/ID/EX/MEM/WB`、单发射、顺序提交的 RV64IMA 核心。
- `rtl/rv64_decoder.sv`、`rv64_imm_gen.sv`、`rv64_alu.sv`、`rv64_regfile.sv`：基础整数指令通路。
- `rtl/rv64_mdu.sv`：覆盖全部 RV64M 64 位与 W 类乘除指令的握手式运算单元。
- `rtl/rv64_amo.sv`：覆盖 LR/SC 和全部基础 AMO W/D 形式的单核阻塞式原子单元。
- `sim/tb_rv64_core.sv`、`sim/tb_rv64m_core.sv`、`sim/tb_rv64a_core.sv`：独立 I/D 端口的 RV64I/RV64M/RV64A 自检测试平台。
- `tests/gen_rv64i_smoke.py`、`tests/gen_rv64m_smoke.py`、`tests/gen_rv64a_smoke.py`：不依赖交叉 GCC 的小端镜像生成器。
- `docs/architecture.zh-CN.md`：架构契约与接口边界。
- `docs/roadmap.zh-CN.md`：从 RV64I 到 Ubuntu 的阶段验收路线图。

当前 A 扩展只保证单核、阻塞式 D-port 且无外部 DMA/其他总线主设备并发时的功能原子性；系统级原子总线属性仍待后续互连阶段实现。目前尚未实现 `F/D/C`、`Zicsr/Zifencei`、M/S/U 特权模式、PMP、`Sv39`、cache、设备模型或 Linux 启动，因此不能宣称已经支持 `RV64GC` 或 Ubuntu。

## 原生 Windows 验证

本项目不使用 WSL。Icarus 只用于短小冒烟回归，Verilator 是 CI 和后续工业级仿真的主工具。

```powershell
$env:RISCV_WORK_ROOT = 'D:\Develop\AI\codex-work\riscv'
$env:Path = 'C:\iverilog\bin;' + $env:Path
.\scripts\run-iverilog.ps1 -WorkRoot $env:RISCV_WORK_ROOT
```

Verilator 环境准备好后：

```powershell
.\scripts\run-verilator.ps1 -LintOnly -WorkRoot $env:RISCV_WORK_ROOT
.\scripts\run-verilator.ps1 -WorkRoot $env:RISCV_WORK_ROOT
```

Python 镜像回归不需要任何 HDL 模拟器：

```powershell
$env:PYTHONDONTWRITEBYTECODE = '1'
python -m unittest discover -s tests -p 'test_*.py' -v
```

仿真中间文件、波形和覆盖率数据库放在 `D:\Develop\AI\codex-work\riscv`，不进入 Git。阶段性操作记录放在 `D:\Develop\AI\codex操作记录\riscv`，文件名使用“日期+中文名称”。

## Git 工作流

- 项目只维护 `main` 分支，所有阶段性工作直接形成小而可验证的中文提交。
- 每次提交前必须运行受影响的 Python 回归、Verilator lint 和可用的 RTL 仿真。
- 未通过当前验收门的代码不得提交；实验性草稿只放在仓外临时目录。

详细规则见 `CONTRIBUTING.md`，架构变更必须同步更新 `docs/architecture.zh-CN.md` 和 `docs/roadmap.zh-CN.md`。
