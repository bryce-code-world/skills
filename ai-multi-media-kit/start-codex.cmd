@echo off
chcp 65001 >nul
cd /d "%~dp0"
where codex >nul 2>&1
if errorlevel 1 (
 echo [ERROR] Codex CLI was not found in PATH.
 echo Install and sign in to Codex, then run this launcher again.
 exit /b 1
)
codex
