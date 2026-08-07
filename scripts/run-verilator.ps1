[CmdletBinding()]
param(
  [string]$WorkRoot,
  [switch]$LintOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($WorkRoot)) {
  if (-not [string]::IsNullOrWhiteSpace($env:RISCV_WORK_ROOT)) {
    $WorkRoot = $env:RISCV_WORK_ROOT
  } else {
    $WorkRoot = Join-Path $repoRoot 'build'
  }
}

$verilator = Get-Command verilator_bin.exe -ErrorAction SilentlyContinue
if ($null -eq $verilator) { $verilator = Get-Command verilator.exe -ErrorAction SilentlyContinue }
if ($null -eq $verilator) { $verilator = Get-Command verilator -ErrorAction SilentlyContinue }
if ($null -eq $verilator) { throw 'verilator was not found on PATH; install a native Verilator toolchain first.' }
if (($verilator.Name -eq 'verilator_bin.exe') -and [string]::IsNullOrWhiteSpace($env:VERILATOR_ROOT)) {
  $nativeRoot = [IO.Path]::GetFullPath((Join-Path (Split-Path $verilator.Source) '..\share\verilator'))
  if (-not (Test-Path -LiteralPath $nativeRoot)) {
    throw "native Verilator data directory was not found at $nativeRoot"
  }
  $env:VERILATOR_ROOT = $nativeRoot
}

$outputRoot = Join-Path ([IO.Path]::GetFullPath($WorkRoot)) 'verilator'
$mdir = Join-Path $outputRoot 'obj_dir'
New-Item -ItemType Directory -Force -Path $mdir | Out-Null
$fileList = 'rtl/files.f'
$testbench = 'sim/tb_rv64_core.sv'

Push-Location $repoRoot
try {
  Write-Host ('Verilator: {0}' -f $verilator.Source)
  & $verilator.Source '--version'
  if ($LASTEXITCODE -ne 0) { throw "verilator version query failed with exit code $LASTEXITCODE" }
  if ($LintOnly) {
    & $verilator.Source '--lint-only' '--Wall' '--Wno-fatal' '--timing' '--top-module' 'tb_rv64_core' '-f' $fileList $testbench
    if ($LASTEXITCODE -ne 0) { throw "verilator lint failed with exit code $LASTEXITCODE" }
    Write-Host 'Verilator lint completed successfully.'
    return
  }

  & $verilator.Source '--binary' '--timing' '--Wall' '--Wno-fatal' '--top-module' 'tb_rv64_core' '--Mdir' $mdir '-f' $fileList $testbench
  if ($LASTEXITCODE -ne 0) { throw "verilator build failed with exit code $LASTEXITCODE" }

  $exe = Get-ChildItem -LiteralPath $mdir -File -Filter 'Vtb_rv64_core*' |
    Where-Object { $_.Extension -in @('', '.exe') } |
    Select-Object -First 1
  if ($null -eq $exe) { throw "Verilator build did not produce Vtb_rv64_core in $mdir" }
  & $exe.FullName
  if ($LASTEXITCODE -ne 0) { throw "Verilator simulation failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}

Write-Host 'Verilator RV64I smoke test completed successfully.'
