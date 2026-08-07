.DEFAULT_GOAL := test
.PHONY: test image lint iverilog verilator

PYTHON ?= python
ifeq ($(OS),Windows_NT)
POWERSHELL ?= powershell.exe
else
POWERSHELL ?= pwsh
endif

test: image verilator

image:
	$(PYTHON) -m unittest discover -s tests -p "test_*.py"

lint:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File scripts/run-verilator.ps1 -LintOnly

iverilog:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File scripts/run-iverilog.ps1

verilator:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File scripts/run-verilator.ps1
