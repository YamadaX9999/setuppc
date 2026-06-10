# ============================================================
#  setup.ps1  -  Auto Installer for Windows 10 LTSC 1809
#  Run: powershell -ExecutionPolicy Bypass -File ".\setup.ps1"
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
    return [bool]($found)
}

function Download-File($url, $dest) {
    $fileName = Split-Path $dest -Leaf
    try {
        # Try BITS first — shows real % progress bar
        Import-Module BitsTransfer -ErrorAction Stop
        Start-BitsTransfer -Source $url -Destination $dest `
            -DisplayName "Downloading $fileName" `
            -Description $url `
            -ErrorAction Stop
    } catch {
        # Fallback: WebClient with progress
        Write-Host "    (BITS unavailable, using WebClient ...)" -ForegroundColor DarkGray
        $wc = New-Object System.Net.WebClient
        $wc.add_DownloadProgressChanged({
            param($s, $e)
            $pct = $e.ProgressPercentage
            $dl  = [math]::Round($e.BytesReceived / 1MB, 1)
            $tot = if ($e.TotalBytesToReceive -gt 0) { [math]::Round($e.TotalBytesToReceive / 1MB, 1) } else { "?" }
            Write-Progress -Activity "Downloading $fileName" `
                -Status "$dl MB / $tot MB  ($pct%)" `
                -PercentComplete ([math]::Max(0, [math]::Min(100, $pct)))
        })
        $wc.add_DownloadFileCompleted({
            Write-Progress -Activity "Downloading $fileName" -Completed
        })
        $wc.DownloadFileAsync([uri]$url, $dest)
        while ($wc.IsBusy) { Start-Sleep -Milliseconds 300 }
        $wc.Dispose()
    }
}

# ── Program definitions ──────────────────────────────────────
$programs = @(
    @{ Name = ".NET Framework 4.8";       Check = "NET48";                   Special = $true  }
    @{ Name = "7-Zip";                    Check = "7-Zip";                   Special = $false }
    @{ Name = "Discord";                  Check = "Discord";                 Special = $false }
    @{ Name = "Steam";                    Check = "Steam";                   Special = $false }
    @{ Name = "Rockstar Games Launcher";  Check = "Rockstar Games Launcher"; Special = $false }
    @{ Name = "Razer Synapse";            Check = "Razer Synapse";           Special = $false }
    @{ Name = "FXSound";                  Check = "FXSound";                 Special = $false }
    @{ Name = "LosslessCut";              Check = "LOSSLESSCUT";             Special = $true  }
    @{ Name = "NVIDIA Driver 610.47";     Check = "NVIDIA_DRIVER";           Special = $true  }
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
             Where-Object { $_.DisplayName -like "*NVIDIA*" -and $_.DisplayVersion -match "^610\.47" }
    return [bool]($found)
}

function Check-LosslessCut {
    $paths = @(
        "C:\Program Files\LosslessCut\LosslessCut.exe",
        "$env:LOCALAPPDATA\Programs\LosslessCut\LosslessCut.exe",
        "$env:PUBLIC\Desktop\LosslessCut.lnk"
    )
    foreach ($p in $paths) { if (Test-Path $p) { return $true } }
    return $false
}

function Get-InstalledStatus($prog) {
    switch ($prog.Check) {
        "NET48"         { return Check-NET48 }
        "NVIDIA_DRIVER" { return Check-NvidiaDriver }
        "LOSSLESSCUT"   { return Check-LosslessCut }
        default         { return Is-Installed $prog.Check }
    }
}

# ============================================================
#  FUNCTION: Install Programs
# ============================================================
function Start-Install {
    # ── SCAN ────────────────────────────────────────────────
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

    if ($toInstall.Count -eq 0) {
        Write-Host "All programs are already installed. Nothing to do!" -ForegroundColor Green
        Read-Host "Press Enter to continue"
        return
    }

    Write-Host "The following $($toInstall.Count) program(s) will be installed:" -ForegroundColor Yellow
    foreach ($prog in $toInstall) {
        Write-Host "  - $($prog.Name)" -ForegroundColor Yellow
    }
    Write-Host ""

    $Host.UI.RawUI.FlushInputBuffer()
    $confirm = ""
    while ($confirm -notmatch "^[YyNn]$") {
        $confirm = (Read-Host "Proceed with installation? (Y/N)").Trim()
    }
    if ($confirm -notmatch "^[Yy]$") {
        Write-Host "Cancelled." -ForegroundColor DarkGray
        return
    }

    # ── INSTALL ─────────────────────────────────────────────
    $tmp = "$env:TEMP\autoinstall"
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $results = @()

    try {
        foreach ($prog in $toInstall) {
            Write-Header
            Write-Step "Installing $($prog.Name) ..."
            $ok = $false

            switch ($prog.Check) {

            # ── .NET 4.8 ────────────────────────────────────
            "NET48" {
                $net48ok = $false
                try {
                    $file = "$tmp\ndp48.exe"
                    Write-Step "Downloading .NET Framework 4.8 ..."
                    Download-File "https://go.microsoft.com/fwlink/?LinkId=2085155" $file
                    Write-Step "Installing (this may take a while) ..."
                    $p = Start-Process $file -ArgumentList "/q /norestart" -Wait -PassThru
                    if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
                        Write-OK ".NET Framework 4.8 installed"
                        $net48ok = $true
                        $ok = $true
                    } else {
                        Write-Fail ".NET Framework 4.8 installer exited with code $($p.ExitCode)"
                    }
                } catch { Write-Fail "Failed: $_" }
                if ($net48ok) {
                    Write-Host ""
                    Write-Host "!! REBOOT required. After reboot, run this script again to continue. !!" -ForegroundColor Red
                    Read-Host "Press Enter to exit"
                    exit 0
                }
            }

            # ── 7-Zip ────────────────────────────────────────
            "7-Zip" {
                try {
                    $file = "$tmp\7zip.exe"
                    Write-Step "Fetching latest 7-Zip version ..."
                    $page = Invoke-WebRequest "https://www.7-zip.org/download.html" -UseBasicParsing -ErrorAction Stop
                    $match = [regex]::Match($page.Content, 'href="(a/7z[\d]+-x64\.exe)"')
                    if ($match.Success) {
                        $url = "https://www.7-zip.org/" + $match.Groups[1].Value
                    } else {
                        $url = "https://www.7-zip.org/a/7z2407-x64.exe"
                    }
                    Write-Step "Downloading from $url ..."
                    Download-File $url $file
                    Start-Process $file -ArgumentList "/S" -Wait
                    Write-OK "7-Zip installed"
                    $ok = $true
                } catch { Write-Fail "Failed: $_" }
            }

            # ── Discord ──────────────────────────────────────
            "Discord" {
                try {
                    $file = "$tmp\DiscordSetup.exe"
                    Download-File "https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=win&arch=x86" $file
                    Start-Process $file -ArgumentList "--silent" -Wait
                    Write-OK "Discord installed"
                    $ok = $true
                } catch { Write-Fail "Failed: $_" }
            }

            # ── Steam ────────────────────────────────────────
            "Steam" {
                try {
                    $file = "$tmp\SteamSetup.exe"
                    Download-File "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe" $file
                    Start-Process $file -ArgumentList "/S" -Wait
                    Write-OK "Steam installed"
                    $ok = $true
                } catch { Write-Fail "Failed: $_" }
            }

            # ── Rockstar ─────────────────────────────────────
            "Rockstar Games Launcher" {
                try {
                    $file = "$tmp\RockstarLauncher.exe"
                    Download-File "https://gamedownloads.rockstargames.com/public/installer/Rockstar-Games-Launcher.exe" $file
                    $proc = Start-Process $file -ArgumentList "/SILENT /LANG=1033" -PassThru
                    $proc.WaitForExit()
                    Write-Step "Waiting for Rockstar child processes to finish ..."
                    $deadline2 = (Get-Date).AddMinutes(5)
                    while ((Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*Rockstar*" }) -and (Get-Date) -lt $deadline2) {
                        Start-Sleep -Seconds 5
                    }
                    $deadline = (Get-Date).AddMinutes(3)
                    while (-not (Is-Installed "Rockstar Games Launcher") -and (Get-Date) -lt $deadline) {
                        Start-Sleep -Seconds 5
                    }
                    if (Is-Installed "Rockstar Games Launcher") {
                        Write-OK "Rockstar Games Launcher installed"
                        $ok = $true
                    } else {
                        Write-Fail "Rockstar: timed out or cancelled — continuing to next program"
                    }
                } catch { Write-Fail "Failed: $_" }
            }

            # ── Razer Synapse ────────────────────────────────
            "Razer Synapse" {
                try {
                    $file = "$tmp\RazerSynapse.exe"
                    Download-File "https://dl.razerzone.com/drivers/Synapse4/RazerSynapseInstaller.exe" $file
                    Start-Process $file -ArgumentList "/S" -Wait
                    Write-OK "Razer Synapse installed"
                    $ok = $true
                } catch { Write-Fail "Failed: $_" }
            }

            # ── FXSound ──────────────────────────────────────
            "FXSound" {
                try {
                    $file = "$tmp\fxsound_setup.exe"
                    Write-Step "Downloading FXSound ..."
                    Download-File "https://github.com/fxsound2/fxsound-app/releases/download/latest/fxsound_setup.exe" $file
                    Write-Step "Installing FXSound (GUI will open — click through the installer) ..."
                    # Note: FXSound installer does NOT support /S or silent flags.
                    # Run without arguments so the GUI installer opens normally.
                    Start-Process $file -Wait
                    Write-OK "FXSound installed"
                    $ok = $true
                } catch { Write-Fail "Failed: $_" }
            }

            # ── LosslessCut ──────────────────────────────────
            "LOSSLESSCUT" {
                try {
                    Write-Step "Fetching latest version from GitHub ..."
                    $api   = Invoke-RestMethod "https://api.github.com/repos/mifi/lossless-cut/releases/latest"
                    $asset = $api.assets | Where-Object { $_.name -match "(?i)^LosslessCut-win-x64\.7z$" } | Select-Object -First 1
                    if ($null -eq $asset) {
                        Write-Fail "LosslessCut: installer asset not found in GitHub release"
                    } else {
                        $archive = "$tmp\LosslessCut.7z"
                        $dest    = "C:\Program Files\LosslessCut"
                        Write-Step "Downloading $($asset.name) ..."
                        Download-File $asset.browser_download_url $archive
                        $7z = "C:\Program Files\7-Zip\7z.exe"
                        if (-not (Test-Path $7z)) { $7z = "C:\Program Files (x86)\7-Zip\7z.exe" }
                        Write-Step "Extracting to $dest ..."
                        Start-Process $7z -ArgumentList "x `"$archive`" -o`"$dest`" -y" -Wait
                        Write-OK "LosslessCut extracted to $dest"
                        Write-Step "Creating desktop shortcut ..."
                        $exe = Get-ChildItem "$dest" -Filter "LosslessCut.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($exe) {
                            $shortcut = "$env:PUBLIC\Desktop\LosslessCut.lnk"
                            $wsh = New-Object -ComObject WScript.Shell
                            $lnk = $wsh.CreateShortcut($shortcut)
                            $lnk.TargetPath = $exe.FullName
                            $lnk.Save()
                            Write-OK "Shortcut created on Desktop"
                        }
                        $ok = $true
                    }
                } catch { Write-Fail "Failed: $_" }
            }

            # ── NVIDIA Driver ────────────────────────────────
            "NVIDIA_DRIVER" {
                try {
                    $file = "$tmp\NvidiaSetup.exe"
                    Write-Step "Downloading NVIDIA Driver 610.47 (~700MB) — progress shown below ..."
                    Download-File "https://us.download.nvidia.com/Windows/610.47/610.47-desktop-win10-win11-64bit-international-dch-whql.exe" $file
                    Write-Step "Installing NVIDIA Driver silently (this may take 3-5 minutes) ..."
                    $p = Start-Process $file -ArgumentList "-s -noreboot" -Wait -PassThru
                    if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 14) {
                        Write-OK "NVIDIA Driver 610.47 installed (reboot required to take effect)"
                        $ok = $true
                    } else {
                        Write-Fail "NVIDIA installer exited with code $($p.ExitCode)"
                    }
                } catch { Write-Fail "Failed: $_" }
            }
        }

        $results += [PSCustomObject]@{ Name = $prog.Name; OK = $ok }
    }

    # ── Summary ──────────────────────────────────────────────
    Write-Header
    Write-Host "Installation Summary:" -ForegroundColor Cyan
    Write-Host ""
    $failCount = 0
    foreach ($r in $results) {
        if ($r.OK) {
            Write-Host "  [OK] $($r.Name)" -ForegroundColor Green
        } else {
            Write-Host "  [!!] $($r.Name) — FAILED" -ForegroundColor Red
            $failCount++
        }
    }
    Write-Host ""
    if ($failCount -eq 0) {
        Write-Host "All programs installed successfully!" -ForegroundColor Green
    } else {
        Write-Host "$failCount program(s) failed. Check the messages above." -ForegroundColor Red
    }
    Write-Host ""

    } finally {
        Write-Host "Cleaning up temp files ..." -ForegroundColor DarkGray
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================
#  FUNCTION: Import FiveM Settings
# ============================================================
function Start-ImportFiveM {
    Write-Header
    Write-Host "Importing FiveM Settings from GitHub ..." -ForegroundColor Cyan
    Write-Host ""

    $cfxDest = "$env:APPDATA\CitizenFX"
    $cfxBase = "https://raw.githubusercontent.com/YamadaX9999/setuppc/main/CitizenFX"

    # ไฟล์ปกติ
    $cfxFiles = @(
        "fivem.cfg",
        "gta5_settings.xml",
        "camera_save_structure.xml",
        "ros_id.dat"
    )

    # ไฟล์ใน subfolder kvs
    $kvsFiles = @(
        "000005.ldb",
        "000008.ldb",
        "000011.ldb",
        "000014.log",
        "CURRENT",
        "LOCK",
        "MANIFEST-000013"
    )

    New-Item -ItemType Directory -Force -Path $cfxDest | Out-Null
    New-Item -ItemType Directory -Force -Path "$cfxDest\kvs" | Out-Null

    $allOk = $true

    # ดาวน์โหลดไฟล์หลัก
    foreach ($file in $cfxFiles) {
        try {
            Write-Step "Downloading $file ..."
            Download-File "$cfxBase/$file" "$cfxDest\$file"
            Write-OK "$file imported"
        } catch {
            Write-Fail "Failed to import $file : $_"
            $allOk = $false
        }
    }

    # ดาวน์โหลดไฟล์ใน kvs
    foreach ($file in $kvsFiles) {
        try {
            Write-Step "Downloading kvs\$file ..."
            Download-File "$cfxBase/kvs/$file" "$cfxDest\kvs\$file"
            Write-OK "kvs\$file imported"
        } catch {
            Write-Fail "Failed to import kvs\$file : $_"
            $allOk = $false
        }
    }

    Write-Host ""
    if ($allOk) {
        Write-OK "FiveM settings imported successfully!"
    } else {
        Write-Fail "Some files failed to import — check messages above"
    }
}

# ============================================================
#  MAIN MENU
# ============================================================
Write-Header
Write-Host "Please select an option:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Install programs" -ForegroundColor Yellow
Write-Host "  2. Import FiveM settings" -ForegroundColor Yellow
Write-Host "  3. Both (Install then Import)" -ForegroundColor Yellow
Write-Host ""

$choice = ""
while ($choice -notmatch "^[123]$") {
    $choice = (Read-Host "Enter choice (1/2/3)").Trim()
}

switch ($choice) {
    "1" { Start-Install }
    "2" { Start-ImportFiveM }
    "3" { Start-Install; Start-ImportFiveM }
}

Write-Host ""
Read-Host "Press Enter to exit"
