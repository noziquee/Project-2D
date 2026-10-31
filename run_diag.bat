@echo off
set GODOT="C:\Users\Nozique\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
echo Using %GODOT%
%GODOT% --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd > run.log 2>&1
findstr /C:"SUMMARY" /C:"CHECK FAIL" /C:"DIAG" /C:"UNEXPECTED ERROR" run.log > run_diag.log
findstr /C:"SUMMARY" run_diag.log
echo Done. Upload run_diag.log
