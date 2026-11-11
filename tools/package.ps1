# Builds the CurseForge upload folder:
#   curseforge\QuestXPTracker-<version>.zip   the file to upload (contains QuestXPTracker\...)
#   curseforge\description.md                 paste into the project description (Markdown editor)
#   curseforge\avatar.png                     400x400 project avatar
#   curseforge\screenshots\                   in-game screenshots (the PNGs in Media other than logo*)
# Usage (from the repo root): .\tools\package.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$out  = Join-Path $root "curseforge"
$name = "QuestXPTracker"

# version from the .toc
$toc = Get-Content (Join-Path $root "$name.toc")
$version = ($toc | Where-Object { $_ -match '^## Version:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1)
if (-not $version) { throw "No '## Version:' line in $name.toc" }

# files that go into the addon folder in the zip
$files = @(
    "$name.toc",
    "$name.lua",
    "LICENSE",
    "README.md",
    "Media\QxpIcon.tga"
)
foreach ($f in $files) {
    if (-not (Test-Path (Join-Path $root $f))) { throw "Missing $f" }
}

New-Item -ItemType Directory -Force $out | Out-Null
Get-ChildItem $out -Filter "$name-*.zip" | Remove-Item -Force

# Build the zip by hand so entry names use forward slashes (Compress-Archive on
# Windows PowerShell writes backslashes, which other unzip tools mis-read).
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = Join-Path $out "$name-$version.zip"
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($f in $files) {
        $entry = "$name/" + ($f -replace '\\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $root $f), $entry, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {
    $zip.Dispose()
}

Copy-Item (Join-Path $root "CURSEFORGE.md") (Join-Path $out "description.md") -Force
& (Join-Path $PSScriptRoot "make-logo.ps1") -Size 400 -Png (Join-Path $out "avatar.png") | Out-Null

# screenshots: every PNG in Media except the logo files, for the project's Images tab
$shots = Get-ChildItem (Join-Path $root "Media") -Filter *.png | Where-Object { $_.Name -notlike "logo*" }
if ($shots) {
    $shotDir = Join-Path $out "screenshots"
    New-Item -ItemType Directory -Force $shotDir | Out-Null
    $shots | Copy-Item -Destination $shotDir -Force
}

"Built $zipPath"
Get-ChildItem $out -Recurse -File | ForEach-Object { "  " + $_.FullName.Substring($out.Length + 1) + "  (" + $_.Length + " bytes)" }
