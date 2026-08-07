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
    $WorkRoot = 'D:\Develop\AI\codex-work\riscv'
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
$fileList = 'rtl/files.f'
$tests = @(
  @{ Top = 'tb_rv64_core';  File = 'sim/tb_rv64_core.sv' },
  @{ Top = 'tb_rv64m_core'; File = 'sim/tb_rv64m_core.sv' },
  @{ Top = 'tb_rv64a_core'; File = 'sim/tb_rv64a_core.sv' },
  @{ Top = 'tb_rv64c_core'; File = 'sim/tb_rv64c_core.sv' },
  @{ Top = 'tb_rv64c_illegal'; File = 'sim/tb_rv64c_illegal.sv' }
)

Push-Location $repoRoot
try {
  Write-Host ('Verilator: {0}' -f $verilator.Source)
  & $verilator.Source '--version'
  if ($LASTEXITCODE -ne 0) { throw "verilator version query failed with exit code $LASTEXITCODE" }
  if ($LintOnly) {
    foreach ($test in $tests) {
      Write-Host ('Lint: {0}' -f $test.Top)
      & $verilator.Source '--lint-only' '--Wall' '--Wno-fatal' '--timing' '--top-module' $test.Top '-f' $fileList $test.File
      if ($LASTEXITCODE -ne 0) { throw "verilator lint failed for $($test.Top) with exit code $LASTEXITCODE" }
    }
    Write-Host 'Verilator RV64I/RV64M/RV64A/RV64C lint completed successfully.'
    return
  }

  if ($null -eq (Get-Command make -ErrorAction SilentlyContinue)) {
    if ($verilator.Name -ne 'verilator_bin.exe') {
      throw 'make was not found on PATH; install the build tool required by Verilator.'
    }
    $mingwBin = Split-Path $verilator.Source
    $msysRoot = [IO.Path]::GetFullPath((Join-Path $mingwBin '..\..'))
    $msysBin = Join-Path $msysRoot 'usr\bin'
    $nativeMake = Join-Path $msysBin 'make.exe'
    if (-not (Test-Path -LiteralPath $nativeMake)) {
      throw "MSYS2 make was not found at $nativeMake"
    }
    $env:Path = $mingwBin + [IO.Path]::PathSeparator +
                $msysBin + [IO.Path]::PathSeparator + $env:Path
  }

  foreach ($test in $tests) {
    $mdir = [IO.Path]::GetFullPath((Join-Path $outputRoot ($test.Top + '_obj_dir')))
    $outputPrefix = [IO.Path]::GetFullPath($outputRoot).TrimEnd('\', '/') +
                    [IO.Path]::DirectorySeparatorChar
    if (-not $mdir.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
      throw "refusing to clean build directory outside $outputRoot`: $mdir"
    }
    if (Test-Path -LiteralPath $mdir) {
      Remove-Item -LiteralPath $mdir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $mdir | Out-Null
    Write-Host ('Build: {0}' -f $test.Top)
    & $verilator.Source '--binary' '--timing' '--Wall' '--Wno-fatal' '--top-module' $test.Top '--Mdir' $mdir '-f' $fileList $test.File
    if ($LASTEXITCODE -ne 0) { throw "verilator build failed for $($test.Top) with exit code $LASTEXITCODE" }

    $executableName = 'V' + $test.Top
    $exe = Get-ChildItem -LiteralPath $mdir -File -Filter ($executableName + '*') |
      Where-Object { $_.Extension -in @('', '.exe') } |
      Select-Object -First 1
    if ($null -eq $exe) { throw "Verilator build did not produce $executableName in $mdir" }
    & $exe.FullName
    if ($LASTEXITCODE -ne 0) { throw "Verilator simulation failed for $($test.Top) with exit code $LASTEXITCODE" }
  }
} finally {
  Pop-Location
}

Write-Host 'Verilator RV64I/RV64M/RV64A/RV64C smoke tests completed successfully.'
