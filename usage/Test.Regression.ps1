$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
. (Join-Path $PSScriptRoot 'Usage.Core.ps1')
$script:assertions = 0
function Assert-Regression([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:assertions++
}
function Import-TestFunction([string]$File, [string]$Name) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($File, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw 'Source parsing failed.' }
    $definition = $ast.Find({ param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }.GetNewClosure(), $true)
    if ($null -eq $definition) { throw ('Missing function: ' + $Name) }
    return [scriptblock]::Create($definition.Extent.Text)
}
. (Import-TestFunction (Join-Path $PSScriptRoot 'NailongUsage.ps1') 'Save-NailongAlertState')
. (Import-TestFunction (Join-Path $PSScriptRoot 'NailongUsage.ps1') 'Show-NailongPendingAlert')
. (Import-TestFunction (Join-Path $PSScriptRoot 'Install.ps1') 'Stop-NailongUsageProcess')
function Update-NailongDisplay { }

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('NailongUsageRegression-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot
$children = @()
$lock = $null
try {
    $Preview = $false
    $statePath = Join-Path $testRoot 'alert-state.json'
    $script:stateDirty = $false
    $script:stateSaveFailed = $false
    $script:nextStateSave = [DateTime]::MinValue
    $script:alertState = $null
    $script:petVisible = $true
    $script:failed = $false
    $script:manualOpen = $false
    $autoHideSeconds = 15
    $controls = @{ AlertText = [pscustomobject]@{ Text = '' } }
    $bubbleWindow = [pscustomobject]@{ ShowCount = 0 }
    $bubbleWindow | Add-Member ScriptMethod Show { $this.ShowCount++ }
    $snapshot = [pscustomobject]@{ WeekStart = 1791734400; Available = 20; RemainingPercent = 20 }
    $script:pendingAlert = Get-NailongAlertDecision $snapshot $null
    # A real exclusive file lock simulates temporary inability to persist the alert.
    $lock = [IO.File]::Open(($statePath + '.tmp'), 'OpenOrCreate', 'ReadWrite', 'None')
    Show-NailongPendingAlert
    Assert-Regression ($bubbleWindow.ShowCount -eq 1) 'The alert must still appear when persistence fails.'
    Assert-Regression ($script:stateDirty -and $script:stateSaveFailed) 'Failed persistence must remain pending.'
    Assert-Regression ($null -eq $script:pendingAlert) 'Shown alerts must not stay queued for repeated display.'
    Assert-Regression (-not (Get-NailongAlertDecision $snapshot $script:alertState).Show) 'Memory must suppress repeated alerts during failure.'
    Assert-Regression ($script:nextStateSave -gt [DateTime]::UtcNow) 'Retry must be throttled rather than run every frame.'
    $lock.Dispose(); $lock = $null
    Save-NailongAlertState
    Assert-Regression (-not (Test-Path -LiteralPath $statePath)) 'Persistence must respect the retry delay.'
    $script:petVisible = $false
    $script:failed = $true
    $script:nextStateSave = [DateTime]::MinValue
    Save-NailongAlertState
    Assert-Regression (-not $script:stateDirty -and -not $script:stateSaveFailed) 'Recovery must clear pending state even while hidden/offline.'
    $reloaded = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    Assert-Regression (-not (Get-NailongAlertDecision $snapshot $reloaded).Show) 'Recovered persistence must suppress the alert after restart.'
    Assert-Regression ($bubbleWindow.ShowCount -eq 1) 'Persistence retries must not reopen the bubble.'
    $script:stateDirty = $true; $Preview = $true
    Save-NailongAlertState
    Assert-Regression $script:stateDirty 'Preview must never persist alert records.'

    # Real child processes prove that only the target -File argument is stopped.
    $targetScript = Join-Path $testRoot 'NailongUsage.ps1'
    $otherDirectory = Join-Path $testRoot 'other'
    $null = New-Item -ItemType Directory -Path $otherDirectory
    $otherScript = Join-Path $otherDirectory 'NailongUsage.ps1'
    $stub = 'param([switch]$Preview, [string]$Directory); Start-Sleep -Seconds 120'
    Set-Content -LiteralPath $targetScript -Value $stub
    Set-Content -LiteralPath $otherScript -Value $stub
    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $target = Start-Process $powershell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $targetScript + '"') -WindowStyle Hidden -PassThru
    $children += $target
    $other = Start-Process $powershell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $otherScript + '" -Directory "' + $targetScript + '"') -WindowStyle Hidden -PassThru
    $children += $other
    $previewChild = Start-Process $powershell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $targetScript + '" -Preview') -WindowStyle Hidden -PassThru
    $children += $previewChild
    Stop-NailongUsageProcess -ScriptPath $targetScript
    Assert-Regression $target.HasExited 'Update must wait for the old target process to exit.'
    Assert-Regression (-not $other.HasExited) 'A different installation must stay running even when its arguments mention the target.'
    Assert-Regression (-not $previewChild.HasExited) 'Preview processes must stay running.'
    Stop-NailongUsageProcess -ScriptPath $targetScript
    Assert-Regression (-not $other.HasExited) 'Stopping an already stopped target must be harmless.'
    Write-Output ('PASS: {0} regression assertions (save failure/recovery, restart, preview, process isolation)' -f $script:assertions)
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
    foreach ($child in $children) {
        if (-not $child.HasExited) { Stop-Process -InputObject $child -Force; $null = $child.WaitForExit(10000) }
        $child.Dispose()
    }
    $resolvedRoot = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolvedRoot) -notlike 'NailongUsageRegression-*') { throw 'Unexpected test cleanup path.' }
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
}
