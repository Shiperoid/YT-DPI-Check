#requires -Version 5.1
<#
.SYNOPSIS
  Smoke: AST parse YT-DPI.ps1 + patterns (List, Task.Delay, Runspace) used by scan / NetInfo paths.
  Outputs [PASS]/[FAIL]/[SKIP] lines; on parse errors prints file, line, column, snippet.
.NOTES
  Part of release gate compatibility matrix — not application E2E.
#>
param(
    [string]$RepoRoot = $null,
    [switch]$SkipWorkerArity,
    [switch]$SkipRunspaceSmoke,
    [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$ytDpi = Join-Path $RepoRoot 'YT-DPI.ps1'
if (-not (Test-Path -LiteralPath $ytDpi)) {
    throw "YT-DPI.ps1 not found (tried $ytDpi)"
}

function Write-SmokeStep {
    param(
        [Parameter(Mandatory)][ValidateSet('PASS', 'FAIL', 'SKIP')][string]$Status,
        [Parameter(Mandatory)][string]$Phase,
        [string]$Detail = ''
    )
    $line = '[{0}] {1}' -f $Status, $Phase
    if (-not [string]::IsNullOrWhiteSpace($Detail)) { $line += (' — {0}' -f $Detail) }
    $color = switch ($Status) {
        'PASS' { if ($Quiet) { 'Gray' } else { 'Green' }; break }
        'FAIL' { 'Red'; break }
        default { 'DarkGray' }
    }
    Write-Host $line -ForegroundColor $color
}

function Format-SmokeParseErrors {
    param([System.Management.Automation.Language.ParseError[]]$Errors, [string]$Path)
    $sb = New-Object System.Text.StringBuilder
    foreach ($e in $Errors) {
        $ln = $e.Extent.StartLineNumber
        $col = $e.Extent.StartColumnNumber
        [void]$sb.AppendLine(('{0}: line {1} col {2}: {3}' -f $Path, $ln, $col, $e.Message))
        $snippet = [string]$e.Extent.Text
        if (-not [string]::IsNullOrWhiteSpace($snippet)) {
            $oneLine = ($snippet -replace '[\r\n]+', ' ').Trim()
            if ($oneLine.Length -gt 200) { $oneLine = $oneLine.Substring(0, 197) + '...' }
            [void]$sb.AppendLine(('      snippet: {0}' -f $oneLine))
        }
    }
    return $sb.ToString().TrimEnd()
}

function Split-YtDpiParamListTopLevel {
    param([string]$Inner)
    $parts = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder
    $dParen = 0
    $dBracket = 0
    $dBrace = 0
    foreach ($ch in $Inner.ToCharArray()) {
        switch ($ch) {
            '(' { $dParen++; [void]$sb.Append($ch); continue }
            ')' { $dParen--; [void]$sb.Append($ch); continue }
            '[' { $dBracket++; [void]$sb.Append($ch); continue }
            ']' { $dBracket--; [void]$sb.Append($ch); continue }
            '{' { $dBrace++; [void]$sb.Append($ch); continue }
            '}' { $dBrace--; [void]$sb.Append($ch); continue }
            ',' {
                if ($dParen -eq 0 -and $dBracket -eq 0 -and $dBrace -eq 0) {
                    $t = $sb.ToString().Trim()
                    if ($t.Length -gt 0) { [void]$parts.Add($t) }
                    [void]$sb.Clear()
                } else {
                    [void]$sb.Append($ch)
                }
                continue
            }
            default { [void]$sb.Append($ch) }
        }
    }
    $tail = $sb.ToString().Trim()
    if ($tail.Length -gt 0) { [void]$parts.Add($tail) }
    return $parts.ToArray()
}

Write-SmokeStep -Status PASS -Phase 'smoke host' -Detail ("PS $($PSVersionTable.PSVersion) $($PSVersionTable.PSEdition)")
Write-SmokeStep -Status PASS -Phase 'target script' -Detail $ytDpi

$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($ytDpi, [ref]$null, [ref]$errs)
if ($errs -and $errs.Count -gt 0) {
    Write-SmokeStep -Status FAIL -Phase 'AST parse' -Detail ('{0} diagnostic(s)' -f $errs.Count)
    Write-Host (Format-SmokeParseErrors -Errors @($errs) -Path $ytDpi) -ForegroundColor Red
    exit 1
}
Write-SmokeStep -Status PASS -Phase 'AST parse'

if (-not $SkipWorkerArity) {
    try {
        $raw = [System.IO.File]::ReadAllText($ytDpi, [System.Text.UTF8Encoding]::new($false))

        $mWorker = [regex]::Match($raw, '(?ms)\$Worker\s*=\s*\{')
        if (-not $mWorker.Success) {
            throw 'Worker arity check: could not find $Worker = { block.'
        }
        $afterBrace = $mWorker.Index + $mWorker.Length
        $tail = $raw.Substring($afterBrace)
        $mParam = [regex]::Match($tail, '^\s*param\s*\(')
        if (-not $mParam.Success) {
            throw 'Worker arity check: could not find param(...) immediately inside $Worker scriptblock.'
        }
        $contentStart = $afterBrace + $mParam.Index + $mParam.Length
        $depth = 1
        $prmInner = $null
        for ($p = $contentStart; $p -lt $raw.Length; $p++) {
            $ch = $raw[$p]
            if ($ch -eq '(') {
                $depth++
            } elseif ($ch -eq ')') {
                $depth--
                if ($depth -eq 0) {
                    $prmInner = $raw.Substring($contentStart, $p - $contentStart)
                    break
                }
            }
        }
        if ($null -eq $prmInner) {
            throw 'Worker arity check: unbalanced parentheses in param(...).'
        }
        $prmParts = @(Split-YtDpiParamListTopLevel -Inner $prmInner | Where-Object { $_ })
        $paramCount = $prmParts.Count
        if ($paramCount -lt 1) { throw 'Worker arity check: empty param list.' }

        $fnAnchor = 'function Start-ScanWithAnimation'
        $fnStart = $raw.IndexOf($fnAnchor, [System.StringComparison]::Ordinal)
        if ($fnStart -lt 0) {
            throw "Worker arity check: anchor '$fnAnchor' not found."
        }
        $nextFn = [regex]::Match($raw.Substring($fnStart + $fnAnchor.Length), '(?m)^function\s+\w+')
        $sliceLen = if ($nextFn.Success) { $fnStart + $fnAnchor.Length + $nextFn.Index } else { $raw.Length }
        $scanFnBody = $raw.Substring($fnStart, [Math]::Min($sliceLen - $fnStart, $raw.Length - $fnStart))
        $addArgCount = [regex]::Matches($scanFnBody, '(?m)(^\s*AddArgument\s*\(|\.AddArgument\s*\()').Count

        if ($addArgCount -ne $paramCount) {
            throw "Worker arity mismatch: param count=$paramCount vs AddArgument count=$addArgCount (expected equal)."
        }
        Write-SmokeStep -Status PASS -Phase 'worker arity' -Detail ("$paramCount params")
    } catch {
        Write-SmokeStep -Status FAIL -Phase 'worker arity' -Detail "$_"
        throw
    }
} else {
    Write-SmokeStep -Status SKIP -Phase 'worker arity' -Detail '-SkipWorkerArity'
}

$jobs = [System.Collections.Generic.List[object]]::new()
[void]$jobs.Add([PSCustomObject]@{ N = 1 })
[void]$jobs.Add([PSCustomObject]@{ N = 2 })
$sum = 0
foreach ($j in $jobs) { $sum += $j.N }
if ($sum -ne 3) {
    Write-SmokeStep -Status FAIL -Phase 'List pattern' -Detail "sum=$sum"
    throw "List foreach failed: sum=$sum"
}
if ($jobs[1].N -ne 2) {
    Write-SmokeStep -Status FAIL -Phase 'List indexer'
    throw 'List indexer failed'
}
Write-SmokeStep -Status PASS -Phase 'List pattern'

$delay = [System.Threading.Tasks.Task]::Delay(20)
$delay.Wait()
if ($delay.IsFaulted -or $delay.IsCanceled) {
    Write-SmokeStep -Status FAIL -Phase 'Task.Delay' -Detail ([string]$delay.Status)
    throw ("Task.Delay smoke failed (Status={0})" -f $delay.Status)
}
Write-SmokeStep -Status PASS -Phase 'Task.Delay'

if (-not $SkipRunspaceSmoke) {
    try {
        $rs = [runspacefactory]::CreateRunspace()
        $rs.Open()
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        $null = $ps.AddScript({
                param($x)
                return @{ Echo = $x }
            }).AddArgument(42)
        $h = $ps.BeginInvoke()
        $deadline = [datetime]::UtcNow.AddSeconds(30)
        while (-not $h.IsCompleted) {
            if ([datetime]::UtcNow -gt $deadline) { throw 'BeginInvoke timeout' }
            Start-Sleep -Milliseconds 30
        }
        $rawInvoke = $ps.EndInvoke($h)
        try { $ps.Dispose() } catch {}
        try { $rs.Close(); $rs.Dispose() } catch {}
        $arr = @($rawInvoke)
        $one = if ($arr.Count) { $arr[-1] } else { $null }
        if ($one.Echo -ne 42) {
            throw "Runspace result wrong: $($one | ConvertTo-Json -Compress)"
        }
        Write-SmokeStep -Status PASS -Phase 'Runspace BeginInvoke'
    } catch {
        Write-SmokeStep -Status FAIL -Phase 'Runspace BeginInvoke' -Detail "$_"
        throw
    }
} else {
    Write-SmokeStep -Status SKIP -Phase 'Runspace BeginInvoke' -Detail '-SkipRunspaceSmoke'
}

Write-SmokeStep -Status PASS -Phase 'smoke-yt-dpi-engines complete'
exit 0
