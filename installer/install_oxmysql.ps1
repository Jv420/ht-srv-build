$ErrorActionPreference = 'Stop'

$ReleaseVersion = 'v2.14.1'
$DownloadUrl = "https://github.com/overextended/oxmysql/releases/download/$ReleaseVersion/oxmysql.zip"
$PackageRoot = Split-Path -Parent $PSScriptRoot
$ResourcesRoot = Join-Path $PackageRoot 'resources'
$LibrariesRoot = Join-Path $ResourcesRoot '[libs]'
$Destination = Join-Path $LibrariesRoot 'oxmysql'
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("hextactics-oxmysql-" + [guid]::NewGuid().ToString('N'))
$Archive = Join-Path $TempRoot 'oxmysql.zip'
$Extracted = Join-Path $TempRoot 'extracted'

Write-Host "HexTactics: oxmysql $ReleaseVersion installeren..." -ForegroundColor Cyan
New-Item -ItemType Directory -Path $TempRoot, $Extracted, $LibrariesRoot -Force | Out-Null

try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $Archive -UseBasicParsing
    Expand-Archive -LiteralPath $Archive -DestinationPath $Extracted -Force

    $Manifest = Get-ChildItem -Path $Extracted -Filter 'fxmanifest.lua' -File -Recurse |
        Where-Object { $_.FullName -match '[\\/]oxmysql[\\/]fxmanifest\.lua$' -or $_.Directory.Name -eq 'oxmysql' } |
        Select-Object -First 1

    if (-not $Manifest) {
        $Manifest = Get-ChildItem -Path $Extracted -Filter 'fxmanifest.lua' -File -Recurse | Select-Object -First 1
    }

    if (-not $Manifest) {
        throw 'De gedownloade ZIP bevat geen fxmanifest.lua.'
    }

    $Source = $Manifest.Directory.FullName
    if (Test-Path $Destination) {
        $Backup = "$Destination.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Move-Item -LiteralPath $Destination -Destination $Backup
        Write-Host "Bestaande oxmysql is bewaard als: $Backup" -ForegroundColor Yellow
    }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force

    if (-not (Test-Path (Join-Path $Destination 'fxmanifest.lua'))) {
        throw 'Installatiecontrole mislukt: fxmanifest.lua ontbreekt in de doelmap.'
    }

    Write-Host "Klaar: $Destination" -ForegroundColor Green
    Write-Host 'Zet ensure oxmysql boven es_extended en alle databasescripts in server.cfg.' -ForegroundColor Green
}
finally {
    if (Test-Path $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
