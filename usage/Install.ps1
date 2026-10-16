param(
    [string]$Destination = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\pets\naifrog\usage'),
    [switch]$NoStart
)
$ErrorActionPreference = 'Stop'
function Stop-NailongUsageProcess {
    param([Parameter(Mandatory)][string]$ScriptPath)
    $targetPath = [IO.Path]::GetFullPath($ScriptPath)
    foreach ($candidate in @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'")) {
        if ($candidate.ProcessId -eq $PID -or -not $candidate.CommandLine) { continue }
        # Match the -File argument exactly; never stop previews or a different installation.
        $match = [regex]::Match($candidate.CommandLine, '(?i)(?:^|\s)-File\s+(?:"([^"]+)"|(\S+))')
        if (-not $match.Success -or $candidate.CommandLine -match '(?i)(?:^|\s)-Preview(?:\s|$)') { continue }
        $candidatePath = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value }
        if (-not [IO.Path]::IsPathRooted($candidatePath) -or
            [IO.Path]::GetFullPath($candidatePath) -ne $targetPath) { continue }
        $process = Get-Process -Id $candidate.ProcessId -ErrorAction SilentlyContinue
        if ($null -ne $process) {
            Stop-Process -InputObject $process -Force -ErrorAction Stop
            if (-not $process.WaitForExit(10000)) { throw 'Usage helper did not stop before update.' }
        }
    }
}

$Destination = [IO.Path]::GetFullPath($Destination)
# Validate sources before interrupting the running helper.
foreach ($file in @('Usage.Core.ps1', 'NailongUsage.ps1', 'Usage.Supervisor.ps1', 'Register.Autostart.ps1', 'Provider.Example.ps1', 'README.md', 'settings.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)) { throw 'An installation source is missing.' }
}
$existingTask = Get-ScheduledTask -TaskName 'Naifrog Usage Supervisor' -ErrorAction SilentlyContinue
if ($null -ne $existingTask) {
    $expected = Join-Path $Destination 'Usage.Supervisor.ps1'
    if (@($existingTask.Actions | Where-Object { $_.Arguments -like ('*"' + $expected + '"*') }).Count -gt 0) {
        $null = Disable-ScheduledTask -TaskName $existingTask.TaskName
        Stop-ScheduledTask -TaskName $existingTask.TaskName
    }
}
Stop-NailongUsageProcess -ScriptPath (Join-Path $Destination 'Usage.Supervisor.ps1')
Stop-NailongUsageProcess -ScriptPath (Join-Path $Destination 'NailongUsage.ps1')
$null = New-Item -ItemType Directory -Path $Destination -Force
foreach ($file in @('Usage.Core.ps1', 'NailongUsage.ps1', 'Usage.Supervisor.ps1', 'Register.Autostart.ps1', 'Provider.Example.ps1', 'README.md')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $Destination $file) -Force
}
if (-not (Test-Path -LiteralPath (Join-Path $Destination 'settings.json'))) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'settings.json') -Destination $Destination
}
$shell = New-Object -ComObject WScript.Shell
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Naifrog Usage Reminder.lnk'
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + (Join-Path $Destination 'Usage.Supervisor.ps1') + '"'
$shortcut.WorkingDirectory = $Destination
$shortcut.WindowStyle = 7
$shortcut.Description = '奶蛙用量按钮、气泡和额度提醒'
$shortcut.Save()
if (-not $NoStart) {
    & (Join-Path $Destination 'Register.Autostart.ps1') -Directory $Destination
}
Write-Output ('Installed usage reminder: ' + $Destination)
