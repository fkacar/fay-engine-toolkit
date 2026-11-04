@echo off
rem hlimgui eklentisini Windows x64 icin derler. CMake ve Visual Studio gerekir.
setlocal
cd /d "%~dp0..\..\.."

if not exist ".hashlink\hl.exe" (
  echo Once run.bat build calistir, HashLink indirilsin.
  exit /b 1
)

set HASHLINKPATH=%CD%\.hashlink
if exist "libs\scene-toolkit\third_party\hlimgui\extension\lib\imgui\imgui.h" goto sources_ready
git -C libs/scene-toolkit submodule update --init --recursive third_party/hlimgui
if errorlevel 1 exit /b 1
:sources_ready

rem Arac takiminin sarmalayicisi: hlimgui ve yerel ek (kare korumasi, editor\native).
cmake -S libs\scene-toolkit\tools\hlimgui -B bin\hlimgui-build -A x64
if errorlevel 1 exit /b 1
cmake --build bin\hlimgui-build --config Release
if errorlevel 1 exit /b 1

copy /y bin\hlimgui-build\out\hlimgui.hdll .hashlink\ >nul
if errorlevel 1 exit /b 1
rem Surum damgasi: run.bat eski hdll'i tanir.
copy /y libs\scene-toolkit\tools\hlimgui-surum.txt .hashlink\ >nul
if errorlevel 1 exit /b 1
echo Hazir: .hashlink\hlimgui.hdll
