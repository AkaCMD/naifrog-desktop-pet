param([switch]$WithUsage, [switch]$NoStart,
    [string]$PetRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\pets'))
$ErrorActionPreference = 'Stop'
$destination = [IO.Path]::GetFullPath((Join-Path $PetRoot 'naifrog'))
foreach ($file in @('pet.json', 'spritesheet.webp')) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot ('pet\' + $file)))) { throw 'Missing pet source.' }
}
if (Test-Path -LiteralPath (Join-Path $destination 'pet.json')) {
    $existing = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $destination 'pet.json') | ConvertFrom-Json
    if ($existing.id -ne 'naifrog') { throw 'Destination belongs to a different pet.' }
}
$null = New-Item -ItemType Directory -Path $destination -Force
foreach ($file in @('pet.json', 'spritesheet.webp', 'LICENSE', 'NOTICE.md', 'licenses\Zhengyici-MIT.txt')) {
    $source = if ($file -in @('pet.json', 'spritesheet.webp')) { Join-Path $PSScriptRoot ('pet\' + $file) } else { Join-Path $PSScriptRoot $file }
    Copy-Item -LiteralPath $source -Destination $destination -Force
}
if ($WithUsage) {
    & (Join-Path $PSScriptRoot 'usage\Install.ps1') -Destination (Join-Path $destination 'usage') -NoStart:$NoStart
}
Write-Output 'Installed 奶蛙. Restart Codex, then choose Settings > Appearance > Pets > 奶蛙.'
