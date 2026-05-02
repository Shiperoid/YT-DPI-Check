# Reads YT-DPI-LOGO-BEGIN ... YT-DPI-LOGO-END from YT-DPI.ps1 and draws the same logo centered.
param(
    [string] $SourceScript,
    [switch] $NoReadKey
)

function Get-YtDpiMainScriptPath {
    param([string] $Explicit)
    if ($Explicit -and (Test-Path -LiteralPath $Explicit)) {
        return (Resolve-Path -LiteralPath $Explicit).ProviderPath
    }
    $startDirs = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        [void]$startDirs.Add((Resolve-Path -LiteralPath $PSScriptRoot).ProviderPath)
    }
    try {
        $loc = (Get-Location).ProviderPath
        if ($loc -and $startDirs -notcontains $loc) { [void]$startDirs.Add($loc) }
    } catch { }

    foreach ($start in $startDirs) {
        $dir = $start
        while ($dir) {
            $candidate = Join-Path $dir 'YT-DPI.ps1'
            if (Test-Path -LiteralPath $candidate) {
                return (Resolve-Path -LiteralPath $candidate).ProviderPath
            }
            # -LiteralPath с -Parent ломается в части версий pwsh; каталоги здесь без масок — достаточно -Path.
            $parent = Split-Path -Path $dir -Parent
            if (-not $parent -or ($parent -eq $dir)) { break }
            $dir = $parent
        }
    }
    return $null
}

$explicitPath = if ($PSBoundParameters.ContainsKey('SourceScript')) { $SourceScript } else { $null }
$SourceScript = Get-YtDpiMainScriptPath -Explicit $explicitPath
if (-not $SourceScript) {
    $hint = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        'PSScriptRoot пуст (скрипт мог быть запущен не через -File). Запускайте: pwsh -File tools\logo.ps1 или укажите -SourceScript путь\YT-DPI.ps1'
    } else {
        "Обошли каталоги от $PSScriptRoot и текущей папки вверх — YT-DPI.ps1 не найден. Укажите -SourceScript."
    }
    Write-Error $hint
    exit 1
}

function Out-Str([int] $x, [int] $y, [string] $str, [string] $color = 'White', [string] $bg = 'Black') {
    try {
        [Console]::CursorVisible = $false
        [Console]::SetCursorPosition($x, $y)
        [Console]::ForegroundColor = $color
        [Console]::BackgroundColor = $bg
        [Console]::Write($str)
        [Console]::BackgroundColor = 'Black'
    } catch { }
}

if (-not (Test-Path -LiteralPath $SourceScript)) {
    Write-Error "Source script not found: $SourceScript"
    exit 1
}

$begin = (Select-String -LiteralPath $SourceScript -SimpleMatch 'YT-DPI-LOGO-BEGIN' | Select-Object -First 1).LineNumber
$end = (Select-String -LiteralPath $SourceScript -SimpleMatch 'YT-DPI-LOGO-END' | Select-Object -First 1).LineNumber
if (-not $begin -or -not $end -or $end -le $begin) {
    Write-Error "Markers YT-DPI-LOGO-BEGIN / YT-DPI-LOGO-END missing or invalid order in: $SourceScript"
    exit 1
}

# LineNumber is 1-based; first line after BEGIN is at index $begin in Get-Content (0-based) array
$lines = Get-Content -LiteralPath $SourceScript -Encoding UTF8
$slice = $lines[$begin..($end - 2)]
$rx = [regex] '^\s*Out-Str\s+(\d+)\s+(\d+)\s+''(.+?)''\s+''(\w+)''\s*(?:#.*)?$'
$calls = foreach ($line in $slice) {
    $m = $rx.Match($line)
    if (-not $m.Success) { continue }
    [pscustomobject]@{
        X     = [int] $m.Groups[1].Value
        Y     = [int] $m.Groups[2].Value
        Text  = $m.Groups[3].Value.Replace("''", "'")
        Color = $m.Groups[4].Value
    }
}
if (@($calls).Count -lt 2) {
    Write-Error 'No Out-Str lines parsed between logo markers (format must match YT-DPI.ps1).'
    exit 1
}

$byY = $calls | Group-Object Y | Sort-Object { [int] $_.Name }
$rows = foreach ($g in $byY) {
    $items = @($g.Group | Sort-Object X)
    if ($items.Count -lt 2) {
        Write-Error ('Logo row Y={0}: need two Out-Str calls (left and right).' -f $g.Name)
        exit 1
    }
    [pscustomobject]@{ Left = $items[0]; Right = $items[-1] }
}

$gap = $rows[0].Right.X - $rows[0].Left.X
foreach ($r in $rows) {
    $g = $r.Right.X - $r.Left.X
    if ($g -ne $gap) {
        Write-Error ('Logo: X gap mismatch (expected {0}, got {1}, row Y={2}).' -f $gap, $g, $r.Left.Y)
        exit 1
    }
}

$blockW = 0
foreach ($r in $rows) {
    $w = [Math]::Max($r.Left.Text.Length, $gap + $r.Right.Text.Length)
    if ($w -gt $blockW) { $blockW = $w }
}

try {
    $cw = [Console]::WindowWidth
    $ch = [Console]::WindowHeight
} catch {
    $cw = 120
    $ch = 40
}
$ox = [Math]::Max(0, [int][Math]::Floor(($cw - $blockW) / 2))
$oy = [Math]::Max(0, [int][Math]::Floor(($ch - $rows.Count) / 2))
try { Clear-Host } catch { }
$ri = 0
foreach ($r in $rows) {
    Out-Str $ox ($oy + $ri) $r.Left.Text $r.Left.Color
    Out-Str ($ox + $gap) ($oy + $ri) $r.Right.Text $r.Right.Color
    $ri++
}

if (-not $NoReadKey) {
    try { [void][Console]::ReadKey($true) } catch { }
}
