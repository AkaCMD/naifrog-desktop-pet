Set-StrictMode -Version 3.0

function ConvertTo-NailongSnapshot {
    param([Parameter(Mandatory)]$Data)
    foreach ($name in @('periodStart', 'periodEnd', 'used', 'available', 'reserve', 'reserveActive')) {
        if (-not $Data.PSObject.Properties[$name] -or $null -eq $Data.$name) { throw 'Required usage field is missing.' }
    }
    $start = [long]$Data.periodStart; $end = [long]$Data.periodEnd
    if ($start -lt 0 -or $end -le $start) { throw 'Invalid quota period.' }
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $used = [decimal]::Parse([string]$Data.used, $culture)
    $available = [Math]::Max([decimal]0, [decimal]::Parse([string]$Data.available, $culture))
    $reserve = [decimal]::Parse([string]$Data.reserve, $culture)
    $active = [decimal]::Parse([string]$Data.reserveActive, $culture)
    if ($used -lt 0 -or $reserve -lt 0 -or $active -lt 0 -or $active -gt $reserve) { throw 'Invalid quota amounts.' }
    $total = $used + $available
    [pscustomobject]@{
        WeekStart = $start; WeekEnd = $end
        Used = $used; Available = $available
        Reserve = $reserve; ReserveActive = $active; ReserveInactive = $reserve - $active
        RemainingPercent = if ($total -gt 0) { [decimal]100 * $available / $total } else { [decimal]0 }
        UpdatedAt = [DateTimeOffset]::UtcNow
    }
}

function Get-NailongUsage {
    param([Parameter(Mandatory)][string]$Directory)
    $settings = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $Directory 'settings.json') | ConvertFrom-Json
    if (-not $settings.providerScript) { throw 'NAIFROG_NOT_CONFIGURED' }
    # Providers are trusted local scripts, run with the current user's permissions.
    $path = Join-Path $Directory ([string]$settings.providerScript)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Usage provider not found.' }
    $items = @(& $path -Directory $Directory)
    if ($items.Count -ne 1) { throw 'Provider must return exactly one data object.' }
    ConvertTo-NailongSnapshot $items[0]
}

function Get-NailongAlertLevel {
    param([Parameter(Mandatory)]$Snapshot)
    if ($Snapshot.Available -le 0) { return 0 }
    if ($Snapshot.RemainingPercent -le 10) { return 10 }
    if ($Snapshot.RemainingPercent -le 20) { return 20 }
    return $null
}

function Get-NailongAlertDecision {
    param([Parameter(Mandatory)]$Snapshot, $PreviousState)
    $notified = @()
    if ($null -ne $PreviousState -and $PreviousState.WeekStart -eq $Snapshot.WeekStart) { $notified = @($PreviousState.Notified) }
    $level = Get-NailongAlertLevel $Snapshot
    $show = $null -ne $level -and $notified -notcontains $level
    if ($show) { $notified = @(@($notified) + @(20, 10, 0 | Where-Object { $_ -ge $level }) | Sort-Object -Unique) }
    [pscustomobject]@{ Show = $show; Level = $level; State = [pscustomobject]@{ WeekStart = $Snapshot.WeekStart; Notified = @($notified) } }
}
