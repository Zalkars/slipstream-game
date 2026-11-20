# Installs the Godot 4.7.2 Android build template into godot/android/build
# (needed by gradle_build/use_gradle_build=true) and builds the SlipstreamAds
# Yandex Mobile Ads plugin AAR when it is missing or older than its Java source.
# Called by build_apk.bat; safe to run repeatedly.
param(
    [string]$GodotExe = $env:GODOT_EXE,
    [string]$AndroidSdkPath = $env:ANDROID_HOME,
    [string]$JavaSdkPath = $env:JAVA_HOME,
    [switch]$RebuildPlugin
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$project = Join-Path $root 'godot'
$build = Join-Path $project 'android\build'
$godotLibrary = Join-Path $build 'libs\debug\godot-lib.template_debug.aar'
$version = '4.7.2.stable'

if (-not $AndroidSdkPath) { $AndroidSdkPath = 'D:\DS\Work\Projects\Last Hook\tools\android-sdk' }
if (-not $JavaSdkPath) { $JavaSdkPath = 'C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot' }

# Export templates live next to a self-contained Godot (editor_data) or in %APPDATA%.
$templateDirs = @()
if ($GodotExe) { $templateDirs += Join-Path (Split-Path -Parent $GodotExe) "editor_data\export_templates\$version" }
$templateDirs += Join-Path $env:APPDATA "Godot\export_templates\$version"
$templateDirs += "D:\DS\Work\Projects\Last Hook\tools\godot\editor_data\export_templates\$version"
$sourceZip = $templateDirs | ForEach-Object { Join-Path $_ 'android_source.zip' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

$versionFile = Join-Path $project 'android\.build_version'
$installed = (Test-Path -LiteralPath $versionFile) -and ((Get-Content -Raw -LiteralPath $versionFile).Trim() -eq $version)
if (-not $installed -or -not (Test-Path -LiteralPath $godotLibrary)) {
    if (-not $sourceZip) { throw "Godot $version Android export templates (android_source.zip) were not found." }
    if (Test-Path -LiteralPath $build) { Remove-Item -LiteralPath $build -Recurse -Force }
    New-Item -ItemType Directory -Path $build -Force | Out-Null
    Expand-Archive -LiteralPath $sourceZip -DestinationPath $build -Force
    [IO.File]::WriteAllText($versionFile, $version, [Text.UTF8Encoding]::new($false))
    Write-Output "Installed Android build template $version from $sourceZip"
}
New-Item -ItemType File -Path (Join-Path $build '.gdignore') -Force | Out-Null

# Godot's export forks a single-use Gradle daemon (it passes JVM settings), and
# that daemon's default 512 MB heap is too small for Jetifier on the ~100 MB
# godot-lib AAR ("Java heap space"). Give it 4 GB; no persistent daemon.
$gradleProperties = Join-Path $build 'gradle.properties'
$gradleText = Get-Content -Raw -LiteralPath $gradleProperties
$jvmArgs = 'org.gradle.jvmargs=-Xmx4g -Dfile.encoding=UTF-8'
if ($gradleText -match '(?m)^org\.gradle\.jvmargs=') {
    $gradleText = [regex]::Replace($gradleText, '(?m)^org\.gradle\.jvmargs=.*$', $jvmArgs)
} else {
    $gradleText = $gradleText.TrimEnd() + "`n$jvmArgs`n"
}
if ($gradleText -match '(?m)^org\.gradle\.daemon=') {
    $gradleText = [regex]::Replace($gradleText, '(?m)^org\.gradle\.daemon=.*$', 'org.gradle.daemon=false')
} else {
    $gradleText = $gradleText.TrimEnd() + "`norg.gradle.daemon=false`n"
}
[IO.File]::WriteAllText($gradleProperties, $gradleText, [Text.UTF8Encoding]::new($false))

$plugin = Join-Path $project 'addons\slipstream_ads\bin\SlipstreamAds.aar'
$pluginSource = Join-Path $root 'tools\android-ads'
# The AAR is committed. Rebuild it when asked, when it is missing, or when the
# plugin source has uncommitted edits (file times are unreliable after checkout).
$sourceEdited = $false
try { $sourceEdited = [bool](git -C $root status --porcelain -- 'tools/android-ads/src' 'tools/android-ads/build.gradle') } catch {}
$needsBuild = $RebuildPlugin -or $sourceEdited -or -not (Test-Path -LiteralPath $plugin)
if ($needsBuild) {
    $env:JAVA_HOME = $JavaSdkPath
    $env:ANDROID_HOME = $AndroidSdkPath
    & (Join-Path $build 'gradlew.bat') --no-daemon --console=plain -p $pluginSource installPlugin
    if ($LASTEXITCODE -ne 0) { throw 'SlipstreamAds plugin build failed.' }
}
Write-Output 'Android build template and SlipstreamAds plugin are ready.'
