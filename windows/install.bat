@echo off
chcp 65001 >nul
rem Right-click -> Run as administrator
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
