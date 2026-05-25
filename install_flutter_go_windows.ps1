#Requires -Version 5.1
<#
Installs a user-level Flutter + Android + Go toolchain for this project.

Default locations:
  Tools root:   %USERPROFILE%\devtools
  Flutter SDK:  %USERPROFILE%\devtools\flutter
  Go SDK:       %USERPROFILE%\devtools\go
  JDK 17:       %USERPROFILE%\devtools\jdk-17
  Android SDK:  %LOCALAPPDATA%\Android\Sdk

Usage:
  powershell -ExecutionPolicy Bypass -File .\install_flutter_go_windows.ps1
  powershell -ExecutionPolicy Bypass -File .\install_flutter_go_windows.ps1 -NoChinaMirrors

Open a new terminal after the script finishes so Windows reloads PATH.
#>

[CmdletBinding()]
param(
    [string]$ToolsRoot = (Join-Path $env:USERPROFILE "devtools"),
    [string]$FlutterDir,
    [string]$GoRoot,
    [string]$JavaHome,
    [string]$AndroidSdkRoot = (Join-Path $env:LOCALAPPDATA "Android\Sdk"),
    [int]$AndroidApiLevel = 36,
    [string]$AndroidBuildTools = "36.0.0",
    [string]$Proxy,
    [switch]$SkipAndroidLicenses,
    [switch]$NoChinaMirrors
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not $FlutterDir) { $FlutterDir = Join-Path $ToolsRoot "flutter" }
if (-not $GoRoot) { $GoRoot = Join-Path $ToolsRoot "go" }
if (-not $JavaHome) { $JavaHome = Join-Path $ToolsRoot "jdk-17" }

$UseChinaMirrors = -not $NoChinaMirrors
$FlutterStorageBaseUrl = if ($UseChinaMirrors) { "https://storage.flutter-io.cn" } else { "https://storage.googleapis.com" }
$GoDownloadBaseUrl = if ($UseChinaMirrors) { "https://mirrors.aliyun.com/golang" } else { "https://go.dev/dl" }
$GoReleaseJsonUrl = if ($UseChinaMirrors) { "https://golang.google.cn/dl/?mode=json" } else { "https://go.dev/dl/?mode=json" }
$Jdk17DownloadUrlX64 = if ($UseChinaMirrors) {
    "https://mirrors.huaweicloud.com/repository/toolkit/openjdk/17/openjdk-17_windows-x64_bin.zip"
} else {
    "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk"
}
$Jdk17DownloadUrlArm64 = "https://api.adoptium.net/v3/binary/latest/17/ga/windows/aarch64/jdk/hotspot/normal/eclipse?project=jdk"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Host "WARN: $Message" -ForegroundColor Yellow
}

function New-CleanDirectory {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Invoke-Download {
    param(
        [string]$Url,
        [string]$OutFile
    )

    $args = @{
        Uri = $Url
        OutFile = $OutFile
        UseBasicParsing = $true
    }
    if ($Proxy) {
        $args.Proxy = $Proxy
        $args.ProxyUseDefaultCredentials = $true
    }
    if (Test-Path -LiteralPath $OutFile) {
        Remove-Item -LiteralPath $OutFile -Force
    }
    Invoke-WebRequest @args
    if (-not (Test-Path -LiteralPath $OutFile)) {
        throw "Download did not create file: $OutFile"
    }
    $downloaded = Get-Item -LiteralPath $OutFile
    if ($downloaded.Length -le 0) {
        throw "Downloaded file is empty: $OutFile"
    }
}

function Invoke-DownloadFirstAvailable {
    param(
        [string[]]$Urls,
        [string]$OutFile
    )

    $lastError = $null
    foreach ($url in $Urls) {
        try {
            Write-Host "Downloading: $url"
            Invoke-Download -Url $url -OutFile $OutFile
            return $url
        } catch {
            $lastError = $_
            Write-Warn "Download failed, trying next source: $url"
            if (Test-Path -LiteralPath $OutFile) {
                Remove-Item -LiteralPath $OutFile -Force
            }
        }
    }

    if ($lastError) {
        throw $lastError
    }
    throw "No download URL was provided."
}

function Invoke-Json {
    param([string]$Url)

    $args = @{
        Uri = $Url
        UseBasicParsing = $true
    }
    if ($Proxy) {
        $args.Proxy = $Proxy
        $args.ProxyUseDefaultCredentials = $true
    }
    return Invoke-RestMethod @args
}

function Invoke-Text {
    param([string]$Url)

    $args = @{
        Uri = $Url
        UseBasicParsing = $true
    }
    if ($Proxy) {
        $args.Proxy = $Proxy
        $args.ProxyUseDefaultCredentials = $true
    }
    return (Invoke-WebRequest @args).Content
}

function Expand-Zip {
    param(
        [string]$ZipFile,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $ZipFile)) {
        throw "Archive not found: $ZipFile"
    }
    New-CleanDirectory -Path $Destination
    Expand-Archive -LiteralPath $ZipFile -DestinationPath $Destination -Force
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

function Set-UserEnv {
    param(
        [string]$Name,
        [string]$Value
    )

    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Set-Item -Path "env:$Name" -Value $Value
}

function Get-WindowsArch {
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
    if ($arch -match "ARM64") { return "arm64" }
    return "amd64"
}

function Install-GitIfMissing {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Step "Git is already available"
        git --version
        return
    }

    Write-Step "Git was not found; trying winget install"
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warn "winget is not available. Install Git for Windows manually: https://git-scm.com/download/win"
        return
    }

    winget install --id Git.Git -e --source winget --scope user --accept-package-agreements --accept-source-agreements --disable-interactivity

    $possibleGitPaths = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Git\cmd"),
        "C:\Program Files\Git\cmd"
    )
    foreach ($path in $possibleGitPaths) {
        if (Test-Path -LiteralPath (Join-Path $path "git.exe")) {
            Add-UserPathEntries -Entries @($path)
            break
        }
    }

    if (Get-Command git -ErrorAction SilentlyContinue) {
        git --version
    } else {
        Write-Warn "Git was installed but is not visible in this terminal yet. Open a new terminal after the script finishes."
    }
}

function Install-Flutter {
    $flutterExe = Join-Path $FlutterDir "bin\flutter.bat"
    if (Test-Path -LiteralPath $flutterExe) {
        Write-Step "Flutter already exists at $FlutterDir"
        & $flutterExe --version
        return
    }

    if (Test-Path -LiteralPath $FlutterDir) {
        throw "Directory exists but is not a Flutter SDK: $FlutterDir"
    }

    Write-Step "Downloading latest stable Flutter SDK"
    New-Item -ItemType Directory -Path $ToolsRoot -Force | Out-Null
    $releaseJsonUrl = "$FlutterStorageBaseUrl/flutter_infra_release/releases/releases_windows.json"
    $releaseIndex = Invoke-Json -Url $releaseJsonUrl
    $stableHash = $releaseIndex.current_release.stable
    $release = $releaseIndex.releases | Where-Object { $_.hash -eq $stableHash } | Select-Object -First 1
    if (-not $release) {
        throw "Could not resolve latest Flutter stable release."
    }

    $archiveUrl = "$FlutterStorageBaseUrl/flutter_infra_release/releases/$($release.archive)"
    $archiveUrls = @($archiveUrl)
    if ($UseChinaMirrors) {
        $archiveUrls = @(
            "https://storage.flutter-io.cn/flutter_infra_release/releases/$($release.archive)",
            "https://mirrors.cloud.tencent.com/flutter/flutter_infra_release/releases/$($release.archive)",
            "https://storage.googleapis.com/flutter_infra_release/releases/$($release.archive)"
        )
    }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("flutter-install-" + [Guid]::NewGuid().ToString("N"))
    New-CleanDirectory -Path $tmp
    try {
        $zip = Join-Path $tmp "flutter.zip"
        Invoke-DownloadFirstAvailable -Urls $archiveUrls -OutFile $zip | Out-Null
        Expand-Zip -ZipFile $zip -Destination $tmp

        $extractedFlutter = Join-Path $tmp "flutter"
        if (-not (Test-Path -LiteralPath $extractedFlutter)) {
            throw "Flutter archive layout is unexpected."
        }
        Move-Item -LiteralPath $extractedFlutter -Destination $FlutterDir
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Recurse -Force
        }
    }

    & $flutterExe --version
}

function Install-Go {
    $goExe = Join-Path $GoRoot "bin\go.exe"
    if (Test-Path -LiteralPath $goExe) {
        Write-Step "Go already exists at $GoRoot"
        & $goExe version
        return
    }

    if (Test-Path -LiteralPath $GoRoot) {
        throw "Directory exists but is not a Go SDK: $GoRoot"
    }

    Write-Step "Downloading latest stable Go SDK"
    New-Item -ItemType Directory -Path $ToolsRoot -Force | Out-Null
    $arch = Get-WindowsArch
    $goIndex = Invoke-Json -Url $GoReleaseJsonUrl
    $stable = $goIndex | Where-Object { $_.stable } | Select-Object -First 1
    $file = $stable.files | Where-Object {
        $_.os -eq "windows" -and $_.arch -eq $arch -and $_.kind -eq "archive"
    } | Select-Object -First 1
    if (-not $file) {
        throw "Could not find a Go archive for windows/$arch."
    }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("go-install-" + [Guid]::NewGuid().ToString("N"))
    New-CleanDirectory -Path $tmp
    try {
        $zip = Join-Path $tmp $file.filename
        $urls = @("$GoDownloadBaseUrl/$($file.filename)")
        if ($UseChinaMirrors) {
            $urls += "https://golang.google.cn/dl/$($file.filename)"
            $urls += "https://go.dev/dl/$($file.filename)"
        }
        Invoke-DownloadFirstAvailable -Urls $urls -OutFile $zip | Out-Null
        Expand-Zip -ZipFile $zip -Destination $tmp

        $extractedGo = Join-Path $tmp "go"
        if (-not (Test-Path -LiteralPath $extractedGo)) {
            throw "Go archive layout is unexpected."
        }
        Move-Item -LiteralPath $extractedGo -Destination $GoRoot
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Recurse -Force
        }
    }

    & $goExe version
}

function Install-Jdk17 {
    $javaExe = Join-Path $JavaHome "bin\java.exe"
    if (Test-Path -LiteralPath $javaExe) {
        Write-Step "JDK 17 already exists at $JavaHome"
        & $javaExe -version
        return
    }

    if (Test-Path -LiteralPath $JavaHome) {
        throw "Directory exists but is not a JDK: $JavaHome"
    }

    Write-Step "Downloading Eclipse Temurin JDK 17"
    New-Item -ItemType Directory -Path $ToolsRoot -Force | Out-Null
    $arch = Get-WindowsArch
    $url = $Jdk17DownloadUrlX64
    if ($arch -eq "arm64") { $url = $Jdk17DownloadUrlArm64 }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("jdk-install-" + [Guid]::NewGuid().ToString("N"))
    New-CleanDirectory -Path $tmp
    try {
        $zip = Join-Path $tmp "jdk.zip"
        $urls = @($url)
        if ($UseChinaMirrors -and $arch -ne "arm64") {
            $urls += "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk"
        }
        Invoke-DownloadFirstAvailable -Urls $urls -OutFile $zip | Out-Null
        Expand-Zip -ZipFile $zip -Destination $tmp

        $jdkDir = Get-ChildItem -LiteralPath $tmp -Directory | Where-Object {
            Test-Path -LiteralPath (Join-Path $_.FullName "bin\java.exe")
        } | Select-Object -First 1
        if (-not $jdkDir) {
            throw "JDK archive layout is unexpected."
        }
        Move-Item -LiteralPath $jdkDir.FullName -Destination $JavaHome
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Recurse -Force
        }
    }

    & $javaExe -version
}

function Install-AndroidSdk {
    $sdkManager = Join-Path $AndroidSdkRoot "cmdline-tools\latest\bin\sdkmanager.bat"
    if (Test-Path -LiteralPath $sdkManager) {
        Write-Step "Android command-line tools already exist at $AndroidSdkRoot"
    } else {
        Write-Step "Downloading Android command-line tools"
        New-Item -ItemType Directory -Path (Join-Path $AndroidSdkRoot "cmdline-tools") -Force | Out-Null

        $repoXmlText = Invoke-Text -Url "https://dl.google.com/android/repository/repository2-1.xml"
        [xml]$repoXml = $repoXmlText
        $node = Select-Xml -Xml $repoXml -XPath "//*[local-name()='remotePackage' and @path='cmdline-tools;latest']" | Select-Object -First 1
        if (-not $node) {
            throw "Could not find Android cmdline-tools package in repository XML."
        }
        $archive = $node.Node.archives.archive | Where-Object { $_.'host-os' -eq "windows" } | Select-Object -First 1
        if (-not $archive) {
            throw "Could not find Android cmdline-tools Windows archive."
        }
        $archiveName = $archive.complete.url
        $archiveUrls = @("https://dl.google.com/android/repository/$archiveName")
        if ($UseChinaMirrors) {
            $archiveUrls = @(
                "https://mirrors.ustc.edu.cn/android/repository/$archiveName",
                "https://dl.google.com/android/repository/$archiveName"
            )
        }

        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("android-sdk-install-" + [Guid]::NewGuid().ToString("N"))
        New-CleanDirectory -Path $tmp
        try {
            $zip = Join-Path $tmp "cmdline-tools.zip"
            Invoke-DownloadFirstAvailable -Urls $archiveUrls -OutFile $zip | Out-Null
            Expand-Zip -ZipFile $zip -Destination $tmp

            $source = Join-Path $tmp "cmdline-tools"
            $latest = Join-Path $AndroidSdkRoot "cmdline-tools\latest"
            if (-not (Test-Path -LiteralPath $source)) {
                throw "Android command-line tools archive layout is unexpected."
            }
            New-CleanDirectory -Path $latest
            Get-ChildItem -LiteralPath $source -Force | Move-Item -Destination $latest
        } finally {
            if (Test-Path -LiteralPath $tmp) {
                Remove-Item -LiteralPath $tmp -Recurse -Force
            }
        }
    }

    Write-Step "Installing Android SDK packages"
    $packages = @(
        "platform-tools",
        "platforms;android-$AndroidApiLevel",
        "build-tools;$AndroidBuildTools"
    )
    $yes = ("y`n" * 100)
    $yes | & $sdkManager --sdk_root=$AndroidSdkRoot $packages

    if (-not $SkipAndroidLicenses) {
        Write-Step "Accepting Android SDK licenses"
        $yes | & $sdkManager --sdk_root=$AndroidSdkRoot --licenses
    } else {
        Write-Warn "Skipped Android licenses. Run 'flutter doctor --android-licenses' before building Android apps."
    }
}

Write-Step "Installing toolchain into $ToolsRoot"
if ($UseChinaMirrors) {
    Write-Host "China mirrors are enabled by default. Use -NoChinaMirrors to use upstream sources."
} else {
    Write-Host "Using upstream sources."
}
New-Item -ItemType Directory -Path $ToolsRoot -Force | Out-Null

Install-GitIfMissing
Install-Flutter
Install-Go
Install-Jdk17

Set-UserEnv -Name "FLUTTER_HOME" -Value $FlutterDir
Set-UserEnv -Name "GOROOT" -Value $GoRoot
Set-UserEnv -Name "JAVA_HOME" -Value $JavaHome
Set-UserEnv -Name "ANDROID_HOME" -Value $AndroidSdkRoot
Set-UserEnv -Name "ANDROID_SDK_ROOT" -Value $AndroidSdkRoot

$pathEntries = @(
    (Join-Path $FlutterDir "bin"),
    (Join-Path $GoRoot "bin"),
    (Join-Path $JavaHome "bin"),
    (Join-Path $AndroidSdkRoot "cmdline-tools\latest\bin"),
    (Join-Path $AndroidSdkRoot "platform-tools")
)
Add-UserPathEntries -Entries $pathEntries

Install-AndroidSdk

Write-Step "Configuring Flutter"
$flutterExe = Join-Path $FlutterDir "bin\flutter.bat"
& $flutterExe config --android-sdk $AndroidSdkRoot
if ($UseChinaMirrors) {
    Set-UserEnv -Name "PUB_HOSTED_URL" -Value "https://pub.flutter-io.cn"
    Set-UserEnv -Name "FLUTTER_STORAGE_BASE_URL" -Value "https://storage.flutter-io.cn"
    Set-UserEnv -Name "GRADLE_USER_HOME" -Value (Join-Path $env:USERPROFILE ".gradle")
    $goExe = Join-Path $GoRoot "bin\go.exe"
    & $goExe env -w GOPROXY=https://goproxy.cn,direct
}
& $flutterExe precache --android

Write-Step "Final checks"
& $flutterExe doctor
& (Join-Path $GoRoot "bin\go.exe") version

Write-Host ""
Write-Host "Environment install finished." -ForegroundColor Green
Write-Host "Open a new PowerShell window, then run:"
Write-Host "  flutter doctor"
Write-Host "  cd bluetooth_server; go test ./..."
Write-Host "  cd ..\bluetooth_client; flutter pub get; flutter devices"
