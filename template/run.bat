@echo off
cd /d "%~dp0"
if not exist "libs\scene-toolkit\tools\run.bat" git submodule update --init --recursive
call "libs\scene-toolkit\tools\run.bat" %*
exit /b %errorlevel%
