# RV64 处理器工程

这是一个从 `RV64I` 起步、面向 `RV64GC`、特权架构、`Sv39` 和 Linux/Ubuntu 启动的 SystemVerilog 处理器项目。当前第一阶段采用现代改进哈佛结构：核心拥有独立 32 位取指端口和独立 64 位数据端口；更高层计划接入独立 I/D cache、MMU、DRAM 控制器、MMIO fabric 和块设备/DMA。

## 当前交付

- `rtl/rv64_core.sv`：五级 `IF/ID/EX/MEM/WB`、单发射、顺序提交的 RV64I 核心。
- `rtl/rv64_decoder.sv`、`rv64_imm_gen.sv`、`rv64_alu.sv`、`rv64_regfile.sv`：基础整数指令通路。
- `sim/tb_rv64_core.sv`：独立 I/D 端口的自检测试平台。
- `tests/gen_rv64i_smoke.py`：不依赖交叉 GCC 的 RV64I 小端镜像生成器。
- `docs/architecture.zh-CN.md`：架构契约与接口边界。
- `docs/roadmap.zh-CN.md`：从 RV64I 到 Ubuntu 的阶段验收路线图。

目前尚未实现 `M/A/F/D/C`、`Zicsr/Zifencei`、M/S/U 特权模式、PMP、`Sv39`、cache、设备模型或 Linux 启动，因此不能宣称已经支持 `RV64GC` 或 Ubuntu。

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

- `main`：可复现、通过当前验收门的基线。
- `develop`：下一阶段集成分支。
- `feature/*`：单一功能工作分支；提交前必须运行 Python 回归和可用的 RTL 仿真。

详细规则见 `CONTRIBUTING.md`，架构变更必须同步更新 `docs/architecture.zh-CN.md` 和 `docs/roadmap.zh-CN.md`。
