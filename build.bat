@echo off
rem Builds the tool and its tests.
rem
rem Finds RAD Studio in the usual places. Set BDS yourself if yours is elsewhere:
rem   set BDS=D:\Embarcadero\Studio\37.0
if not "%BDS%"=="" goto :haveBds
if exist "%ProgramFiles(x86)%\Embarcadero\Studio\37.0\bin\rsvars.bat" set BDS=%ProgramFiles(x86)%\Embarcadero\Studio\37.0
if not "%BDS%"=="" goto :haveBds
if exist "%ProgramFiles%\Embarcadero\Studio\37.0\bin\rsvars.bat" set BDS=%ProgramFiles%\Embarcadero\Studio\37.0
:haveBds
if not exist "%BDS%\bin\rsvars.bat" (
  echo Could not find RAD Studio 37.0 ^(Delphi 13^).
  echo Set BDS to the install folder, for example:
  echo   set BDS=D:\Embarcadero\Studio\37.0
  exit /b 1
)
call "%BDS%\bin\rsvars.bat"
if errorlevel 1 exit /b 1

set CONFIG=%1
if "%CONFIG%"=="" set CONFIG=Debug
set PLATFORM=%2
if "%PLATFORM%"=="" set PLATFORM=Win32

msbuild "%~dp0Source\DelphiUsesAnalyzer.dproj" /t:Build /p:Config=%CONFIG% /p:Platform=%PLATFORM% /v:minimal /nologo
if errorlevel 1 exit /b 1
msbuild "%~dp0Tests\DelphiUsesAnalyzer.Tests.dproj" /t:Build /p:Config=%CONFIG% /p:Platform=%PLATFORM% /v:minimal /nologo
if errorlevel 1 exit /b 1
echo BUILD OK
