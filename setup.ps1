# ============================================================
#  setup.ps1  -  Auto Installer
#  Run: powershell -ExecutionPolicy Bypass -File ".\setup.ps1"
# ============================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Continue"
$script:LogFile   = "$env:TEMP\autoinstall.log"
$script:StartTime = Get-Date

# Detect Windows edition name at runtime
$_os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$script:WinName = if ($_os) { $_os.Caption.Trim() } else { "Windows" }

# ============================================================
#  LOGGING
# ============================================================
function Write-Log($msg) {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$ts  $msg" | Out-File -FilePath $script:LogFile -Append -Encoding UTF8
}

# ============================================================
#  UI HELPERS
# ============================================================
function Write-Header {
    Clear-Host
    $title  = "  Auto Installer - $script:WinName  "
    $border = "=" * ($title.Length)
    Write-Host ""
    Write-Host "  $border" -ForegroundColor Cyan
    Write-Host $title      -ForegroundColor Cyan
    Write-Host "  $border" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section($title) {
    Write-Host ""
    Write-Host "  ---- $title ----" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Progress-Header($current, $total, $name) {
    $pct = [math]::Round(($current / $total) * 100)
    $filled = [math]::Round($pct / 5)
    $bar = ("=" * $filled).PadRight(20, "-")
    Write-Host ""
    Write-Host "  [$bar] $pct%  ($current/$total)  $name" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step($msg) {
    Write-Host "  [>>] $msg" -ForegroundColor Yellow
    Write-Log "STEP  $msg"
}

function Write-OK($msg) {
    Write-Host "  [OK] $msg" -ForegroundColor Green
    Write-Log "OK    $msg"
}

function Write-Skip($msg) {
    Write-Host "  [--] $msg" -ForegroundColor DarkGray
    Write-Log "SKIP  $msg"
}

function Write-Fail($msg) {
    Write-Host "  [!!] $msg" -ForegroundColor Red
    Write-Log "FAIL  $msg"
}

function Write-Info($msg) {
    Write-Host "  [i]  $msg" -ForegroundColor DarkCyan
    Write-Log "INFO  $msg"
}

function Get-Elapsed {
    $e = (Get-Date) - $script:StartTime
    if ($e.TotalMinutes -ge 1) { return "$([math]::Floor($e.TotalMinutes))m $($e.Seconds)s" }
    return "$([math]::Round($e.TotalSeconds))s"
}

# ============================================================
#  DOWNLOAD (with progress + retry + GitHub redirect fix)
# ============================================================
function Download-File($url, $dest, [int]$maxRetry = 2) {
    $fileName = Split-Path $dest -Leaf
    $isGitHub = $url -match "github\.com|githubusercontent\.com"

    for ($attempt = 1; $attempt -le ($maxRetry + 1); $attempt++) {
        if ($attempt -gt 1) {
            Write-Info "Retry $($attempt - 1)/$maxRetry ..."
            Start-Sleep -Seconds 3
        }
        try {
            if (-not $isGitHub) {
                # BITS - best for large files, shows real % progress
                Import-Module BitsTransfer -ErrorAction Stop
                Start-BitsTransfer -Source $url -Destination $dest `
                    -DisplayName "Downloading $fileName" `
                    -Description $url `
                    -ErrorAction Stop
            } else {
                # GitHub uses 302 redirects - BITS fails silently, use WebClient instead
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "Mozilla/5.0")
                $wc.add_DownloadProgressChanged({
                    param($s, $e)
                    $pct = $e.ProgressPercentage
                    $dl  = [math]::Round($e.BytesReceived / 1MB, 1)
                    $tot = if ($e.TotalBytesToReceive -gt 0) {
                        [math]::Round($e.TotalBytesToReceive / 1MB, 1)
                    } else { "?" }
                    Write-Progress -Activity "  Downloading $fileName" `
                        -Status "$dl MB / $tot MB  ($pct%)" `
                        -PercentComplete ([math]::Max(0, [math]::Min(100, $pct)))
                })
                $wc.add_DownloadFileCompleted({
                    Write-Progress -Activity "  Downloading $fileName" -Completed
                })
                $wc.DownloadFileAsync([uri]$url, $dest)
                while ($wc.IsBusy) { Start-Sleep -Milliseconds 300 }
                $wc.Dispose()
            }

            # Verify file downloaded and not empty
            if (-not (Test-Path $dest) -or (Get-Item $dest).Length -lt 1024) {
                throw "Downloaded file is missing or too small - possible redirect/network issue"
            }
            return  # success
        } catch {
            if ($attempt -le $maxRetry) {
                Write-Fail "Download failed (attempt $attempt): $_"
            } else {
                throw "Download failed after $($maxRetry + 1) attempts: $_"
            }
        }
    }
}

# ============================================================
#  REGISTRY HELPERS
# ============================================================
function Get-UninstallEntries {
    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    return Get-ItemProperty $paths -ErrorAction SilentlyContinue
}

function Is-Installed($name) {
    $found = Get-UninstallEntries | Where-Object { $_.DisplayName -like "*$name*" }
    return [bool]($found)
}

# ============================================================
#  PROGRAM DEFINITIONS
# ============================================================
$programs = @(
    @{ Name = ".NET Framework 4.8";      Check = "NET48";                   Special = $true  }
    @{ Name = "7-Zip";                   Check = "7-Zip";                   Special = $false }
    @{ Name = "Discord";                 Check = "Discord";                 Special = $false }
    @{ Name = "Steam";                   Check = "Steam";                   Special = $false }
    @{ Name = "Rockstar Games Launcher"; Check = "Rockstar Games Launcher"; Special = $false }
    @{ Name = "Razer Synapse";           Check = "Razer Synapse";           Special = $false }
    @{ Name = "FXSound";                 Check = "FXSound";                 Special = $false }
    @{ Name = "LosslessCut";             Check = "LOSSLESSCUT";             Special = $true  }
    @{ Name = "NVIDIA Driver 610.47";    Check = "NVIDIA_DRIVER";           Special = $true  }
)

# ============================================================
#  INSTALL-STATUS CHECKS
# ============================================================
function Check-NET48 {
    $release = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" `
                -ErrorAction SilentlyContinue).Release
    return ($release -ge 528040)
}

function Check-NvidiaDriver {
    $found = Get-UninstallEntries |
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
#  INSTALL PROGRAMS
# ============================================================
function Start-Install {
    Write-Header
    Write-Log "=== Install session started ==="
    Write-Section "Scanning installed programs"

    $toInstall = @()
    $entries = Get-UninstallEntries  # single registry read for all checks

    foreach ($prog in $programs) {
        $installed = Get-InstalledStatus $prog
        if ($installed) {
            Write-Host "  [OK] $($prog.Name)" -ForegroundColor Green
        } else {
            Write-Host "  [--] $($prog.Name)" -ForegroundColor DarkGray
            $toInstall += $prog
        }
    }
    Write-Host ""

    if ($toInstall.Count -eq 0) {
        Write-Host "  All programs are already installed!" -ForegroundColor Green
        Write-Host ""
        Read-Host "  Press Enter to continue"
        return
    }

    Write-Host "  $($toInstall.Count) program(s) to install:" -ForegroundColor Yellow
    foreach ($prog in $toInstall) {
        Write-Host "    - $($prog.Name)" -ForegroundColor Yellow
    }
    Write-Host ""

    $Host.UI.RawUI.FlushInputBuffer()
    $confirm = ""
    while ($confirm -notmatch "^[YyNn]$") {
        $confirm = (Read-Host "  Proceed? (Y/N)").Trim()
    }
    if ($confirm -notmatch "^[Yy]$") {
        Write-Host "  Cancelled." -ForegroundColor DarkGray
        return
    }

    $tmp = "$env:TEMP\autoinstall"
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $results = @()
    $idx = 0

    try {
        foreach ($prog in $toInstall) {
            $idx++
            $ok = $false

            Write-Header
            Write-Progress-Header $idx $toInstall.Count $prog.Name
            Write-Log "--- Installing: $($prog.Name) ($idx/$($toInstall.Count)) ---"

            try {
                switch ($prog.Check) {

                # ── .NET 4.8 ──────────────────────────────────
                "NET48" {
                    $file = "$tmp\ndp48.exe"
                    Write-Step "Downloading .NET Framework 4.8 ..."
                    Download-File "https://go.microsoft.com/fwlink/?LinkId=2085155" $file
                    Write-Step "Installing (may take a few minutes) ..."
                    $p = Start-Process $file -ArgumentList "/q /norestart" -Wait -PassThru
                    if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
                        Write-OK ".NET Framework 4.8 installed"
                        $ok = $true
                        $results += [PSCustomObject]@{ Name = $prog.Name; OK = $ok }
                        Write-Host ""
                        Write-Host "  !! REBOOT required - run this script again after reboot !!" -ForegroundColor Red
                        Write-Host ""
                        Read-Host "  Press Enter to exit"
                        exit 0
                    } else {
                        Write-Fail ".NET installer exited with code $($p.ExitCode)"
                    }
                }

                # ── 7-Zip ──────────────────────────────────────
                "7-Zip" {
                    $file = "$tmp\7zip.exe"
                    Write-Step "Fetching latest 7-Zip version ..."
                    $page  = Invoke-WebRequest "https://www.7-zip.org/download.html" -UseBasicParsing -ErrorAction Stop
                    $match = [regex]::Match($page.Content, 'href="(a/7z[\d]+-x64\.exe)"')
                    $url   = if ($match.Success) { "https://www.7-zip.org/" + $match.Groups[1].Value } else { "https://www.7-zip.org/a/7z2407-x64.exe" }
                    Write-Step "Downloading $url ..."
                    Download-File $url $file
                    Start-Process $file -ArgumentList "/S" -Wait
                    Write-OK "7-Zip installed"
                    $ok = $true
                }

                # ── Discord ────────────────────────────────────
                "Discord" {
                    $file = "$tmp\DiscordSetup.exe"
                    Write-Step "Downloading Discord ..."
                    Download-File "https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=win&arch=x86" $file
                    Write-Step "Installing Discord ..."
                    Start-Process $file -ArgumentList "--silent" -Wait
                    Write-OK "Discord installed"
                    $ok = $true
                }

                # ── Steam ──────────────────────────────────────
                "Steam" {
                    $file = "$tmp\SteamSetup.exe"
                    Write-Step "Downloading Steam ..."
                    Download-File "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe" $file
                    Write-Step "Installing Steam ..."
                    Start-Process $file -ArgumentList "/S" -Wait
                    Write-OK "Steam installed"
                    $ok = $true
                }

                # ── Rockstar ───────────────────────────────────
                "Rockstar Games Launcher" {
                    $file = "$tmp\RockstarLauncher.exe"
                    Write-Step "Downloading Rockstar Games Launcher ..."
                    Download-File "https://gamedownloads.rockstargames.com/public/installer/Rockstar-Games-Launcher.exe" $file
                    Write-Step "Installing (launcher may open briefly) ..."
                    $proc = Start-Process $file -ArgumentList "/SILENT /LANG=1033" -PassThru
                    $proc.WaitForExit()
                    Write-Step "Waiting for Rockstar to finish setup ..."
                    $deadline = (Get-Date).AddMinutes(5)
                    while (-not (Is-Installed "Rockstar Games Launcher") -and (Get-Date) -lt $deadline) {
                        Start-Sleep -Seconds 5
                    }
                    if (Is-Installed "Rockstar Games Launcher") {
                        Write-OK "Rockstar Games Launcher installed"
                        $ok = $true
                    } else {
                        Write-Fail "Rockstar: timed out - continuing"
                    }
                }

                # ── Razer Synapse ──────────────────────────────
                # Note: Razer Synapse does NOT support /S silent flag - GUI required
                "Razer Synapse" {
                    $file = "$tmp\RazerSynapse.exe"
                    Write-Step "Downloading Razer Synapse ..."
                    Download-File "https://dl.razerzone.com/drivers/Synapse4/RazerSynapseInstaller.exe" $file
                    Write-Step "Installing Razer Synapse (GUI will open - click through) ..."
                    Start-Process $file -Wait
                    Write-OK "Razer Synapse installed"
                    $ok = $true
                }

                # ── FXSound ────────────────────────────────────
                # Note: FXSound does NOT support /S silent flag - GUI required
                "FXSound" {
                    $file = "$tmp\fxsound_setup.exe"
                    Write-Step "Downloading FXSound ..."
                    Download-File "https://github.com/fxsound2/fxsound-app/releases/download/latest/fxsound_setup.exe" $file
                    Write-Step "Installing FXSound (GUI will open - click through) ..."
                    Start-Process $file -Wait
                    Write-OK "FXSound installed"
                    $ok = $true
                }

                # ── LosslessCut ────────────────────────────────
                "LOSSLESSCUT" {
                    Write-Step "Fetching latest LosslessCut version from GitHub ..."
                    $api   = Invoke-RestMethod "https://api.github.com/repos/mifi/lossless-cut/releases/latest"
                    $asset = $api.assets | Where-Object { $_.name -match "(?i)^LosslessCut-win-x64\.7z$" } | Select-Object -First 1
                    if ($null -eq $asset) {
                        Write-Fail "LosslessCut: asset not found in GitHub release"
                    } else {
                        $archive = "$tmp\LosslessCut.7z"
                        $dest    = "C:\Program Files\LosslessCut"
                        Write-Step "Downloading $($asset.name) ..."
                        Download-File $asset.browser_download_url $archive
                        $7z = if (Test-Path "C:\Program Files\7-Zip\7z.exe") {
                            "C:\Program Files\7-Zip\7z.exe"
                        } else { "C:\Program Files (x86)\7-Zip\7z.exe" }
                        Write-Step "Extracting to $dest ..."
                        Start-Process $7z -ArgumentList "x `"$archive`" -o`"$dest`" -y" -Wait
                        Write-OK "LosslessCut extracted"
                        $exe = Get-ChildItem $dest -Filter "LosslessCut.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($exe) {
                            $shortcut = "$env:PUBLIC\Desktop\LosslessCut.lnk"
                            $wsh = New-Object -ComObject WScript.Shell
                            $lnk = $wsh.CreateShortcut($shortcut)
                            $lnk.TargetPath = $exe.FullName
                            $lnk.Save()
                            Write-OK "Desktop shortcut created"
                        }
                        $ok = $true
                    }
                }

                # ── NVIDIA Driver ──────────────────────────────
                "NVIDIA_DRIVER" {
                    $file = "$tmp\NvidiaSetup.exe"
                    Write-Step "Downloading NVIDIA Driver 610.47 (~700 MB) ..."
                    Download-File "https://us.download.nvidia.com/Windows/610.47/610.47-desktop-win10-win11-64bit-international-dch-whql.exe" $file
                    Write-Step "Installing silently (3-5 minutes) ..."
                    $p = Start-Process $file -ArgumentList "-s -noreboot" -Wait -PassThru
                    if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 14) {
                        Write-OK "NVIDIA Driver 610.47 installed  (reboot required)"
                        $ok = $true
                    } else {
                        Write-Fail "NVIDIA installer exited with code $($p.ExitCode)"
                    }
                }

                } # end switch

            } catch {
                Write-Fail "Unexpected error: $_"
            }

            # Always record result - even if exception occurred above
            $results += [PSCustomObject]@{ Name = $prog.Name; OK = $ok }

            # Clean up this program's temp file immediately to save disk space
            Get-ChildItem $tmp -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        }

    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ── SUMMARY ───────────────────────────────────────────────
    $elapsed   = Get-Elapsed
    $failCount = ($results | Where-Object { -not $_.OK }).Count
    $okCount   = ($results | Where-Object { $_.OK }).Count

    Write-Header
    Write-Section "Installation Summary  ($elapsed elapsed)"

    foreach ($r in $results) {
        if ($r.OK) {
            Write-Host "  [OK] $($r.Name)" -ForegroundColor Green
        } else {
            Write-Host "  [!!] $($r.Name)  - FAILED" -ForegroundColor Red
        }
    }

    Write-Host ""
    if ($failCount -eq 0) {
        Write-Host "  All $okCount program(s) installed successfully!" -ForegroundColor Green
    } else {
        Write-Host "  $okCount OK  /  $failCount failed  -  see log: $script:LogFile" -ForegroundColor Yellow
    }

    $rebootNeeded = ($results | Where-Object { $_.Name -match "NVIDIA" -and $_.OK })
    if ($rebootNeeded) {
        Write-Host ""
        Write-Host "  ** Reboot recommended (NVIDIA driver installed) **" -ForegroundColor Cyan
    }
    Write-Host ""
    Write-Log "=== Session ended. OK=$okCount FAIL=$failCount elapsed=$elapsed ==="
}

# ============================================================
#  IMPORT FIVEM SETTINGS
# ============================================================
function Start-ImportFiveM {
    Write-Header
    Write-Log "=== FiveM import started ==="
    Write-Section "Importing FiveM settings from GitHub"

    $cfxDest = "$env:APPDATA\CitizenFX"
    $cfxBase = "https://raw.githubusercontent.com/YamadaX9999/setuppc/main/CitizenFX"

    $cfxFiles = @("fivem.cfg","gta5_settings.xml","camera_save_structure.xml","ros_id.dat")
    $kvsFiles = @("000005.ldb","000008.ldb","000011.ldb","000014.log","CURRENT","LOCK","MANIFEST-000013")

    New-Item -ItemType Directory -Force -Path $cfxDest | Out-Null
    New-Item -ItemType Directory -Force -Path "$cfxDest\kvs" | Out-Null

    $allOk    = $true
    $total    = $cfxFiles.Count + $kvsFiles.Count
    $current  = 0

    foreach ($file in $cfxFiles) {
        $current++
        try {
            Write-Step "[$current/$total] $file"
            Download-File "$cfxBase/$file" "$cfxDest\$file"
            Write-OK "$file"
        } catch {
            Write-Fail "Failed: $file - $_"
            $allOk = $false
        }
    }

    foreach ($file in $kvsFiles) {
        $current++
        try {
            Write-Step "[$current/$total] kvs\$file"
            Download-File "$cfxBase/kvs/$file" "$cfxDest\kvs\$file"
            Write-OK "kvs\$file"
        } catch {
            Write-Fail "Failed: kvs\$file - $_"
            $allOk = $false
        }
    }

    Write-Host ""
    if ($allOk) {
        Write-OK "All FiveM settings imported!"
    } else {
        Write-Fail "Some files failed - check log: $script:LogFile"
    }
    Write-Log "=== FiveM import ended. allOk=$allOk ==="
}

# ============================================================
#  MAIN MENU  (loops until user exits)
# ============================================================
function Show-Menu {
    Write-Header
    Write-Host "  Log file: $script:LogFile" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Select an option:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    1.  Install programs" -ForegroundColor Yellow
    Write-Host "    2.  Import FiveM settings" -ForegroundColor Yellow
    Write-Host "    3.  Both (install then import)" -ForegroundColor Yellow
    Write-Host "    4.  Exit" -ForegroundColor DarkGray
    Write-Host ""
    $Host.UI.RawUI.FlushInputBuffer()
    $c = (Read-Host "  Choice (1/2/3/4)").Trim()
    return $c
}

while ($true) {
    $choice = ""
    while ($choice -notmatch "^[1234]$") {
        $choice = Show-Menu
    }
    switch ($choice) {
        "1" { Start-Install }
        "2" { Start-ImportFiveM }
        "3" { Start-Install; Start-ImportFiveM }
        "4" {
            Write-Host ""
            Write-Host "  Bye!" -ForegroundColor DarkGray
            Write-Host ""
            exit 0
        }
    }
    Write-Host ""
    Read-Host "  Press Enter to return to menu"
}
