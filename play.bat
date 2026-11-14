@echo off
rem Starts the game.
set GODOT=C:\Users\Martin\Programming\Projects\Games\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64.exe
cd /d "%~dp0"
start "" "%GODOT%" --path . -- %*
