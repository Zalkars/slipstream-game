@echo off
setlocal enabledelayedexpansion
title Building SLIPSTREAM APK

echo ===================================================
echo        SLIPSTREAM - Android APK Build Tool
echo ===================================================
echo.

set "SCRIPT_DIR=%~dp0"
set "GODOT_DIR=%SCRIPT_DIR%godot"
set "OUTPUT_APK=%SCRIPT_DIR%Slipstream-0.2.1.apk"

:: 1. Setup Java JDK
if not defined JAVA_HOME (
    if exist "C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot" (
        set "JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot"
    )
)

if not exist "!JAVA_HOME!\bin\java.exe" (
    echo [ERROR] JDK not found at !JAVA_HOME!
    echo Please install Java 17+ or set JAVA_HOME.
    pause
    exit /b 1
)

set "PATH=!JAVA_HOME!\bin;!PATH!"
echo [OK] Using Java from: !JAVA_HOME!

:: 2. Setup Android SDK
if not defined ANDROID_HOME (
    if exist "D:\DS\Work\Projects\Last Hook\tools\android-sdk" (
        set "ANDROID_HOME=D:\DS\Work\Projects\Last Hook\tools\android-sdk"
    )
)
if defined ANDROID_HOME (
    set "ANDROID_SDK_ROOT=!ANDROID_HOME!"
    echo [OK] Using Android SDK: !ANDROID_HOME!
)

:: 3. Find Godot executable
set "GODOT_EXE="
if defined GODOT_BIN if exist "!GODOT_BIN!" set "GODOT_EXE=!GODOT_BIN!"
if not defined GODOT_EXE if exist "D:\DS\Work\Projects\Last Hook\tools\godot\Godot_v4.7.2-stable_win64_console.exe" (
    set "GODOT_EXE=D:\DS\Work\Projects\Last Hook\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
)
if not defined GODOT_EXE (
    for %%X in (godot.exe godot4.exe) do (
        if not defined GODOT_EXE (
            set "GODOT_EXE=%%~$PATH:X"
        )
    )
)

if not exist "!GODOT_EXE!" (
    echo [ERROR] Godot executable not found!
    echo Please set GODOT_BIN environment variable or place Godot in tools directory.
    pause
    exit /b 1
)

echo [OK] Using Godot: !GODOT_EXE!
echo.
echo ---------------------------------------------------
echo Exporting Android Release APK...
echo Output: !OUTPUT_APK!
echo ---------------------------------------------------
echo.

"!GODOT_EXE!" --headless --path "!GODOT_DIR!" --export-release "Android" "!OUTPUT_APK!"
if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] Export failed with error code %ERRORLEVEL%!
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo ===================================================
echo [SUCCESS] APK built and signed successfully!
echo File: !OUTPUT_APK!
echo ===================================================
echo.

pause
