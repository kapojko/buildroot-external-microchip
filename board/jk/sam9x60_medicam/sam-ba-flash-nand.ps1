#Requires -Version 5.1
<#
.SYNOPSIS
    Flash SAM9X60 MediCam NAND image via SAM-BA over USB-CDC serial.

.DESCRIPTION
    Recovery path B (PLAN 2.7 / F4). Primary path is the SD rescue card +
    flash-nand.sh; SAM-BA is only for when the SD path is unavailable
    (e.g. dead rootfs, first-ever bring-up). It writes the full raw
    medicam-nand.img over USB-CDC, which is SLOW: ~1 GiB for the 8 Gbit
    test bed (plan F21: prefer the SD rescue path).

    Multi-call SAM-BA flash following the procedure documented at:
      D:\Programs\sam-ba_v3.9.1\doc\sam9x60.html
    (section "Programming a raw NAND flash")

    Sequence per call:
      1. sam-ba -p serial -b sam9x60d1g -t 5 -a lowlevel
      2. sam-ba -p serial -b sam9x60d1g -t 5 -a nandflash -c erase
      3. sam-ba -p serial -b sam9x60d1g -t 5 -a nandflash -c write:FILE:0x0
      4. sam-ba -p serial -b sam9x60d1g -t 5 -a nandflash -c verify:FILE:0x0

    Board preset (F4):
      -b sam9x60d1g  -> SAM-BA's qml/SAMBA/Device/SAM9X60/SAM9X60.qml
                       maps sam9x60d1g to extram.preset 8 = W971GG6SB, which
                       is exactly the SiP's W971G16SG2-5I DDR2. Using
                       sam9x60-ek (preset 12 = W972GG6KB) is the wrong chip.
      -a nandflash:1:8:0xc2605007  (no ::no_extram) -> the applet buffer now
                       runs in DRAM, so writes are much faster than the old
                       internal-SRAM fallback. 0xc2605007 = 8 sectors/page,
                       8-bit ECC, per F4 (verify against the stage-2 PMECC
                       header during session 3 if NAND boot misbehaves).

.PARAMETER ComPort
    Target COM port (e.g. COM18). If omitted, the script attempts auto-detection
    of a Microchip/SAM-BA USB CDC device. Override with env SAM_BA_COM.

.PARAMETER SambaDir
    Path to SAM-BA install directory (must contain sam-ba.exe). If omitted,
    uses env SAM_BA_DIR, then auto-detection, then default D:\Programs\sam-ba_v3.9.1.

.PARAMETER WslImagePath
    UNC path to the NAND image inside WSL. Defaults to
    \\wsl$\Debian\home\<user>\src\buildroot-mchp\output-nand\images\medicam-nand.img

.PARAMETER WorkImagePath
    Windows-side working path where the image is copied before flashing.
    Defaults to D:\Temp\medicam-nand.img.

.PARAMETER WslDistro
    WSL distribution name. Defaults to "Debian".

.EXAMPLE
    PS> .\sam-ba-flash-nand.ps1
    Auto-detects everything, uses defaults.

.EXAMPLE
    PS> .\sam-ba-flash-nand.ps1 -ComPort COM5
    Uses COM5 explicitly.

.EXAMPLE
    PS> .\sam-ba-flash-nand.ps1 -Erase
    Run lowlevel + erase only, then stop (no write/verify).

.EXAMPLE
    PS> $env:SAM_BA_DIR = 'D:\tools\sam-ba_v3.9.1'; .\sam-ba-flash-nand.ps1
    Uses a custom SAM-BA install location.

.PARAMETER SkipVerify
    Skip the post-write verify (read-back) step. With the image at ~1 GiB the
    verify is a long extra pass; consider -SkipVerify after the first success.

.NOTES
    Requires PowerShell 5.1+ on Windows 10/11.
    WSL must be installed and the build artifacts must exist at $WslImagePath.
#>

[CmdletBinding()]
param(
    [string]$ComPort,
    [string]$SambaDir,
    [string]$WslImagePath,
    [string]$WorkImagePath = 'D:\Temp\medicam-nand.img',
    [string]$WslDistro = 'Debian',
    [switch]$Erase,
    [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Pretty printing
# ---------------------------------------------------------------------------
function Write-Step   { param($msg) Write-Host "[$([DateTime]::Now.ToString('HH:mm:ss'))] $msg" -ForegroundColor Cyan }
function Write-Ok     { param($msg) Write-Host "  [OK]  $msg" -ForegroundColor Green }
function Write-Warn   { param($msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Err    { param($msg) Write-Host "  [FAIL] $msg" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# Locate SAM-BA installation
# ---------------------------------------------------------------------------
function Resolve-SambaDir {
    param([string]$Override)

    $candidates = @()
    if ($Override)            { $candidates += $Override }
    if ($env:SAM_BA_DIR)      { $candidates += $env:SAM_BA_DIR }
    $candidates += 'D:\Programs\sam-ba_v3.9.1'
    $candidates += 'C:\Program Files (x86)\Microchip\sam-ba_v3.9.1'
    $candidates += 'C:\Program Files\Microchip\sam-ba_v3.9.1'

    foreach ($dir in $candidates | Select-Object -Unique) {
        if (-not $dir) { continue }
        $exe = Join-Path -Path $dir -ChildPath 'sam-ba.exe'
        if (Test-Path -LiteralPath $exe) {
            return (Resolve-Path -LiteralPath $dir).ProviderPath
        }
    }

    throw "sam-ba.exe not found. Searched:`n  $($candidates -join "`n  ")`nSet -SambaDir or `$env:SAM_BA_DIR."
}

# ---------------------------------------------------------------------------
# Locate COM port (Microchip USB CDC)
# ---------------------------------------------------------------------------
function Resolve-ComPort {
    param([string]$Override)

    if ($Override)            { return $Override }
    if ($env:SAM_BA_COM)      { return $env:SAM_BA_COM }

    $pnpPorts = @()
    try {
        $pnpPorts = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop |
                    Where-Object { $_.PNPClass -eq 'Ports' -and $_.Name -match '\(COM(\d+)\)' })
    } catch {
        $pnpPorts = @()
    }

    $ports = @($pnpPorts | ForEach-Object {
        if ($_.Name -match '\((COM\d+)\)') {
            [pscustomobject]@{
                DeviceID = $Matches[1]
                Name     = ($_.Name -replace '\s*\(COM\d+\)\s*$', '').Trim()
                Caption  = $_.Caption
            }
        }
    })

    $microchip = @($ports | Where-Object {
        $_.Name -match 'Microchip|SAM-?BA|Atmel|AT91|microchip|CH340|CP210|FTDI|CDC'
    })

    if ($microchip.Count -eq 1) {
        Write-Ok "Auto-detected COM port: $($microchip[0].DeviceID) ($($microchip[0].Name))"
        return $microchip[0].DeviceID
    }

    if ($microchip.Count -gt 1) {
        Write-Warn "Multiple Microchip COM ports found; please disambiguate with -ComPort:"
        $microchip | ForEach-Object { Write-Host "    $($_.DeviceID): $($_.Name)" }
        throw "Ambiguous COM port selection."
    }

    Write-Warn "No Microchip USB CDC device detected."
    if ($ports.Count -gt 0) {
        Write-Host "Available COM ports:"
        $ports | ForEach-Object { Write-Host "    $($_.DeviceID): $($_.Name)" }
    } else {
        Write-Host "No serial ports at all (USB cable unplugged? driver missing?)."
        Write-Host "Check Device Manager -> 'Ports (COM & LPT)'."
    }
    throw "Pass -ComPort explicitly."
}

# ---------------------------------------------------------------------------
# Resolve WSL image path (if user did not override)
# ---------------------------------------------------------------------------
function Resolve-WslImagePath {
    param(
        [string]$Override,
        [string]$Distro,
        [string]$User
    )

    if ($Override) { return $Override }

    if (-not $User) {
        $User = (& wsl.exe -d $Distro -- whoami 2>$null).Trim()
        if (-not $User) {
            $User = $env:USERNAME.ToLower()
        }
    }
    return "/home/$User/src/buildroot-mchp/output-nand/images/medicam-nand.img"
}

# ---------------------------------------------------------------------------
# Copy image from WSL to a Windows path using wsl.exe (avoids flaky UNC provider)
# ---------------------------------------------------------------------------
function Copy-FromWsl {
    param(
        [Parameter(Mandatory)][string]$WslPath,
        [Parameter(Mandatory)][string]$WindowsPath,
        [Parameter(Mandatory)][string]$Distro
    )

    if ($WindowsPath -notmatch '^([A-Za-z]):\\(.*)$') {
        throw "WorkImagePath must be a Windows drive path (e.g. D:\Temp\foo.img), got: $WindowsPath"
    }
    $drive = $Matches[1].ToLower()
    $rest  = $Matches[2] -replace '\\', '/'
    $wslDest = "/mnt/$drive/$rest"

    $parent = Split-Path -Parent $WindowsPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $srcSize = & wsl.exe -d $Distro -- stat -c '%s' $WslPath 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $srcSize) {
        throw "Cannot stat WSL image '$WslPath' in distro '$Distro'. Check path and distro name."
    }
    $srcSize = [int64]$srcSize

    & wsl.exe -d $Distro -- cp -f $WslPath $wslDest
    if ($LASTEXITCODE -ne 0) {
        throw "wsl cp failed: $WslPath -> $wslDest"
    }

    $dstSize = (Get-Item -LiteralPath $WindowsPath).Length
    if ($dstSize -ne $srcSize) {
        Remove-Item -LiteralPath $WindowsPath -Force -ErrorAction SilentlyContinue
        throw "Size mismatch after copy: $dstSize vs $srcSize"
    }
    return $dstSize
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
try {
    Write-Host ""
    Write-Host "=== SAM9X60 MediCam - NAND Flash via SAM-BA (recovery path) ===" -ForegroundColor Magenta
    Write-Host ""

    # 1. Resolve SAM-BA
    $sambaDir = Resolve-SambaDir -Override $SambaDir
    $sambaExe = Join-Path $sambaDir 'sam-ba.exe'
    Write-Ok "SAM-BA:      $sambaExe"

    # 2. Resolve COM port
    $resolvedCom = Resolve-ComPort -Override $ComPort

    # 3. Resolve WSL image path
    $wslImg = Resolve-WslImagePath -Override $WslImagePath -Distro $WslDistro
    Write-Ok "WSL image:   $wslImg"

    # 4. Validate image source via wsl.exe (avoids flaky UNC provider)
    Write-Step "Resolving image inside WSL distro '$WslDistro' ..."
    $wslSize = & wsl.exe -d $WslDistro -- stat -c '%s' $wslImg 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $wslSize) {
        throw "Cannot stat WSL image '$wslImg' in distro '$WslDistro'.`nCheck your build output and -WslDistro."
    }
    $wslSize = [int64]$wslSize
    Write-Ok "Source size: $([math]::Round($wslSize/1MB,2)) MiB ($wslSize bytes)"

    # 5. Copy image to working path via wsl.exe (cross-fs copy, no UNC provider)
    Write-Step "Copying image -> $WorkImagePath (via wsl.exe)"
    $copiedSize = Copy-FromWsl -WslPath $wslImg -WindowsPath $WorkImagePath -Distro $WslDistro
    Write-Ok "Copied: $([math]::Round($copiedSize/1MB,2)) MiB"
    Write-Host ""

    # 7. Build NAND applet args (F4): board preset sam9x60d1g (DDR2 W971G16SG2
    #    preset 8), NAND applet nandflash:[ioset]:[bus_width]:[pmecc_cfg], no
    #    ::no_extram so the applet buffer lives in DRAM.
    $nandArgs = "nandflash:1:8:0xc2605007"
    # Buffer limit for the applet. With the buffer in DRAM (128 MiB SiP) a
    # large value is fine; this only bounds the applet's transfer buffer.
    $bufferLimit = 2097152
    Write-Ok "NAND applet: $nandArgs"
    Write-Ok "Buffer limit: $bufferLimit bytes (-L)"
    Write-Host ""

    # 8. Run SAM-BA in multi-call sequence per sam9x60.html docs.
    $imageDir  = Split-Path -Parent $WorkImagePath
    $imageFile = Split-Path -Leaf   $WorkImagePath

    $commonArgs = @(
        "-p", "serial:$resolvedCom",
        "-b", "sam9x60d1g",
        "-t", "5"
    )

    function Invoke-Samba {
        param(
            [Parameter(Mandatory)][string[]]$SambaArgs,
            [string]$Description,
            [string]$WorkingDirectory
        )
        Write-Step "SAM-BA: $Description"
        $params = @{
            FilePath       = $sambaExe
            ArgumentList   = $SambaArgs
            NoNewWindow    = $true
            Wait           = $true
            PassThru       = $true
        }
        if ($WorkingDirectory) { $params.WorkingDirectory = $WorkingDirectory }
        $proc = Start-Process @params
        return $proc.ExitCode
    }

    # Step a: initialize clock tree (lowlevel applet)
    $rc = Invoke-Samba -SambaArgs ($commonArgs + @("-a", "lowlevel")) -Description "Initialize lowlevel (clock tree)"
    if ($rc -ne 0) {
        Write-Err "lowlevel applet failed (exit $rc)"
        exit $rc
    }

    # Step b: erase entire NAND
    Write-Step "Erasing entire NAND (this takes ~30s)..."
    $eraseArgs = $commonArgs + @("-a", $nandArgs, "-c", "erase")
    $rc = Invoke-Samba -SambaArgs $eraseArgs -Description "NAND erase (entire chip)"
    if ($rc -ne 0) {
        Write-Err "NAND erase failed (exit $rc)"
        exit $rc
    }

    if ($Erase) {
        Write-Ok "Erase-only mode: stopping after erase as requested."
        exit 0
    }

    # Step c: write image to NAND offset 0. ~1 GiB over USB-CDC: expect a long
    # transfer (plan F21 — this is why the SD rescue path is the primary one).
    Write-Step "Writing image to NAND offset 0 (this takes a long time for ~1 GiB)..."
    $writeArgs = $commonArgs + @(
        "-L", $bufferLimit,
        "-a", $nandArgs,
        "-c", "write:${imageFile}:0x0"
    )
    $rc = Invoke-Samba -SambaArgs $writeArgs -Description "NAND write (raw image)" -WorkingDirectory $imageDir
    if ($rc -ne 0) {
        Write-Err "NAND write failed (exit $rc)"
        exit $rc
    }

    # Step d: verify (read-back and compare). Skipped when -SkipVerify.
    if ($SkipVerify) {
        Write-Step "Skipping NAND verify (-SkipVerify)"
    } else {
        Write-Step "Verifying NAND contents (long read-back pass)..."
        $verifyArgs = $commonArgs + @(
            "-L", $bufferLimit,
            "-a", $nandArgs,
            "-c", "verify:${imageFile}:0x0"
        )
        $rc = Invoke-Samba -SambaArgs $verifyArgs -Description "NAND verify (read-back compare)" -WorkingDirectory $imageDir
        if ($rc -ne 0) {
            Write-Err "NAND verify failed (exit $rc)"
            exit $rc
        }
    }

    Write-Ok "SAM-BA completed successfully."
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Green
    Write-Host "  1. Power OFF the board (unplug DEBUG USB or press reset)."
    Write-Host "  2. Wait 5 seconds."
    Write-Host "  3. Power ON the board WITHOUT SD card inserted."
    Write-Host "  4. Connect serial terminal at 115200 8N1 to DEBUG USB."
    Write-Host "  5. You should see:"
    Write-Host "         RomBOOT"
    Write-Host "         AT91Bootstrap 4.0.11 ..."
    Write-Host "         ## Starting U-Boot ..."
    Write-Host "         U-Boot> _"
    Write-Host ""
    exit 0
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}
