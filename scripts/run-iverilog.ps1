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
    $WorkRoot = Join-Path $repoRoot 'build'
  }
}

$iverilog = Get-Command iverilog -ErrorAction SilentlyContinue
$vvp = Get-Command vvp -ErrorAction SilentlyContinue
if ($null -eq $iverilog) { throw 'iverilog was not found on PATH; install native Windows Icarus Verilog first.' }
if ($null -eq $vvp) { throw 'vvp was not found on PATH; install native Windows Icarus Verilog first.' }

$outputRoot = Join-Path ([IO.Path]::GetFullPath($WorkRoot)) 'iverilog'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$outputFile = Join-Path $outputRoot 'rv64_smoke.vvp'
$fileList = Join-Path $repoRoot 'rtl/files.f'
$testbench = Join-Path $repoRoot 'sim/tb_rv64_core.sv'

Push-Location $repoRoot
try {
  Write-Host ('Icarus: {0}' -f $iverilog.Source)
  & $iverilog.Source '-V'
  if ($LASTEXITCODE -ne 0) { throw "iverilog version query failed with exit code $LASTEXITCODE" }
  Write-Host ('VVP: {0}' -f $vvp.Source)
  & $vvp.Source '-V'
  if ($LASTEXITCODE -ne 0) { throw "vvp version query failed with exit code $LASTEXITCODE" }
  Write-Host ('Output: {0}' -f $outputFile)
  & $iverilog.Source '-g2012' '-s' 'tb_rv64_core' '-f' $fileList '-o' $outputFile $testbench
  if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }

  & $vvp.Source $outputFile
  if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}

Write-Host 'Icarus RV64I smoke test completed successfully.'
