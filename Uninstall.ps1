param([string]$PetRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\pets'))
$ErrorActionPreference = 'Stop'
$resolvedRoot = [IO.Path]::GetFullPath($PetRoot).TrimEnd('\')
$target = [IO.Path]::GetFullPath((Join-Path $resolvedRoot 'naifrog'))
if (-not $target.StartsWith($resolvedRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($target) -ne 'naifrog') { throw 'Unexpected uninstall path.' }
if (-not (Test-Path -LiteralPath (Join-Path $target 'pet.json'))) { Write-Output 'Not installed.'; return }
$pet = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $target 'pet.json') | ConvertFrom-Json
if ($pet.id -ne 'naifrog') { throw 'Refusing to remove another pet.' }
if ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing to delete a linked directory.' }
$usage = Join-Path $target 'usage'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'usage\Install.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Installer source is invalid.' }
$definition = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Stop-NailongUsageProcess' }, $true)
. ([scriptblock]::Create($definition.Extent.Text))
foreach ($name in @('Usage.Supervisor.ps1', 'NailongUsage.ps1')) { Stop-NailongUsageProcess -ScriptPath (Join-Path $usage $name) }
$task = Get-ScheduledTask -TaskName 'Naifrog Usage Supervisor' -ErrorAction SilentlyContinue
if ($null -ne $task) {
    $expected = Join-Path $usage 'Usage.Supervisor.ps1'
    if (@($task.Actions | Where-Object { $_.Arguments -like ('*"' + $expected + '"*') }).Count -gt 0) { Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false }
}
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Naifrog Usage Reminder.lnk'
if (Test-Path -LiteralPath $shortcutPath) {
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
    if ($shortcut.Arguments -like ('*"' + (Join-Path $usage 'Usage.Supervisor.ps1') + '"*')) { Remove-Item -LiteralPath $shortcutPath -Force }
}
Remove-Item -LiteralPath $target -Recurse -Force
Write-Output 'Removed 奶蛙 and its usage helper. Restore manually configured sound notify separately.'
