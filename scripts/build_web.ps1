[CmdletBinding()]
param(
    [string]$GodotExe = $env:GODOT_EXE,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$taskProjectRoot = Split-Path -Parent $PSScriptRoot
$taskBuildRoot = Join-Path $taskProjectRoot 'build'
$taskWebRoot = Join-Path $taskBuildRoot 'web'
$taskLogRoot = Join-Path $taskBuildRoot 'logs'

if (-not $GodotExe) {
    $taskGodotCommand = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($taskGodotCommand) {
        $GodotExe = $taskGodotCommand.Source
    } else {
        $GodotExe = Join-Path $env:USERPROFILE 'Downloads\Godot_v4.5.1-stable_win64.exe\Godot_v4.5.1-stable_win64_console.exe'
    }
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw 'Godot was not found. Set GODOT_EXE to the Godot 4.5.1 console executable, or pass -GodotExe.'
}
$taskGodotVersion = (& $GodotExe --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $taskGodotVersion -notmatch '^4\.5\.1\.stable') {
    throw "This project requires Godot 4.5.1.stable; found '$taskGodotVersion'."
}
Write-Host "Building NIGHT SCHOOL with Godot $taskGodotVersion"

New-Item -ItemType Directory -Path $taskWebRoot, $taskLogRoot -Force | Out-Null
Set-Content -LiteralPath (Join-Path $taskBuildRoot '.gdignore') -Value '' -Encoding ascii
# Only generated output in this project's exact build/web directory is replaced.
$taskResolvedWebRoot = [IO.Path]::GetFullPath($taskWebRoot).TrimEnd('\', '/')
$taskExpectedWebRoot = [IO.Path]::GetFullPath((Join-Path $taskProjectRoot 'build\web')).TrimEnd('\', '/')
if ($taskResolvedWebRoot -ne $taskExpectedWebRoot) {
    throw 'Refusing to clean an output directory outside build/web.'
}
foreach ($taskOutputDirectory in @($taskBuildRoot, $taskWebRoot)) {
    if ((Get-Item -LiteralPath $taskOutputDirectory).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Refusing to clean a build directory that redirects to another location.'
    }
}
function Invoke-GodotPhase {
    param([string]$Name, [string[]]$GodotArguments)
    $taskLogPath = Join-Path $taskLogRoot ($Name + '.log')
    $taskEngineLogPath = Join-Path $taskLogRoot ($Name + '.engine.log')
    Write-Host "Running $Name"
    # Godot can report script failures while still returning exit code zero.
    # Capture both streams and reject such builds before uploading anything.
    & $GodotExe --headless --path $taskProjectRoot --log-file $taskEngineLogPath @GodotArguments 2>&1 |
        Tee-Object -FilePath $taskLogPath | ForEach-Object { Write-Host $_ }
    $taskExitCode = $LASTEXITCODE
    if ($taskExitCode -ne 0) {
        throw "Godot $Name failed with exit code $taskExitCode. See $taskLogPath"
    }
    if (Select-String -LiteralPath $taskLogPath -Pattern 'SCRIPT ERROR:|^ERROR:|Parse Error:|Failed to load script' -Quiet) {
        throw "Godot $Name reported an error. See $taskLogPath"
    }
}

Invoke-GodotPhase -Name 'import' -GodotArguments @('--editor', '--import')
if (-not $SkipTests) {
    $taskTestsRoot = Join-Path $taskProjectRoot 'tests'
    $taskTestFiles = @(Get-ChildItem -LiteralPath $taskTestsRoot -Filter 'test_*.gd' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    $taskSmokeTest = Join-Path $taskTestsRoot 'smoke_test.gd'
    if (Test-Path -LiteralPath $taskSmokeTest) {
        $taskTestFiles += Get-Item -LiteralPath $taskSmokeTest
    }
    if ($taskTestFiles.Count -eq 0) {
        throw 'No headless tests were found. Expected tests/test_*.gd or tests/smoke_test.gd.'
    }
    foreach ($taskTestFile in $taskTestFiles) {
        Invoke-GodotPhase -Name $taskTestFile.BaseName -GodotArguments @('--script', ('res://tests/' + $taskTestFile.Name))
    }
}

# Preserve the last working local preview if import or tests fail.
foreach ($taskGeneratedItem in Get-ChildItem -LiteralPath $taskResolvedWebRoot -Force) {
    Remove-Item -LiteralPath $taskGeneratedItem.FullName -Recurse -Force
}
Invoke-GodotPhase -Name 'export' -GodotArguments @('--export-release', 'Web', (Join-Path $taskWebRoot 'index.html'))
foreach ($taskRequiredFile in @('index.html', 'index.js', 'index.wasm', 'index.pck')) {
    $taskOutputFile = Join-Path $taskWebRoot $taskRequiredFile
    if (-not (Test-Path -LiteralPath $taskOutputFile) -or (Get-Item -LiteralPath $taskOutputFile).Length -eq 0) {
        throw "The export did not produce a valid $taskRequiredFile."
    }
}
Set-Content -LiteralPath (Join-Path $taskWebRoot '.nojekyll') -Value '' -Encoding ascii
$taskBuildBytes = (Get-ChildItem -LiteralPath $taskWebRoot -File | Measure-Object -Property Length -Sum).Sum
Write-Host ('Web export ready: {0} ({1:N1} MB)' -f $taskWebRoot, ($taskBuildBytes / 1MB))
