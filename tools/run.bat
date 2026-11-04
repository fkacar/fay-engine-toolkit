@echo off
rem Eksik kutuphaneleri ve HashLink'i kurar, derler ve calistirir.
rem Oyun: run.bat       Editor: run.bat editor       Testler: run.bat test
rem Yalnizca derlemek icin sona build eklenir: run.bat build, run.bat editor build
setlocal
cd /d "%~dp0..\..\.."

set HAXE_SERIES=4.3
set HL_DIR=.hashlink
set HL_NAME=hashlink-1.16.0-win
set HL_URL=https://github.com/HaxeFoundation/hashlink/releases/download/1.16/%HL_NAME%.zip
set HXML=build.hxml
set BYTECODE=bin\game.hl
set TESTS=
if /i "%~1"=="editor" (
  set HXML=editor.hxml
  set BYTECODE=bin\editor.hl
  shift
)
if /i "%~1"=="test" (
  set HXML=libs\scene-toolkit\tests-hl.hxml
  set BYTECODE=bin\tests.hl
  set TESTS=1
  shift
)
set HL_SHA256=EC80B5BFBE93AE497FF43CD72D5BB4D906DE3C6398839BA692FA28C47B54AA0F

where haxe >nul 2>nul
if errorlevel 1 (
  echo Haxe bulunamadi. %HAXE_SERIES% surumunu https://haxe.org/download/ adresinden kur.
  goto fail
)

set HAXE_VERSION=
for /f "delims=" %%V in ('haxe --version') do set HAXE_VERSION=%%V
echo %HAXE_VERSION%| findstr /b /c:"%HAXE_SERIES%." >nul
if errorlevel 1 echo Uyari: Haxe %HAXE_VERSION% kurulu, ekip %HAXE_SERIES% kullaniyor.

if exist "%HL_DIR%\hl.exe" goto hashlink_ready
echo HashLink indiriliyor...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $zip=Join-Path $env:TEMP '%HL_NAME%.zip'; Invoke-WebRequest '%HL_URL%' -OutFile $zip -UseBasicParsing; if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne '%HL_SHA256%') { throw 'SHA-256 uyusmuyor' }; Expand-Archive $zip -DestinationPath '%HL_DIR%-tmp' -Force; Move-Item '%HL_DIR%-tmp\%HL_NAME%' '%HL_DIR%'; Remove-Item '%HL_DIR%-tmp' -Recurse; Remove-Item $zip"
if errorlevel 1 goto fail
:hashlink_ready

rem Kutuphane surumleri common.hxml'de sabittir, burada tekrar yazilmaz.
set MISSING_LIB=
for /f "tokens=2" %%L in ('findstr /b /c:"-lib " common.hxml') do (
  call haxelib path %%L >nul 2>nul
  if errorlevel 1 set MISSING_LIB=1
)
if defined MISSING_LIB (
  call haxelib install common.hxml --always
  if errorlevel 1 goto fail
)

if /i "%HXML%"=="editor.hxml" if not exist "%HL_DIR%\hlimgui.hdll" (
  echo hlimgui eksik. Once libs\scene-toolkit\tools\build-hlimgui.bat calistir.
  goto fail
)

call haxe %HXML%
if errorlevel 1 goto fail

if /i "%~1"=="build" exit /b 0
"%HL_DIR%\hl.exe" %BYTECODE%
if errorlevel 1 exit /b %errorlevel%
rem Testlerde ardindan Heaps'in matematik turlerini isteyen testler (yorumlayicida, tests\heaps).
if defined TESTS call haxe libs\scene-toolkit\tests-heaps.hxml
exit /b %errorlevel%

:fail
echo.
echo Islem basarisiz. Yukaridaki hataya bak.
if /i not "%~1"=="build" pause
exit /b 1
