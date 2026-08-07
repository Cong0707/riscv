# Berkeley HardFloat Release 1

本目录固定保存 Berkeley HardFloat Release 1 的 RISC-V Verilog 源码闭包，用于本项目的 RV64F/RV64D 可综合浮点执行单元。

## 来源

```text
上游：https://www.jhauser.us/arithmetic/HardFloat-1.zip
发行日期：2019-07-29
归档大小：286959 字节
SHA-256：6B3757C9FBFA2230C6A2B84605E39372CB589DD7500E979C4F0B8ECC8A03B14B
许可证：三条款 BSD 风格许可证，见 COPYING.txt
```

只保留 RV64F/RV64D 所需的公共模块、RISC-V specialization、IEEE/recoded 格式转换、整数转换、加减、乘法、融合乘加、除法/平方根和比较模块。`source/RISCV` 必须先于 `source` 进入 include 搜索路径。

## 本地补丁

`source/divSqrtRecFN_small.v` 删除了 `output sqrtOpOut` 之后的冗余 `wire sqrtOpOut` 声明。该声明在 Verilator 中可接受，但 Icarus 12 会报告同一作用域重复声明；删除不会改变端口类型或逻辑。

除这一行外，源文件保持上游 Release 1 内容。Verilator 的上游风格告警仅通过 `hardfloat.vlt` 对本目录路径豁免，不全局关闭项目 RTL 的位宽检查。
