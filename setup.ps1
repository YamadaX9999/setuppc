# ============================================================
#  setup.ps1  -  Auto Installer for Windows 10 LTSC 1809
#  Run: powershell -ExecutionPolicy Bypass -File ".\setup.ps1"
# ============================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# ── Helpers ─────────────────────────────────────────────────
function Write-Header {
    Clear-Host
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "   Auto Installer - Windows 10 LTSC 1809   " -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step($msg) { Write-Host "[*] $msg" -ForegroundColor Yellow }
function Write-OK($msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "[--] $msg" -ForegroundColor DarkGray }
function Write-Fail($msg) { Write-Host "[!!] $msg" -ForegroundColor Red }

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

function Download-File($url, $dest) {
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($url, $dest)
}

# ── Program definitions ──────────────────────────────────────
$programs = @(
    @{ Name = ".NET Framework 4.8"; Check = "NET48";    Special = $true  }
    @{ Name = "7-Zip";              Check = "7-Zip";    Special = $false }
    @{ Name = "Discord";            Check = "Discord";  Special = $false }
    @{ Name = "Steam";              Check = "Steam";    Special = $false }
    @{ Name = "Rockstar Games Launcher"; Check = "Rockstar Games Launcher"; Special = $false }
    @{ Name = "Razer Synapse";      Check = "Razer Synapse"; Special = $false }
    @{ Name = "FXSound";            Check = "FXSound";  Special = $false }
    @{ Name = "LosslessCut";        Check = "LosslessCut"; Special = $false }
    @{ Name = "NVIDIA Driver 610.47"; Check = "NVIDIA_DRIVER"; Special = $true }
)

# ── Special check functions ──────────────────────────────────
function Check-NET48 {
    $release = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" `
                -ErrorAction SilentlyContinue).Release
    return ($release -ge 528040)
}

function Check-NvidiaDriver {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $found = Get-ItemProperty $paths -ErrorAction SilentlyContinue |
             Where-Object { $_.DisplayName -like "*NVIDIA*" -and $_.DisplayVersion -like "610.47*" }
    return ($null -ne $found)
}

function Get-InstalledStatus($prog) {
    switch ($prog.Check) {
        "NET48"         { return Check-NET48 }
        "NVIDIA_DRIVER" { return Check-NvidiaDriver }
        default         { return Is-Installed $prog.Check }
    }
}

# ============================================================
#  PHASE 1: SCAN
# ============================================================
Write-Header
Write-Host "Scanning installed programs ..." -ForegroundColor Cyan
Write-Host ""

$toInstall = @()

foreach ($prog in $programs) {
    $installed = Get-InstalledStatus $prog
    if ($installed) {
        Write-Host "  [INSTALLED] $($prog.Name)" -ForegroundColor Green
    } else {
        Write-Host "  [MISSING]   $($prog.Name)" -ForegroundColor Red
        $toInstall += $prog
    }
}

Write-Host ""

# ── ถ้าครบแล้ว ────────────────────────────────────────────────
if ($toInstall.Count -eq 0) {
    Write-Host "All programs are already installed. Nothing to do!" -ForegroundColor Green
    Read-Host "Press Enter to exit"
    exit 0
}

# ── แสดงรายการที่จะติดตั้ง ────────────────────────────────────
Write-Host "The following $($toInstall.Count) program(s) will be installed:" -ForegroundColor Yellow
foreach ($prog in $toInstall) {
    Write-Host "  - $($prog.Name)" -ForegroundColor Yellow
}
Write-Host ""

# ── ถามยืนยัน ─────────────────────────────────────────────────
$confirm = Read-Host "Proceed with installation? (Y/N)"
if ($confirm -notmatch "^[Yy]$") {
    Write-Host "Cancelled." -ForegroundColor DarkGray
    exit 0
}

# ============================================================
#  PHASE 2: INSTALL
# ============================================================
$tmp = "$env:TEMP\autoinstall"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    foreach ($prog in $toInstall) {
        Write-Header
        Write-Step "Installing $($prog.Name) ..."

        switch ($prog.Check) {

            # ── .NET 4.8 ────────────────────────────────────
            "NET48" {
                try {
                    $file = "$tmp\ndp48.exe"
                    Write-Step "Downloading .NET Framework 4.8 ..."
                    Download-File "https://go.microsoft.com/fwlink/?LinkId=2085155" $file
                    Write-Step "Installing (this may take a while) ..."
                    Start-Process $file -ArgumentList "/q /norestart" -Wait
                    Write-OK ".NET Framework 4.8 installed"
                } catch { Write-Fail "Failed: $_" }
                Write-Host ""
                Write-Host "!! REBOOT required. After reboot, run this script again to continue. !!" -ForegroundColor Red
                Read-Host "Press Enter to exit"
                exit 0
            }

            # ── 7-Zip ────────────────────────────────────────
            "7-Zip" {
                try {
                    $file = "$tmp\7zip.exe"
                    Download-File "https://www.7-zip.org/a/7z2407-x64.exe" $file
                    Start-Process $file -ArgumentList "/S" -Wait
                    Write-OK "7-Zip installed"
                } catch { Write-Fail "Failed: $_" }
            }

            # ── Discord ──────────────────────────────────────
            "Discord" {
                try {
                    $file = "$tmp\DiscordSetup.exe"
                    Download-File "https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=win&arch=x86" $file
                    Start-Process $file -ArgumentList "--silent" -Wait
                    Write-OK "Discord installed"
                } catch { Write-Fail "Failed: $_" }
            }

            # ── Steam ────────────────────────────────────────
            "Steam" {
                try {
                    $file = "$tmp\SteamSetup.exe"
                    Download-File "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe" $file
                    Start-Process $file -ArgumentList "/S" -Wait
                    Write-OK "Steam installed"
                } catch { Write-Fail "Failed: $_" }
            }

            # ── Rockstar ─────────────────────────────────────
            "Rockstar Games Launcher" {
                try {
                    $file = "$tmp\RockstarLauncher.exe"
                    Download-File "https://gamedownloads.rockstargames.com/public/installer/Rockstar-Games-Launcher.exe" $file
                    Start-Process $file -ArgumentList "/S" -Wait
                    Write-OK "Rockstar Games Launcher installed"
                } catch { Write-Fail "Failed: $_" }
            }

            # ── Razer Synapse ────────────────────────────────
            "Razer Synapse" {
                try {
                    $file = "$tmp\RazerSynapse.exe"
                    Download-File "https://dl.razerzone.com/drivers/Synapse4/RazerSynapseInstaller.exe" $file
                    Start-Process $file -ArgumentList "/S" -Wait
                    Write-OK "Razer Synapse installed"
                } catch { Write-Fail "Failed: $_" }
            }

            # ── FXSound ──────────────────────────────────────
            "FXSound" {
                try {
                    $file = "$tmp\fxsound_setup.exe"
                    Download-File "https://github.com/fxsound2/fxsound-app/releases/download/latest/fxsound_setup.exe" $file
                    Start-Process $file -ArgumentList "/S" -Wait
                    Write-OK "FXSound installed"
                } catch { Write-Fail "Failed: $_" }
            }

            # ── LosslessCut ──────────────────────────────────
            "LosslessCut" {
                try {
                    Write-Step "Fetching latest version from GitHub ..."
                    $api   = Invoke-RestMethod "https://api.github.com/repos/mifi/lossless-cut/releases/latest"
                    $asset = $api.assets | Where-Object { $_.name -match "(?i)win.*x64.*Setup.*\.exe$" } | Select-Object -First 1
                    if ($null -eq $asset) {
                        Write-Fail "LosslessCut: installer asset not found in GitHub release"
                    } else {
                        $file = "$tmp\LosslessCutSetup.exe"
                        Write-Step "Downloading $($asset.name) ..."
                        Download-File $asset.browser_download_url $file
                        Start-Process $file -ArgumentList "/S" -Wait
                        Write-OK "LosslessCut installed"
                    }
                } catch { Write-Fail "Failed: $_" }
            }

            # ── NVIDIA Driver ────────────────────────────────
            "NVIDIA_DRIVER" {
                try {
                    $file = "$tmp\NvidiaSetup.exe"
                    Write-Step "Downloading NVIDIA Driver 610.47 (~700MB, please wait) ..."
                    Download-File "https://us.download.nvidia.com/Windows/610.47/610.47-desktop-win10-win11-64bit-international-dch-whql.exe" $file
                    Start-Process $file -ArgumentList "-s -noreboot" -Wait
                    Write-OK "NVIDIA Driver 610.47 installed"
                } catch { Write-Fail "Failed: $_" }
            }
        }
    }

    # ── Done ─────────────────────────────────────────────────
    Write-Header
    Write-Host "Installation complete!" -ForegroundColor Cyan
    Write-Host ""

} finally {
    Write-Host "Cleaning up temp files ..." -ForegroundColor DarkGray
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Read-Host "Press Enter to exit"
