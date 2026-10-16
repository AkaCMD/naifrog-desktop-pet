param([string]$Directory)
# Synthetic example only. Replace with your query; set a request timeout (e.g. 15s).
# Return exactly one object. Never write credentials or account details to logs.
$now = [DateTimeOffset]::UtcNow
$period = [DateTimeOffset]::new($now.Date.AddDays(-[int]$now.DayOfWeek), [TimeSpan]::Zero)
[pscustomobject]@{
    periodStart = $period.ToUnixTimeSeconds()
    periodEnd = $period.AddDays(7).ToUnixTimeSeconds()
    used = 25.0; available = 75.0; reserve = 10.0; reserveActive = 0.0
}
