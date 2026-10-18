param(
  [string]$Output = "dist/CraftAlert.zip"
)

$root = Split-Path -Parent $PSScriptRoot
$outputPath = Join-Path $root $Output
$outputDir = Split-Path -Parent $outputPath
$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("CraftAlert-package-" + [System.Guid]::NewGuid().ToString())
$stagingAddon = Join-Path $stagingRoot "CraftAlert"
$packageItems = @(
  "CraftAlert.toc",
  "Bindings.xml",
  "Bootstrap.lua",
  "Core",
  "Model",
  "Professions",
  "Persistence",
  "UI"
)

if (-not (Test-Path $outputDir)) {
  New-Item -ItemType Directory -Path $outputDir | Out-Null
}

if (Test-Path $outputPath) {
  Remove-Item $outputPath -Force
}

if (Test-Path $stagingRoot) {
  Remove-Item $stagingRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $stagingAddon -Force | Out-Null

foreach ($item in $packageItems) {
  $sourcePath = Join-Path $root $item

  if (-not (Test-Path $sourcePath)) {
    throw "Addon package item not found: $sourcePath"
  }

  Copy-Item -Path $sourcePath -Destination (Join-Path $stagingAddon $item) -Recurse -Force
}

Compress-Archive -Path $stagingAddon -DestinationPath $outputPath
Remove-Item $stagingRoot -Recurse -Force
Write-Host "Packaged addon at $outputPath"
