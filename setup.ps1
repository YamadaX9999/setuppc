# ============================================================
#  setup.ps1  -  Auto Installer for Windows 10 LTSC 1809
#  Run as Administrator:
#  Set-ExecutionPolicy Bypass -Scope Process -Force
#  irm https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/setup.ps1 | iex
# ============================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Continue"

# ── Helpers ─────────────────────────────────────────────────
function Write-Header {
    Clear-Host
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "   Auto Installer - Windows 10 LTSC 1809   " -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step($msg)  { Write-Host "[*] $msg" -ForegroundColor Yellow }
function Write-OK($msg)    { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Skip($msg)  { Write-Host "[--] $msg already installed, skipping." -ForegroundColor DarkGray }
function Write-Fail($msg)  { Write-Host "[!!] $msg" -ForegroundColor Red }

function Is-Installed($name) {
    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $found = Get-ItemProperty $paths -ErrorAction SilentlyContinue |
             Where-Object { $_.DisplayName -like "*$name*" }
    return ($null -ne $found)
}

function Download-And-Install($name, $url, $installerArgs, $checkName) {
    Write-Step "Checking $name ..."
    if (Is-Installed $checkName) {
        Write-Skip $name
        return
    }
    $ext  = if ($url -match "\.msi$") { ".msi" } else { ".exe" }
    $file = "$tmp\$($name -replace ' ','_')$ext"
    try {
        Write-Step "Downloading $name ..."
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($url, $file)
        Write-Step "Installing $name ..."
        if ($ext -eq ".msi") {
            Start-Process "msiexec.exe" -ArgumentList "/i `"$file`" $installerArgs" -Wait
        } else {
            Start-Process $file -ArgumentList $installerArgs -Wait
        }
        Write-OK "$name installed successfully"
    } catch {
        Write-Fail "Failed to install $name : $_"
    }
}

# ── Temp folder ─────────────────────────────────────────────
$tmp = "$env:TEMP\autoinstall"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# ============================================================
Write-Header

# ── 1. .NET Framework 4.8 ────────────────────────────────────
Write-Step "Checking .NET Framework 4.8 ..."
$release = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" `
            -ErrorAction SilentlyContinue).Release
if ($release -ge 528040) {
    Write-Skip ".NET Framework 4.8"
} else {
    $netFile = "$tmp\ndp48.exe"
    Write-Step "Downloading .NET Framework 4.8 ..."
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile("https://go.microsoft.com/fwlink/?LinkId=2085155", $netFile)
    Write-Step "Installing .NET Framework 4.8 (this may take a while) ..."
    Start-Process $netFile -ArgumentList "/q /norestart" -Wait
    Write-OK ".NET Framework 4.8 installed"
    Write-Host ""
    Write-Host "!! Please REBOOT and re-run this script to continue !!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 0
}

# ── 2. 7-Zip ─────────────────────────────────────────────────
Download-And-Install `
    "7-Zip" `
    "https://www.7-zip.org/a/7z2407-x64.exe" `
    "/S" `
    "7-Zip"

# ── 3. Discord ───────────────────────────────────────────────
Download-And-Install `
    "Discord" `
    "https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=win&arch=x86" `
    "--silent" `
    "Discord"

# ── 4. Steam ─────────────────────────────────────────────────
Download-And-Install `
    "Steam" `
    "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe" `
    "/S" `
    "Steam"

# ── 5. Rockstar Games Launcher ───────────────────────────────
Download-And-Install `
    "Rockstar Games Launcher" `
    "https://gamedownloads.rockstargames.com/public/installer/Rockstar-Games-Launcher.exe" `
    "/S" `
    "Rockstar Games Launcher"

# ── 6. Razer Synapse 4 ───────────────────────────────────────
Download-And-Install `
    "Razer Synapse" `
    "https://dl.razerzone.com/drivers/Synapse4/RazerSynapseInstaller.exe" `
    "/S" `
    "Razer Synapse"

# ── 7. FXSound ───────────────────────────────────────────────
Download-And-Install `
    "FXSound" `
    "https://github.com/fxsound2/fxsound-app/releases/download/latest/fxsound_setup.exe" `
    "/S" `
    "FXSound"

# ── 8. LosslessCut ───────────────────────────────────────────
Write-Step "Checking LosslessCut ..."
if (Is-Installed "LosslessCut") {
    Write-Skip "LosslessCut"
} else {
    try {
        Write-Step "Fetching latest LosslessCut version from GitHub ..."
        $api      = Invoke-RestMethod "https://api.github.com/repos/mifi/lossless-cut/releases/latest"
        $asset    = $api.assets | Where-Object { $_.name -match "win.*x64.*Setup.*\.exe$" } | Select-Object -First 1
        $lcUrl    = $asset.browser_download_url
        $lcFile   = "$tmp\LosslessCutSetup.exe"
        Write-Step "Downloading LosslessCut ..."
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($lcUrl, $lcFile)
        Write-Step "Installing LosslessCut ..."
        Start-Process $lcFile -ArgumentList "/S" -Wait
        Write-OK "LosslessCut installed successfully"
    } catch {
        Write-Fail "Failed to install LosslessCut: $_"
    }
}

# ── 9. NVIDIA Driver 610.47 ──────────────────────────────────
Write-Step "Checking NVIDIA Driver ..."
$nvInstalled = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" `
               -ErrorAction SilentlyContinue |
               Where-Object { $_.DisplayName -like "*NVIDIA Graphics Driver*" -and $_.DisplayVersion -like "610.47*" }
if ($nvInstalled) {
    Write-Skip "NVIDIA Driver 610.47"
} else {
    Download-And-Install `
        "NVIDIA Driver 610.47" `
        "https://us.download.nvidia.com/Windows/610.47/610.47-desktop-win10-win11-64bit-international-dch-whql.exe" `
        "-s -noreboot" `
        "NVIDIA Graphics Driver"
}

# ============================================================
#  Done
# ============================================================
Write-Header
Write-Host "Installation complete!" -ForegroundColor Cyan
Write-Host ""
Write-Host "Cleaning up temp files ..." -ForegroundColor DarkGray
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Read-Host "Press Enter to exit"
