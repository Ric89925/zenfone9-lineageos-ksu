@echo off
rem zf9-sync.cmd - double-click or run from cmd/PowerShell; no execution-policy change needed.
rem After KonaBess / KernelSU Next changes: re-sign vbmeta for the live boot chain.
cd /d "%~dp0"
py -3 scripts\install_lineage_locked.py sync %*
pause
