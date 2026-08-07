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
	$(PYTHON) tests/gen_rv64i_smoke.py
	$(PYTHON) tests/gen_rv64m_smoke.py
	$(PYTHON) tests/gen_rv64a_smoke.py
	$(PYTHON) tests/gen_rv64c_smoke.py
	$(PYTHON) -m unittest discover -s tests -p "test_*.py"

lint:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File scripts/run-verilator.ps1 -LintOnly

iverilog:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File scripts/run-iverilog.ps1

verilator:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File scripts/run-verilator.ps1
