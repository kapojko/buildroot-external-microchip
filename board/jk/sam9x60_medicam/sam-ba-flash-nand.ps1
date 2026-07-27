#Requires -Version 5.1
<#
.SYNOPSIS
    Flash SAM9X60 MediCam NAND image via SAM-BA over USB-CDC serial.

.DESCRIPTION
    Multi-call SAM-BA flash following the procedure documented at:
      D:\Programs\sam-ba_v3.9.1\doc\sam9x60.html
    (section "Programming a raw NAND flash")

    Sequence per call:
      1. sam-ba -p serial -b sam9x60-ek -t 5 -a lowlevel
      2. sam-ba -p serial -b sam9x60-ek -t 5 -a nandflash -c erase
      3. sam-ba -p serial -b sam9x60-ek -t 5 -a nandflash -c write:D:\Temp\medicam-nand.img:0x0
      4. sam-ba -p serial -b sam9x60-ek -t 5 -a nandflash -c verify:D:\Temp\medicam-nand.img:0x0

    Notes:
      - We use -b sam9x60-ek as a generic SAM9X60 board preset (no DDR
        config) and override the NAND applet with -a nandflash:1:8:0xc2605007
        to match our MT29F8G08 geometry (8-bit bus, ioset 1, header
        0xc2605007 = 8 sectors/page, 8-bit ECC, spare 256).
      - extram is intentionally skipped. Our chip is W971G16SG2-5I which
        has no matching DDR preset in SAM-BA 3.9; the nandflash applet
        falls back to internal RAM buffer with a warning.
      - The full medicam-nand.img is written as one block because our
        layout has PMECC baked into bootstrap.bin.pmecc, and u-boot/dt/
        kernel/rootfs are raw (no PMECC required for non-bootstrap
        images). See PLAN_NAND.md for partition layout.

.PARAMETER ComPort
    Target COM port (e.g. COM18). If omitted, the script attempts auto-detection
    of a Microchip/SAM-BA USB CDC device. Override with env SAM_BA_COM.

.PARAMETER SambaDir
    Path to SAM-BA install directory (must contain sam-ba.exe). If omitted,
    uses env SAM_BA_DIR, then auto-detection, then default D:\Programs\sam-ba_v3.9.1.

.PARAMETER WslImagePath
    UNC path to the NAND image inside WSL. Defaults to
    \\wsl$\Debian\home\<user>\src\buildroot-mchp\output\images\medicam-nand.img

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
    Skip the post-write verify (read-back) step. Useful when the
    applet buffer is in internal SRAM (~4 KiB) because verify is
    ~30 minutes extra and adds no value beyond 'does the board
    boot?'.

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

    # Win32_PnPEntity under class "Ports (COM & LPT)" is the reliable way to
    # enumerate USB CDC COM ports on Windows 10/11. Win32_SerialPort is legacy
    # and returns empty for many USB CDC devices.
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

    # Prefer devices that mention Microchip / SAM-BA / CDC / common
    # USB-UART bridge chips used on evaluation boards and custom designs.
    # AT91 matches the native SAM-BA USB CDC descriptor ("AT91 USB to
    # Serial Converter") exposed by Atmel/Microchip MPU ROM code.
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

    # Query the actual WSL user via `whoami` rather than guessing from
    # $env:USERNAME (Windows and WSL usernames often differ in case).
    if (-not $User) {
        $User = (& wsl.exe -d $Distro -- whoami 2>$null).Trim()
        if (-not $User) {
            # Fallback to Windows username lowercased
            $User = $env:USERNAME.ToLower()
        }
    }
    return "/home/$User/src/buildroot-mchp/output/images/medicam-nand.img"
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

    # Use the distro's /mnt/<drive>/... view to write directly to a Windows path.
    # Parse D:\Temp\foo.img -> /mnt/d/Temp/foo.img
    if ($WindowsPath -notmatch '^([A-Za-z]):\\(.*)$') {
        throw "WorkImagePath must be a Windows drive path (e.g. D:\Temp\foo.img), got: $WindowsPath"
    }
    $drive = $Matches[1].ToLower()
    $rest  = $Matches[2] -replace '\\', '/'
    $wslDest = "/mnt/$drive/$rest"

    # Ensure parent directory exists in WSL view of the Windows fs
    $parent = Split-Path -Parent $WindowsPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    # Get source size for verification (use Linux stat -c %s)
    $srcSize = & wsl.exe -d $Distro -- stat -c '%s' $WslPath 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $srcSize) {
        throw "Cannot stat WSL image '$WslPath' in distro '$Distro'. Check path and distro name."
    }
    $srcSize = [int64]$srcSize

    # Copy via cp (faster than cat for large files)
    & wsl.exe -d $Distro -- cp -f $WslPath $wslDest
    if ($LASTEXITCODE -ne 0) {
        throw "wsl cp failed: $WslPath -> $wslDest"
    }

    # Verify size on Windows side
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
    Write-Host "=== SAM9X60 MediCam - NAND Flash via SAM-BA ===" -ForegroundColor Magenta
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

    # 7. Build NAND applet args
    # Per SAM-BA docs (sam9x60.html), the nandflash applet takes
    #   nandflash:[ioset]:[bus_width]:[pmecc_cfg]:[memcfg_file]:[no_extram]
    # Our MT29F8G08 header 0xc2605007 = 8 sectors/page, 8-bit ECC,
    # spare 256. IOSET 1, 8-bit bus.
    # no_extram: force applet buffer to internal RAM, skip failed extram
    # probe (our DDR2 chip W971G16SG2-5I has no SAM-BA preset).
    $nandArgs = "nandflash:1:8:0xc2605007::no_extram"
    # -L sets applet buffer limit. Without extram, internal SRAM is ~64 KiB.
    # SAM-BA caps to actual available size. Larger buffer = fewer applet
    # round-trips = much faster writes (default is one NAND page = 4096 B).
    $bufferLimit = 131072
    Write-Ok "NAND applet: $nandArgs"
    Write-Ok "Buffer limit: $bufferLimit bytes (-L)"
    Write-Host ""

    # 8. Run SAM-BA in multi-call sequence per sam9x60.html docs.
    # Each call: lowlevel, erase, write, verify.
    # -b sam9x60-ek provides generic SAM9X60 setup without DDR.
    # SAM-BA -c write:FILE:OFFSET parser splits on ':' — Windows drive
    # letters (D:\...) break it. -w is QML-only so cannot be used here.
    # Workaround: set process working directory to image dir and pass
    # just the filename in the -c argument (no colon).
    $imageDir  = Split-Path -Parent $WorkImagePath
    $imageFile = Split-Path -Leaf   $WorkImagePath

    $commonArgs = @(
        "-p", "serial:$resolvedCom",
        "-b", "sam9x60-ek",
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

    # Step c: write image to NAND offset 0
    # medicam-nand.img is 128 MiB at D:\Temp\medicam-nand.img
    # Note: ${imageFile} brace syntax required because $imageFile:0x0
    # would be parsed as a PowerShell scope variable reference.
    # Process WorkingDirectory set to $imageDir so SAM-BA resolves the
    # relative filename — avoids colon in drive letter breaking -c parser.
    Write-Step "Writing image to NAND offset 0 (this takes 5-15 minutes)..."
    $writeArgs = $commonArgs + @(
        "-L", $bufferLimit,
        "-a", $nandArgs,
        "-c", "write:${imageFile}:0x0"
    )
    $rc = Invoke-Samba -SambaArgs $writeArgs -Description "NAND write 128 MiB" -WorkingDirectory $imageDir
    if ($rc -ne 0) {
        Write-Err "NAND write failed (exit $rc)"
        exit $rc
    }

    # Step d: verify (read-back and compare). Skipped when -SkipVerify
    # is passed; on the slow path (4 KiB SRAM1) this saves ~30 min.
    if ($SkipVerify) {
        Write-Step "Skipping NAND verify (-SkipVerify)"
    } else {
        Write-Step "Verifying NAND contents (this takes 5-15 minutes)..."
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
    Write-Host "If boot hangs after AT91Bootstrap, see README.md troubleshooting."
    Write-Host ""
    exit 0
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}