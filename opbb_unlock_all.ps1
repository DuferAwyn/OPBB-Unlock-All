<#
One Piece: Burning Blood (Steam / PC) - save patch. No Python needed (PowerShell is built into Windows).

  Unlock ALL emblems (main + sub) and ALL titles, incl. DLC and Pirate Flag Battle, and/or set Beli to 999,999,999.

  How to run (game CLOSED; file saved in your Downloads folder):
    powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\opbb_unlock_all.ps1" check     (read only)
    powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\opbb_unlock_all.ps1" apply     (unlock all)
    powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\opbb_unlock_all.ps1" beli      (999,999,999 Beli)
    powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\opbb_unlock_all.ps1" restore   (undo everything)
  Optional 2nd argument: full path of SYSTEM-DATA if it isn't found automatically.

  Your original save is backed up to an OPBB_save_backup folder next to this script before anything changes.

  Save format: SYSTEM-DATA, 123072 bytes. Three check values (16-bit sum of 16-bit words; high byte at
  header+0, low byte at header+4): 0x40 covers 0x48..0x16880, 0x16880 covers 0x16888..end, 0x0 covers 0x8..end.
  Beli = 4-byte number at 0x80. Unlock bytes (0 locked, 2 unlocked): titles 0x41C4+id, main emblems 0x42BE+id,
  sub emblems 0x4354+id.
#>
param([string]$Command = 'check', [string]$SavePath = '')

$ErrorActionPreference = 'Stop'
$SaveSize = 123072
$BeliOffset = 0x80
$BeliMax = 999999999
$Unlocked = 2

function Fail([string]$msg) { Write-Host $msg -ForegroundColor Red; exit 1 }

# ---- real ids (from the game's progress_parameter.npk tables) ----
$TitleIds = @(0..205 | Where-Object { ($_ -lt 49 -or $_ -gt 51) -and ($_ -lt 124 -or $_ -gt 129) })   # 197
$MainIds  = @(0..129 | Where-Object { $_ -lt 49 -or $_ -gt 51 })                                     # 127
$SubIds   = @(0..56) + @(101..114)                                                                    # 71
$Groups = @(
    @{ Name = 'Titles';       Base = 0x41C4; Ids = $TitleIds; Len = 250 },
    @{ Name = 'Main emblems'; Base = 0x42BE; Ids = $MainIds;  Len = 150 },
    @{ Name = 'Sub emblems';  Base = 0x4354; Ids = $SubIds;   Len = 150 }
)

# ---- backup folder: next to this script (dev setup: older ..\save_backup if it already holds the backup) ----
$Here = $PSScriptRoot
$Legacy = Join-Path (Split-Path $Here -Parent) 'save_backup'
if (Test-Path (Join-Path $Legacy 'SYSTEM-DATA_before_unlockall')) { $BackupDir = $Legacy }
else { $BackupDir = Join-Path $Here 'OPBB_save_backup' }
$FirstBackup = Join-Path $BackupDir 'SYSTEM-DATA_before_unlockall'

# ---- check values ----
function Get-Sum16([byte[]]$d, [int]$start, [int]$end) {
    [long]$s = 0
    for ($i = $start; $i -lt $end; $i += 2) { $s += [int]$d[$i] + ([int]$d[$i + 1] -shl 8) }
    return [int]($s -band 0xFFFF)
}
function Set-Checks([byte[]]$d) {          # fixes the check values in place (order matters: 0x0 last)
    $n = $d.Length
    foreach ($r in @(@(0x40, 0x16880), @(0x16880, $n), @(0, $n))) {
        $h = $r[0]; $v = Get-Sum16 $d ($h + 8) $r[1]
        [Array]::Copy([BitConverter]::GetBytes([int]($v -shr 8)), 0, $d, $h, 4)
        [Array]::Copy([BitConverter]::GetBytes([int]($v -band 0xFF)), 0, $d, $h + 4, 4)
    }
}
function Test-Checks([byte[]]$d) {
    $c = [byte[]]$d.Clone(); Set-Checks $c
    foreach ($o in @(0, 0x40, 0x16880)) { for ($k = 0; $k -lt 8; $k++) { if ($c[$o + $k] -ne $d[$o + $k]) { return $false } } }
    return $true
}

# ---- find the save ----
function Find-Save {
    if ($SavePath) { return $SavePath }
    $roots = @()
    try { $sp = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath; if ($sp) { $roots += $sp } } catch {}
    $roots += 'C:\Program Files (x86)\Steam'
    foreach ($r in ($roots | Select-Object -Unique)) {
        $hits = @(Get-ChildItem -Path (Join-Path $r 'userdata\*\425220\remote\SYSTEM-DATA') -ErrorAction SilentlyContinue)
        if ($hits.Count -eq 1) { return $hits[0].FullName }
        if ($hits.Count -gt 1) { Fail ("More than one save found (several Steam accounts?):`n" + ($hits.FullName -join "`n") + "`nRun again with the full path of yours at the end.") }
    }
    Fail 'Save not found. Run again with the full path of SYSTEM-DATA at the end.'
}

function Load-Save([string]$path) {
    $d = [System.IO.File]::ReadAllBytes($path)
    if ($d.Length -ne $SaveSize) { Fail "Unexpected save size $($d.Length) (expected $SaveSize). Nothing changed." }
    if (-not (Test-Checks $d)) { Fail 'Check values in the save do not match the known format. Nothing changed.' }
    foreach ($g in $Groups) {
        for ($i = 0; $i -lt $g.Len; $i++) {
            if (($g.Ids -notcontains $i) -and $d[$g.Base + $i] -ne 0) { Fail "$($g.Name): unexpected data at id $i. Layout differs, nothing changed." }
        }
    }
    return ,$d
}

function Show-Report([byte[]]$d, [string]$label) {
    Write-Host $label
    $total = 0
    foreach ($g in $Groups) {
        $locked = @($g.Ids | Where-Object { $d[$g.Base + $_] -eq 0 })
        $total += $locked.Count
        $line = '  {0,-13} {1,3} / {2,3} unlocked' -f $g.Name, ($g.Ids.Count - $locked.Count), $g.Ids.Count
        if ($locked.Count) { $line += '   locked ids: ' + ($locked -join ' ') }
        Write-Host $line
    }
    return $total
}

function Backup-Save([string]$save, [string]$tag) {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    Copy-Item -LiteralPath $save -Destination (Join-Path $BackupDir "SYSTEM-DATA_before_${tag}_$stamp")
    if (-not (Test-Path $FirstBackup)) { Copy-Item -LiteralPath $save -Destination $FirstBackup }
    Write-Host "Backup saved: $FirstBackup"
}

function Write-Verified([string]$save, [byte[]]$out) {
    [System.IO.File]::WriteAllBytes($save, $out)
    $back = [System.IO.File]::ReadAllBytes($save)
    $same = ($back.Length -eq $out.Length)
    if ($same) { for ($i = 0; $i -lt $out.Length; $i++) { if ($back[$i] -ne $out[$i]) { $same = $false; break } } }
    if (-not $same -or -not (Test-Checks $back)) {
        Copy-Item -LiteralPath $FirstBackup -Destination $save -Force
        Fail 'Write check FAILED; original save put back.'
    }
    return ,$back
}

# ---- main ----
$save = Find-Save
Write-Host "Save: $save"

switch ($Command.ToLower()) {
    'check' {
        $d = Load-Save $save
        Write-Host ('Beli: {0:N0}' -f [BitConverter]::ToUInt32($d, $BeliOffset))
        [void](Show-Report $d 'Current save:')
        Write-Host 'Save format OK (check values match).' -ForegroundColor Green
    }
    'apply' {
        if (Get-Process -Name OPBB -ErrorAction SilentlyContinue) { Fail 'One Piece Burning Blood is running. Close the game first. Nothing changed.' }
        $d = Load-Save $save
        if ((Show-Report $d 'Before:') -eq 0) { Write-Host 'Everything is already unlocked. Nothing changed.'; break }
        Backup-Save $save 'unlockall'
        foreach ($g in $Groups) { foreach ($i in $g.Ids) { if ($d[$g.Base + $i] -eq 0) { $d[$g.Base + $i] = $Unlocked } } }
        Set-Checks $d
        $back = Write-Verified $save $d
        [void](Show-Report $back 'After:')
        Write-Host 'Done. Save written and verified.' -ForegroundColor Green
    }
    'beli' {
        if (Get-Process -Name OPBB -ErrorAction SilentlyContinue) { Fail 'One Piece Burning Blood is running. Close the game first. Nothing changed.' }
        $d = Load-Save $save
        $cur = [BitConverter]::ToUInt32($d, $BeliOffset)
        Write-Host ('Current Beli: {0:N0}' -f $cur)
        if ($cur -eq $BeliMax) { Write-Host 'Beli is already 999,999,999. Nothing changed.'; break }
        Backup-Save $save 'beli'
        [Array]::Copy([BitConverter]::GetBytes([uint32]$BeliMax), 0, $d, $BeliOffset, 4)
        Set-Checks $d
        [void](Write-Verified $save $d)
        Write-Host ('Done. Beli: {0:N0} -> {1:N0}. Save written and verified.' -f $cur, $BeliMax) -ForegroundColor Green
    }
    'restore' {
        if (Get-Process -Name OPBB -ErrorAction SilentlyContinue) { Fail 'One Piece Burning Blood is running. Close the game first. Nothing changed.' }
        if (-not (Test-Path $FirstBackup)) { Fail "No backup found at $FirstBackup" }
        Copy-Item -LiteralPath $FirstBackup -Destination $save -Force
        $d = Load-Save $save
        [void](Show-Report $d 'Restored save:')
        Write-Host 'Done. Save from before the patch is back.' -ForegroundColor Green
    }
    default { Fail 'Use one of: check, apply, beli, restore' }
}
