#Requires -Version 5.1
<#
.SYNOPSIS
  Build and install the Databend Power BI Connector (.mez).
#>
[CmdletBinding()]
param(
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$src = Join-Path $root "powerbi\DatabendConnector"
$outDir = Join-Path $root "powerbi\dist"
$mez = Join-Path $outDir "DatabendConnector.mez"

function New-ConnectorIcon {
    param([string]$Path, [int]$Size)
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap $Size, $Size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::FromArgb(255, 18, 99, 214))
    $fontSize = [Math]::Max(6, [int]($Size * 0.45))
    $font = New-Object System.Drawing.Font "Segoe UI", $fontSize, ([System.Drawing.FontStyle]::Bold)
    $brush = [System.Drawing.Brushes]::White
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $rect = New-Object System.Drawing.RectangleF 0, 0, $Size, $Size
    $g.DrawString("D", $font, $brush, $rect, $sf)
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    $font.Dispose()
}

Write-Host "Generating icons..."
foreach ($size in 16, 20, 24, 32, 40, 48, 64) {
    New-ConnectorIcon -Path (Join-Path $src "Databend$size.png") -Size $size
}

Write-Host "Packaging $mez ..."
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
if (Test-Path $mez) { Remove-Item -Force $mez }

$stage = Join-Path $env:TEMP ("DatabendConnector_mez_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $stage | Out-Null
try {
    Copy-Item -Force (Join-Path $src "DatabendConnector.pq") $stage
    Get-ChildItem (Join-Path $src "Databend*.png") | Copy-Item -Destination $stage -Force
    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath ($mez + ".zip") -Force
    Move-Item -Force ($mez + ".zip") $mez
} finally {
    Remove-Item -Recurse -Force $stage
}

Write-Host "Built: $mez"

if ($SkipInstall) { return }

$target = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Microsoft Power BI Desktop\Custom Connectors"
New-Item -ItemType Directory -Force -Path $target | Out-Null
Copy-Item -Force $mez (Join-Path $target "DatabendConnector.mez")
Write-Host "Installed to: $target\DatabendConnector.mez"
