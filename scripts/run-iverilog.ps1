[CmdletBinding()]
param(
  [string]$WorkRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($WorkRoot)) {
  if (-not [string]::IsNullOrWhiteSpace($env:RISCV_WORK_ROOT)) {
    $WorkRoot = $env:RISCV_WORK_ROOT
  } else {
    $WorkRoot = 'D:\Develop\AI\codex-work\riscv'
  }
}

$iverilog = Get-Command iverilog -ErrorAction SilentlyContinue
$vvp = Get-Command vvp -ErrorAction SilentlyContinue
if ($null -eq $iverilog) { throw 'iverilog was not found on PATH; install native Windows Icarus Verilog first.' }
if ($null -eq $vvp) { throw 'vvp was not found on PATH; install native Windows Icarus Verilog first.' }

$outputRoot = Join-Path ([IO.Path]::GetFullPath($WorkRoot)) 'iverilog'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$fileList = 'rtl/files.f'
$tests = @(
  @{ Top = 'tb_rv64_core';  File = 'sim/tb_rv64_core.sv';  Output = 'rv64i_smoke.vvp' },
  @{ Top = 'tb_rv64m_core'; File = 'sim/tb_rv64m_core.sv'; Output = 'rv64m_smoke.vvp' },
  @{ Top = 'tb_rv64a_core'; File = 'sim/tb_rv64a_core.sv'; Output = 'rv64a_smoke.vvp' },
  @{ Top = 'tb_rv64c_core'; File = 'sim/tb_rv64c_core.sv'; Output = 'rv64c_smoke.vvp' },
  @{ Top = 'tb_rv64c_illegal'; File = 'sim/tb_rv64c_illegal.sv'; Output = 'rv64c_illegal.vvp' },
  @{ Top = 'tb_precise_trap'; File = 'sim/tb_precise_trap.sv'; Output = 'precise_trap.vvp' }
)

Push-Location $repoRoot
try {
  Write-Host ('Icarus: {0}' -f $iverilog.Source)
  & $iverilog.Source '-V'
  if ($LASTEXITCODE -ne 0) { throw "iverilog version query failed with exit code $LASTEXITCODE" }
  Write-Host ('VVP: {0}' -f $vvp.Source)
  & $vvp.Source '-V'
  if ($LASTEXITCODE -ne 0) { throw "vvp version query failed with exit code $LASTEXITCODE" }
  foreach ($test in $tests) {
    $outputFile = Join-Path $outputRoot $test.Output
    Write-Host ('Test: {0}' -f $test.Top)
    Write-Host ('Output: {0}' -f $outputFile)
    & $iverilog.Source '-g2012' '-s' $test.Top '-f' $fileList '-o' $outputFile $test.File
    if ($LASTEXITCODE -ne 0) { throw "iverilog failed for $($test.Top) with exit code $LASTEXITCODE" }

    & $vvp.Source $outputFile
    if ($LASTEXITCODE -ne 0) { throw "vvp failed for $($test.Top) with exit code $LASTEXITCODE" }
  }
} finally {
  Pop-Location
}

Write-Host 'Icarus RV64I/RV64M/RV64A/RV64C and precise-trap tests completed successfully.'
