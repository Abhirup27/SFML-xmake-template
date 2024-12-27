
param(
    [string]$compiler,
    [string]$buildMode
)
# Install xmake if not present
if (-not (Get-Command xmake -ErrorAction SilentlyContinue)) {
    Write-Host "Installing xmake..."
    Invoke-Expression (Invoke-WebRequest 'https://xmake.io/psget.text' -UseBasicParsing).Content
}
else {
	Write-Host "xmake is installed."
}
# Function to check if MinGW is installed via w64devkit
function Test-MinGW {
    $w64devkitPath = "C:\w64devkit\bin\gcc.exe"
    return Test-Path $w64devkitPath
}

# Function to check if MSVC is installed
function Test-MSVC {
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vsWhere) {
        $vsPath = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        return $null -ne $vsPath
    }
    return $false
}

# Function to download and install w64devkit
function Install-W64DevKit {
    $w64devkitUrl = "https://github.com/skeeto/w64devkit/releases/download/v1.21.0/w64devkit-1.21.0.zip"
    $zipPath = "$env:TEMP\w64devkit.zip"
    $extractPath = "C:\"
    Write-Host "Downloading w64devkit..."
    Invoke-WebRequest -Uri $w64devkitUrl -OutFile $zipPath
    Write-Host "Extracting w64devkit to C:\..."
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    # Add to PATH
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -notlike "*w64devkit\bin*") {
        [Environment]::SetEnvironmentVariable("Path", $currentPath + ";C:\w64devkit\bin", "User")
        $env:Path = $env:Path + ";C:\w64devkit\bin"
    }
    Remove-Item $zipPath
}

# Function to install Visual Studio Build Tools
function Install-MSVC {
    Write-Host "Downloading Visual Studio Build Tools..."
    $vsInstallerUrl = "https://aka.ms/vs/17/release/vs_buildtools.exe"
    $installerPath = "$env:TEMP\\vs_buildtools.exe"
    Invoke-WebRequest -Uri $vsInstallerUrl -OutFile $installerPath
    Write-Host "Installing Visual Studio Build Tools (this may take a while)..."
    Start-Process -Wait -FilePath $installerPath -ArgumentList "--quiet", "--wait", "--norestart", "--nocache", `
        "--installPath", "$env:ProgramFiles\\Microsoft Visual Studio\\2022\\BuildTools", `
        "--add", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", `
        "--add", "Microsoft.VisualStudio.Component.Windows11SDK.22621"
    Remove-Item $installerPath
}

# Function to get MSVC path
function Get-MSVCPath {
    $vsWhere = "${env:ProgramFiles(x86)}\\Microsoft Visual Studio\\Installer\\vswhere.exe"
    if (Test-Path $vsWhere) {
        $vsPath = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($vsPath) {
            # Get the VC tools version
            $vcToolsPath = "$vsPath\\VC\\Tools\\MSVC"
            if (Test-Path $vcToolsPath) {
                $latestVersion = Get-ChildItem $vcToolsPath | Sort-Object Name -Descending | Select-Object -First 1
                return "$vcToolsPath\$($latestVersion.Name)"
            }
        }
    }
    return $null
}

# Parse compiler argument
if ($compiler) {
    switch ($compiler.ToLower()) {
        "--mingw" { $selectedCompiler = "mingw" }
        "--msvc" { $selectedCompiler = "msvc" }
        default {
            Write-Host "Invalid compiler argument. Use --mingw or --msvc"
            exit 1
        }
    }
} else {
    Write-Host "`nSelect compiler:"
    Write-Host "1. MSVC (Visual Studio)"
    Write-Host "2. MinGW (w64devkit)"
    $compilerChoice = Read-Host "Enter your choice (1-2)"
    $selectedCompiler = switch ($compilerChoice) {
        "1" { "msvc" }
        "2" { "mingw" }
        default { 
            Write-Host "Invalid choice. Exiting..."
            exit 1
        }
    }
}

# Parse build mode argument
if ($buildMode) {
    switch ($buildMode.ToLower()) {
        "--debug" { $mode = "debug" }
        "--release" { $mode = "release" }
        "--dev" { $mode = "dev" }
        default {
            Write-Host "Invalid build mode. Use --debug, --release, or --dev"
            exit 1
        }
    }
} else {
    Write-Host "`nSelect build mode:"
    Write-Host "1. Debug"
    Write-Host "2. Release"
    Write-Host "3. Dev"
    $modeChoice = Read-Host "Enter your choice (1-3)"
    $mode = switch ($modeChoice) {
        "1" { "debug" }
        "2" { "release" }
        "3" { "dev" }
        default { 
            Write-Host "Invalid choice. Exiting..."
            exit 1
        }
    }
}

# Check and install selected compiler
if ($selectedCompiler -eq "msvc") {
    Write-Host "Checking for MSVC..."
    if (-not (Test-MSVC)) {
        Write-Host "MSVC not found. Would you like to install Visual Studio Build Tools? (Y/N)"
        $response = Read-Host
        if ($response -eq 'Y' -or $response -eq 'y') {
            Install-MSVC
        } else {
            Write-Host "Cannot proceed without a C++ compiler. Exiting..."
            exit 1
        }
    }
    $sdkPath = Get-MSVCPath
    $binPath = "$sdkPath\bin\Hostx64\x64"
} else {
    Write-Host "Checking for MinGW..."
    if (-not (Test-MinGW)) {
        Write-Host "MinGW not found. Would you like to install w64devkit? (Y/N)"
        $response = Read-Host
        if ($response -eq 'Y' -or $response -eq 'y') {
            Install-W64DevKit
        } else {
            Write-Host "Cannot proceed without a C++ compiler. Exiting..."
            exit 1
        }
    }
    $sdkPath = "C:\\w64devkit"
    $binPath = "C:\\w64devkit\\bin"
}

# Configure xmake
Write-Host "`nConfiguring xmake..."
$xmakeCommand
if ($selectedCompiler -eq "msvc") {
	$xmakeCommand = "xmake f -p windows -m $mode"
}
else
{
	$xmakeCommand = "xmake f -p $selectedCompiler --sdk=`"$sdkPath`" --bin=`"$binPath`" -m $mode"
}
#$xmakeCommand = "xmake f -p $selectedCompiler --sdk=`"$sdkPath`" --bin=`"$binPath`" -m $mode"
Write-Host "Executing: $xmakeCommand"
Invoke-Expression $xmakeCommand

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nXMake configuration successful!"
} else {
    Write-Host "`nXMake configuration failed!" -ForegroundColor Red
    exit 1
}

Write-Host "building!"
Invoke-Expression xmake
if ($LASTEXITCODE -eq 0) {
    Write-Host "`nbuild successful!"
} else {
    Write-Host "`nbuild failed!" -ForegroundColor Red
    exit 1
}