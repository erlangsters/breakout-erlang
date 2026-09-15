$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

if (-not $env:VCPKG_ROOT) {
    if ($env:VCPKG_INSTALLATION_ROOT) {
        $env:VCPKG_ROOT = $env:VCPKG_INSTALLATION_ROOT
    } elseif (Test-Path "C:\vcpkg\scripts\buildsystems\vcpkg.cmake") {
        $env:VCPKG_ROOT = "C:\vcpkg"
    } elseif (Test-Path "C:\tools\vcpkg\scripts\buildsystems\vcpkg.cmake") {
        $env:VCPKG_ROOT = "C:\tools\vcpkg"
    }
}

$vsCMake = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"
if (Test-Path $vsCMake) {
    $env:PATH = "$vsCMake;$env:PATH"
}

$vcvars = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
if ((Get-Command cl -ErrorAction SilentlyContinue) -eq $null -and (Test-Path $vcvars)) {
    cmd /c "`"$vcvars`" >nul && set" | ForEach-Object {
        if ($_ -match "^(.*?)=(.*)$") {
            [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2])
        }
    }
}

rebar3 compile

$BuildDir = Join-Path $Root "_build\default"
$PaArgs = @()
Get-ChildItem -Path (Join-Path $BuildDir "lib") -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $ebin = Join-Path $_.FullName "ebin"
    if (Test-Path $ebin) {
        $PaArgs += "-pa"
        $PaArgs += $ebin
    }
    $priv = Join-Path $_.FullName "priv"
    if (Test-Path $priv) {
        $env:PATH = "$priv;$env:PATH"
    }
}

if ($env:ANGLE_LIB_DIR) {
    $angleBin = Join-Path (Split-Path $env:ANGLE_LIB_DIR -Parent) "bin"
    if (Test-Path $angleBin) {
        $env:PATH = "$angleBin;$env:PATH"
    }
}

if ($PaArgs.Count -eq 0) {
    Write-Error "Unable to locate compiled application ebin directories"
}

$erlArgs = @("-noshell") + $PaArgs + @("-s", "breakout", "start", "-s", "erlang", "halt")
& erl @erlArgs
exit $LASTEXITCODE
