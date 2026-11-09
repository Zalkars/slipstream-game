@echo off
setlocal EnableExtensions DisableDelayedExpansion

title SLIPSTREAM - Android release build

set "ROOT_DIR=%~dp0"
set "PROJECT_DIR=%ROOT_DIR%godot"
set "OUTPUT_APK=%ROOT_DIR%Slipstream-0.5.1.apk"
set "GODOT_EXE="

echo ===================================================
echo        SLIPSTREAM - Android release build
echo ===================================================
echo.

if not exist "%PROJECT_DIR%\project.godot" (
    set "FAIL_MESSAGE=Godot project not found: %PROJECT_DIR%\project.godot"
    goto :fail
)

rem Prefer an explicitly configured executable, known local installs, then PATH.
if defined GODOT_BIN if exist "%GODOT_BIN%" set "GODOT_EXE=%GODOT_BIN%"
if not defined GODOT_EXE if exist "%ROOT_DIR%tools\godot\Godot_v4.3-stable_win64_console.exe" set "GODOT_EXE=%ROOT_DIR%tools\godot\Godot_v4.3-stable_win64_console.exe"
if not defined GODOT_EXE if exist "D:\DS\Work\Projects\Last Hook\tools\godot\Godot_v4.7.2-stable_win64_console.exe" set "GODOT_EXE=D:\DS\Work\Projects\Last Hook\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if not defined GODOT_EXE for %%G in (godot.exe godot4.exe) do if not defined GODOT_EXE (
    for /f "delims=" %%P in ('where %%G 2^>nul') do if not defined GODOT_EXE set "GODOT_EXE=%%P"
)

if not defined GODOT_EXE (
    set "FAIL_MESSAGE=Godot executable was not found. Set GODOT_BIN to the Godot 4.3 console executable, or add Godot to PATH."
    goto :fail
)

echo [OK] Godot: %GODOT_EXE%
if not defined ANDROID_HOME if exist "D:\DS\Work\Projects\Last Hook\tools\android-sdk" set "ANDROID_HOME=D:\DS\Work\Projects\Last Hook\tools\android-sdk"
if defined ANDROID_HOME set "ANDROID_SDK_ROOT=%ANDROID_HOME%"
if defined JAVA_HOME echo [OK] JAVA_HOME: %JAVA_HOME%
if defined ANDROID_HOME echo [OK] ANDROID_HOME: %ANDROID_HOME%
if not defined JAVA_HOME echo [INFO] JAVA_HOME is not set; using the Java path configured in Godot.
if not defined ANDROID_HOME echo [INFO] ANDROID_HOME is not set; using the SDK path configured in Godot.
echo.

echo Importing project resources...
"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --import
if errorlevel 1 (
    set "FAIL_MESSAGE=Godot resource import failed."
    goto :fail
)

echo.
echo Exporting Android release APK...
echo Output: %OUTPUT_APK%
"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --export-release "Android" "%OUTPUT_APK%"
if errorlevel 1 (
    set "FAIL_MESSAGE=Godot Android release export failed."
    goto :fail
)

if not exist "%OUTPUT_APK%" (
    set "FAIL_MESSAGE=Export finished without creating the APK."
    goto :fail
)

for %%F in ("%OUTPUT_APK%") do set "APK_SIZE=%%~zF"
echo.
echo ===================================================
echo [SUCCESS] Release APK created.
echo File: %OUTPUT_APK%
echo Size: %APK_SIZE% bytes
echo ===================================================
set "EXIT_CODE=0"
goto :finish

:fail
echo.
echo [ERROR] %FAIL_MESSAGE%
set "EXIT_CODE=1"
goto :finish

:finish
if /i not "%CI%"=="true" if /i not "%CI%"=="1" pause
exit /b %EXIT_CODE%
