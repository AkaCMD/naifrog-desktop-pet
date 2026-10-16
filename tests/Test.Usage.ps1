$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
. (Join-Path $PSScriptRoot '..\usage\Usage.Core.ps1')
$script:count = 0
function Assert([bool]$Value, [string]$Message) {
    if (-not $Value) { throw $Message }; $script:count++
}
function New-TestData([decimal]$Available = 75, [decimal]$Used = 25, [long]$Start = 1767225600) {
    [pscustomobject]@{ periodStart = $Start; periodEnd = $Start + 604800; used = $Used; available = $Available; reserve = 10; reserveActive = 2 }
}
$s = ConvertTo-NailongSnapshot (New-TestData)
Assert ($s.Used -eq 25 -and $s.Available -eq 75) 'Use final units, no hidden conversion.'
Assert ($s.ReserveInactive -eq 8 -and $s.RemainingPercent -eq 75) 'Do not add inactive reserves to remaining percentage.'
Assert ($null -eq (Get-NailongAlertLevel $s)) 'Healthy quota must not alert.'
$low = ConvertTo-NailongSnapshot (New-TestData -Available 20 -Used 80)
$d = Get-NailongAlertDecision $low $null
Assert ($d.Show -and $d.Level -eq 20) '20% boundary must alert.'
$saved = $d.State | ConvertTo-Json | ConvertFrom-Json
Assert (-not (Get-NailongAlertDecision $low $saved).Show) 'Deduplication survives serialization.'
$lower = ConvertTo-NailongSnapshot (New-TestData -Available 10 -Used 90)
$d10 = Get-NailongAlertDecision $lower $saved
Assert ($d10.Show -and $d10.Level -eq 10) '10% boundary must alert.'
$empty = ConvertTo-NailongSnapshot (New-TestData -Available 0 -Used 100)
$d0 = Get-NailongAlertDecision $empty $d10.State
Assert ($d0.Show -and $d0.Level -eq 0) 'Exhaustion must alert.'
Assert (-not (Get-NailongAlertDecision $empty $d0.State).Show) 'Exhaustion must not repeat.'
Assert (-not (Get-NailongAlertDecision $low (Get-NailongAlertDecision $empty $null).State).Show) 'Skipped milder bands must not reappear after refill.'
Assert ((Get-NailongAlertDecision (ConvertTo-NailongSnapshot (New-TestData -Available 20 -Used 80 -Start 1767830400)) $saved).Show) 'New period must reset reminders.'
Assert ($null -eq (Get-NailongAlertLevel (ConvertTo-NailongSnapshot (New-TestData -Available 20.001 -Used 79.999)))) 'Display rounding must not trigger alerts.'
Assert ((ConvertTo-NailongSnapshot (New-TestData -Available -1)).Available -eq 0) 'Debt must display zero available.'
foreach ($field in @('periodStart','periodEnd','used','available','reserve','reserveActive')) {
    $bad = New-TestData; $bad.PSObject.Properties.Remove($field); $rejected = $false
    try { $null = ConvertTo-NailongSnapshot $bad } catch { $rejected = $true }
    Assert $rejected ('Missing field rejected: ' + $field)
}
foreach ($patch in @(@{used=-1}, @{reserve=-1}, @{reserveActive=11}, @{periodEnd=1})) {
    $bad = New-TestData; foreach ($key in $patch.Keys) { $bad.$key = $patch[$key] }; $rejected = $false
    try { $null = ConvertTo-NailongSnapshot $bad } catch { $rejected = $true }
    Assert $rejected 'Invalid provider values must fail.'
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('NaifrogProviderTest-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temp
try {
    @{providerScript=''} | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $temp 'settings.json')
    $unconfigured = $false
    try { $null = Get-NailongUsage -Directory $temp } catch { $unconfigured = $_.Exception.Message -eq 'NAIFROG_NOT_CONFIGURED' }
    Assert $unconfigured 'Empty provider must be explicitly unconfigured.'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\usage\Provider.Example.ps1') -Destination $temp
    @{providerScript='Provider.Example.ps1'} | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $temp 'settings.json')
    Assert ((Get-NailongUsage -Directory $temp).Available -eq 75) 'Provider integration must load the example object.'
    Set-Content -LiteralPath (Join-Path $temp 'Provider.Example.ps1') -Value "'extra output'; [pscustomobject]@{used=0}"
    $rejected = $false
    try { $null = Get-NailongUsage -Directory $temp } catch { $rejected = $true }
    Assert $rejected 'Providers with extra output must fail.'
} finally {
    $resolved = [IO.Path]::GetFullPath($temp)
    $prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'NaifrogProviderTest-*') { throw 'Unexpected cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Output ('PASS: {0} usage assertions.' -f $script:count)
