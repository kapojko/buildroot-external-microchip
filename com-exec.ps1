<#
.SYNOPSIS
    Run shell commands on the MediCam board through its DBGU serial console.

.DESCRIPTION
    Opens the board's COM port, makes sure a root shell is available
    (the console asks for a password after a logout / power-up), turns off
    tty echo so the markers are unambiguous, runs the given commands one by
    one and prints their output.

    Every command is wrapped in a unique marker pair:

        echo <BEGIN>; <command>; echo <END>

.EXAMPLE
    .\com-exec.ps1 -Command 'uname -a'
    .\com-exec.ps1 -Command 'devmem 0xf802c034'
    # several commands (PowerShell array):
    .\com-exec.ps1 -Command 'uname -a','ip -4 addr show eth0'

.NOTES
    - Default login: root / 1 (see PLAN_base_image.md).
    - Handles the console whether it is logged in, at "login:", or stuck at
      "Password:" (Ctrl-C is sent first).
    - Keep outputs short; serial transfers of large blobs are slow.
#>

[CmdletBinding()]
param(
    [string]   $Port        = 'COM3',
    [int]      $Baud        = 115200,
    [string]   $User        = 'root',
    [string]   $Password    = '1',
    [string[]] $Command     = @('uname -a'),
    [int]      $TimeoutSec  = 25,
    [switch]   $Quiet          # print only command output, no "===== cmd" headers
)

$ErrorActionPreference = 'Stop'
$script:sw = [System.Diagnostics.Stopwatch]::StartNew()
$ESC = [string][char]27
$CTRLC = [char]3

function Remove-Ansi {
    param([string] $Text)
    ($Text -replace ($ESC + '\[[0-9;?]*[A-Za-z]'), '' -replace ($ESC + '[78]'), '')
}

function Format-Output {
    param([string] $Text)
    (Remove-Ansi $Text) -replace "`r", '<CR>' -replace "`n", '<LF>'
}

function Read-Until {
    param(
        [System.IO.Ports.SerialPort] $P,
        [string] $Pattern,
        [int]    $TimeoutMs = ($TimeoutSec * 1000)
    )
    $sb = New-Object System.Text.StringBuilder
    $start = $script:sw.ElapsedMilliseconds
    while (($script:sw.ElapsedMilliseconds - $start) -lt $TimeoutMs) {
        try { $chunk = $P.ReadExisting() } catch { $chunk = '' }
        if ($chunk) {
            [void]$sb.Append($chunk)
            if ((Remove-Ansi $sb.ToString()) -match $Pattern) {
                return @{ Text = $sb.ToString(); Matched = $true }
            }
        }
        Start-Sleep -Milliseconds 40
    }
    return @{ Text = $sb.ToString(); Matched = $false }
}

function Send-Raw {
    param([System.IO.Ports.SerialPort] $P, [string] $Text, [int] $CharDelayMs = 2)
    foreach ($ch in $Text.ToCharArray()) {
        $P.Write([string]$ch)
        if ($CharDelayMs -gt 0) { Start-Sleep -Milliseconds $CharDelayMs }
    }
}

function Send-Line {
    param([System.IO.Ports.SerialPort] $P, [string] $Line, [int] $CharDelayMs = 2)
    Send-Raw $P $Line $CharDelayMs
    $P.Write("`r")
    Start-Sleep -Milliseconds 120
}

function Get-Shell {
    param([System.IO.Ports.SerialPort] $P)
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        # Ctrl-C + CR: escapes a half-finished login/password prompt and
        # prints a fresh prompt or a fresh "login:" line.
        Send-Raw $P ([string]$CTRLC) 0
        Start-Sleep -Milliseconds 200
        Send-Raw $P "`r" 0
        Start-Sleep -Milliseconds 200

        $r = Read-Until $P '(?i)(login:\s*$)|([#$]\s*$)' 3000
        $clean = Remove-Ansi $r.Text

        if ($clean -match '(?i)password:\s*$') { continue }

        if ($clean -match '(?i)login:\s*$') {
            Send-Line $P $User
            $r = Read-Until $P '(?i)password:\s*$' 8000
            if (-not $r.Matched) { continue }
            Send-Line $P $Password
            $r = Read-Until $P '[#$]\s*$' 15000
            if ($r.Matched) { return $true }
            continue
        }
        if ($clean -match '[#$]\s*$') { return $true }
    }
    return $false
}

function Disable-Echo {
    param([System.IO.Ports.SerialPort] $P)
    for ($i = 0; $i -lt 3; $i++) {
        Send-Line $P 'stty -echo'
        Start-Sleep -Milliseconds 250
        Send-Line $P 'echo __ECHO_PROBE__'
        $r = Read-Until $P '__ECHO_PROBE__.*__ECHO_PROBE__|__ECHO_PROBE__' 4000
        $clean = Remove-Ansi $r.Text
        # echo on  -> the command line appears too: two occurrences
        # echo off -> only the single marker printed by echo
        $count = ([regex]::Matches($clean, '__ECHO_PROBE__')).Count
        if ($count -ge 1 -and $clean -notmatch 'echo __ECHO_PROBE__;\s*echo') { return $true }
        Start-Sleep -Milliseconds 200
    }
    return $false
}

$portObj = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
$portObj.ReadTimeout  = 100
$portObj.WriteTimeout = 2000
$portObj.DtrEnable = $true
$portObj.RtsEnable = $true

try {
    $portObj.Open()
    Start-Sleep -Milliseconds 250
    $portObj.DiscardInBuffer()

    if (-not (Get-Shell $portObj)) {
        throw ("cannot get a shell on {0}" -f $Port)
    }
    if (-not (Disable-Echo $portObj)) {
        Write-Warning 'tty echo is still on; output may include the command echo'
    }

    # ---- run the commands -------------------------------------------------
    $n = 0
    foreach ($cmd in $Command) {
        $n++
        $begin = "__CMD${n}_BEGIN__"
        $end   = "__CMD${n}_END__"

        Send-Line $portObj ("echo $begin; $cmd; echo $end")
        $r = Read-Until $portObj ([regex]::Escape($end)) ($TimeoutSec * 1000)
        $text = Remove-Ansi ($r.Text -replace "`r", '')

        # keep only what is between the first BEGIN and the last END
        $text = $text -replace "(?s)^.*$([regex]::Escape($begin))", ''
        $text = $text -replace "(?s)$([regex]::Escape($end)).*$", ''
        $text = $text -replace '(?m)^\[[^\]]*\][#$]\s*$', ''

        if (-not $Quiet) { Write-Output ("===== " + $cmd) }
        Write-Output $text.TrimEnd()

        if (-not $r.Matched) {
            Write-Warning ("timeout waiting for the end of: {0}" -f $cmd)
        }
    }
}
finally {
    if ($portObj.IsOpen) {
        try { Send-Line $portObj 'stty echo' -CharDelayMs 0 } catch { }
        $portObj.Close()
    }
    $portObj.Dispose()
}
