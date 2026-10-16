param([string]$Directory = $PSScriptRoot, [int]$TestExitSeconds = 0)
$ErrorActionPreference = 'Stop'
$created = $false
$mutex = [Threading.Mutex]::new($true, 'Local\NaifrogUsageSupervisor', [ref]$created)
if (-not $created) { $mutex.Dispose(); exit 0 }
$helperPath = [IO.Path]::GetFullPath((Join-Path $Directory 'NailongUsage.ps1'))
$executable = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$clock = [Diagnostics.Stopwatch]::StartNew()
$child = $null
try {
    while ($TestExitSeconds -le 0 -or $clock.Elapsed.TotalSeconds -lt $TestExitSeconds) {
        try {
            if ($null -ne $child -and $child.HasExited) { $child.Dispose(); $child = $null }
            if ($null -eq $child -and @(Get-Process -Name ChatGPT,codex -ErrorAction SilentlyContinue).Count -gt 0) {
                # Adopt an existing installation, but never adopt a preview or another path.
                foreach ($candidate in @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'")) {
                    if (-not $candidate.CommandLine -or $candidate.CommandLine -match '(?i)\s-Preview(?:\s|$)') { continue }
                    $match = [regex]::Match($candidate.CommandLine, '(?i)(?:^|\s)-File\s+(?:"([^"]+)"|(\S+))')
                    if (-not $match.Success) { continue }
                    $path = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value }
                    if ([IO.Path]::IsPathRooted($path) -and [IO.Path]::GetFullPath($path) -eq $helperPath) {
                        $child = Get-Process -Id $candidate.ProcessId -ErrorAction SilentlyContinue
                        break
                    }
                }
                if ($null -eq $child) {
                    $child = Start-Process -FilePath $executable -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + $helperPath + '"') -WindowStyle Hidden -PassThru
                }
            }
        } catch {
            # No exception details: local configuration and URLs must not leak into logs.
            if ($null -ne $child) { $child.Dispose(); $child = $null }
        }
        Start-Sleep -Seconds 2
    }
} finally {
    if ($null -ne $child) { $child.Dispose() }
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
