@echo off
powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File \"%~dp0wifi-watchdog.ps1\"' -Verb RunAs"
