# RV64 处理器工程

这是一个从 `RV64I` 起步、面向 `RV64GC`、特权架构、`Sv39` 和 Linux/Ubuntu 启动的 SystemVerilog 处理器项目。当前已形成可运行的 `RV64IMAC` 功能基线，并在其上接入 `RV64F/RV64D` 非特权浮点执行路径、`FLEN=64` 浮点寄存器堆和最小 `fflags/frm/fcsr` 状态闭环。核心采用现代改进哈佛结构，拥有独立 32 位取指端口和独立 64 位数据端口；更高层计划接入独立 I/D cache、MMU、DRAM 控制器、MMIO fabric 和块设备/DMA。当前实现仍不等于完整 `RV64GC`、特权系统或 Ubuntu 可启动平台。

## 当前交付

- `rtl/rv64_core.sv`：五级 `IF/ID/EX/MEM/WB`、单发射、顺序提交的 RV64IMAC 核心，并已接入 RV64F/RV64D 非特权执行、浮点访存、前递、阻塞和有序写回路径。
- `rtl/rv64_decoder.sv`、`rtl/rv64_imm_gen.sv`、`rtl/rv64_alu.sv`、`rtl/rv64_regfile.sv`：整数基础数据通路、F/D 指令解码以及仅限 `fflags/frm/fcsr` 的最小 CSR 解码。
- `rtl/rv64_fregfile.sv`：32 x 64 位、三读一写的 `FLEN=64` 浮点寄存器堆；`f0` 是普通浮点寄存器。
- `rtl/rv64_fpu.sv`：基于 Berkeley HardFloat 的阻塞式 RV64F/RV64D 执行包装器，覆盖算术、融合乘加、除法/平方根、比较、分类、格式转换、整数转换、原始位移动、NaN-boxing 和异常标志映射。
- `rtl/rv64_mdu.sv`：覆盖全部 RV64M 64 位与 W 类乘除指令的握手式运算单元。
- `rtl/rv64_amo.sv`：覆盖 LR/SC 和全部基础 AMO W/D 形式的单核阻塞式原子单元。
- `rtl/rv64c_decompressor.sv`：覆盖 RV64C 整数形式、HINT、保留编码分类以及 `C.FLD/C.FSD/C.FLDSP/C.FSDSP` 的 16 位解压器。
- `third_party/berkeley-hardfloat`：固定版本的 Berkeley HardFloat Release 1 RISC-V Verilog 源码、许可证和原生 Windows 工具兼容补丁；既保留独立 vendor 回归，也已经由 `rtl/rv64_fpu.sv` 接入核心浮点执行路径。
- `sim/tb_rv64_fpu.sv`：F/D 执行包装器定向自检，包括多周期请求输入锁存。
- `sim/tb_rv64fd_core.sv`：浮点访存、流水冒险、算术、格式转换、`fflags/frm/fcsr` 和动态舍入的核心级端到端自检。
- `sim/tb_rv64fd_trap.sv`：动态保留舍入模式、浮点有序退休和浮点访存未对齐的精确异常自检。
- `sim/tb_rv64cd_decompressor.sv`：RV64C+D 压缩浮点访存解压自检。
- `sim/tb_rv64_core.sv`、`sim/tb_rv64m_core.sv`、`sim/tb_rv64a_core.sv`、`sim/tb_rv64c_core.sv`、`sim/tb_rv64c_illegal.sv`、`sim/tb_precise_trap.sv`：既有整数、原子、压缩和精确异常回归。
- `tests/gen_rv64i_smoke.py`、`tests/gen_rv64m_smoke.py`、`tests/gen_rv64a_smoke.py`、`tests/gen_rv64c_smoke.py`：不依赖交叉 GCC 的小端镜像生成器。
- `docs/architecture.zh-CN.md`：架构契约与接口边界。
- `docs/roadmap.zh-CN.md`：从 RV64I 到 Ubuntu 的阶段验收路线图。

当前 A 扩展只保证单核、阻塞式 D-port 且无外部 DMA/其他总线主设备并发时的功能原子性；系统级原子总线属性仍待后续互连阶段实现。C 扩展已覆盖 RV64 整数压缩形式，并在 D 扩展接入后启用 `C.FLD/C.FSD/C.FLDSP/C.FSDSP`。F/D 当前已实现浮点寄存器、访存、基本算术、真正融合的乘加、除法/平方根、比较、分类、S/D 与整数格式转换、原始位移动、NaN-boxing、静态/动态舍入和 `NV/DZ/OF/UF/NX` 累积；`fflags/frm/fcsr` 只构成满足当前浮点数据通路需要的最小 CSR 闭环，不代表完整 `Zicsr`。当前尚未实现 `mstatus.FS/SD`、完整特权 CSR、MMU/Sv39、缓存与平台设备，也尚未通过官方 `rv64uf/rv64ud` 或 Spike/TestFloat 全量差分，因此只能称为 RV64GC 用户态执行基线的重要组成部分，仍不能宣称完整 `RV64GC` 或 Ubuntu 可启动。

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

当前 F/D 定向回归包括：

- `RV64F/D wrapper PASS: completed=36`
- `RV64FD core PASS: cycles=107 reads=4 writes=15`
- `RV64F/D precise trap PASS: completed=6`
- `RV64C+D decompressor PASS: completed=7`

这些是项目自建定向测试，不替代官方 RISC-V ISA 测试、Berkeley TestFloat 或 Spike 差分。

仿真中间文件、波形和覆盖率数据库放在 `D:\Develop\AI\codex-work\riscv`，不进入 Git。阶段性操作记录放在 `D:\Develop\AI\codex操作记录\riscv`，文件名使用“日期+中文名称”。

## Git 工作流

- 项目只维护 `main` 分支，所有阶段性工作直接形成小而可验证的中文提交。
- 每次提交前必须运行受影响的 Python 回归、Verilator lint 和可用的 RTL 仿真。
- 未通过当前验收门的代码不得提交；实验性草稿只放在仓外临时目录。

详细规则见 `CONTRIBUTING.md`，架构变更必须同步更新 `docs/architecture.zh-CN.md` 和 `docs/roadmap.zh-CN.md`。
