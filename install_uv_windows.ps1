#Requires -Version 5.1
<#
Installs uv for the Windows RFCOMM Python server.

Usage:
  powershell -ExecutionPolicy Bypass -File .\install_uv_windows.ps1
#>

[CmdletBinding()]
param(
    [string]$PythonVersion = "3.12",
    [string]$Proxy
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Add-UserPathEntries {
    param([string[]]$Entries)

    $currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $currentUserPath) { $currentUserPath = "" }

    $parts = $currentUserPath.Split(";", [System.StringSplitOptions]::RemoveEmptyEntries)
    $updated = New-Object System.Collections.Generic.List[string]
    foreach ($part in $parts) {
        if (-not [string]::IsNullOrWhiteSpace($part)) {
            $updated.Add($part.Trim())
        }
    }

    foreach ($entry in $Entries) {
        if (-not $entry) { continue }
        $exists = $false
        foreach ($part in $updated) {
            if ($part.TrimEnd("\") -ieq $entry.TrimEnd("\")) {
                $exists = $true
                break
            }
        }
        if (-not $exists) {
            $updated.Add($entry)
        }
        if (($env:Path -split ";") -notcontains $entry) {
            $env:Path = "$entry;$env:Path"
        }
    }

    [Environment]::SetEnvironmentVariable("Path", ($updated -join ";"), "User")
}

function Install-Uv {
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        Write-Step "uv already exists"
        uv --version
        return
    }

    Write-Step "Installing uv"
    $installScript = "https://astral.sh/uv/install.ps1"
    if ($Proxy) {
        $script = Invoke-WebRequest -Uri $installScript -UseBasicParsing -Proxy $Proxy -ProxyUseDefaultCredentials
    } else {
        $script = Invoke-WebRequest -Uri $installScript -UseBasicParsing
    }
    Invoke-Expression $script.Content

    $uvBin = Join-Path $env:USERPROFILE ".local\bin"
    Add-UserPathEntries -Entries @($uvBin)

    if (Get-Command uv -ErrorAction SilentlyContinue) {
        uv --version
    } else {
        throw "uv was installed but is not visible in PATH."
    }
}

Write-Step "Preparing Windows Python tools"
Install-Uv

Write-Step "Installing Python $PythonVersion with uv"
uv python install $PythonVersion

Write-Host ""
Write-Host "Done. See README.md for next steps." -ForegroundColor Green
