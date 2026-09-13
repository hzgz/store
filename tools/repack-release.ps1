param(
    [string]$SourceRoot = 'C:\Users\Administrator\Desktop\sdsssdddddd',
    [string]$ReleaseDate = '20260913'
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$releaseRoot = Join-Path $repoRoot ("releases\{0}" -f $ReleaseDate)
$stageRoot = Join-Path $repoRoot ("releases\{0}.repack" -f $ReleaseDate)

if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    throw "source directory missing: $SourceRoot"
}
if (-not (Test-Path -LiteralPath $releaseRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $releaseRoot | Out-Null
}
if (-not $stageRoot.StartsWith($repoRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "stage path escaped repository: $stageRoot"
}
if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $stageRoot | Out-Null

$jsonPath = Join-Path $repoRoot 'xarryuan.json'
$catalog = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
$templatePay = @(
    'modern_hy', 'pay2', 'pay3', 'pay4', 'pay5', 'pay6', 'pay7',
    'pay8', 'pay9', 'pay10', 'pay11', 'pay12', 'pay13'
)
$downloadable = @($catalog.data.plugins | Where-Object { $null -ne $_.download_url })
if ($downloadable.Count -ne 52) {
    throw "expected 52 downloadable applications, got $($downloadable.Count)"
}

$hashes = @{}
foreach ($plugin in $downloadable) {
    if ($templatePay -contains $plugin.name) {
        $sourcePath = Join-Path $SourceRoot ("templates\pay\{0}" -f $plugin.name)
    } elseif ($plugin.name -eq 'hg_index_3') {
        $sourcePath = Join-Path $SourceRoot 'templates\index\hg_index_3'
    } elseif (Test-Path -LiteralPath (Join-Path $SourceRoot ("plugins\pay\{0}" -f $plugin.name))) {
        $sourcePath = Join-Path $SourceRoot ("plugins\pay\{0}" -f $plugin.name)
    } else {
        $sourcePath = Join-Path $SourceRoot ("plugins\storage\{0}" -f $plugin.name)
    }

    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        throw "source directory missing for $($plugin.name): $sourcePath"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $sourcePath 'manifest.json') -PathType Leaf)) {
        throw "manifest missing for $($plugin.name): $sourcePath"
    }

    $zipPath = Join-Path $stageRoot ("{0}.zip" -f $plugin.uuid)
    Compress-Archive -LiteralPath $sourcePath -DestinationPath $zipPath -CompressionLevel Optimal
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$manifestErrors = [System.Collections.Generic.List[string]]::new()
foreach ($plugin in $downloadable) {
    $zipPath = Join-Path $stageRoot ("{0}.zip" -f $plugin.uuid)
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entry = $archive.GetEntry(("{0}/manifest.json" -f $plugin.name))
        if ($null -eq $entry) {
            $manifestErrors.Add("$($plugin.name): missing $($plugin.name)/manifest.json")
            continue
        }
        $reader = [System.IO.StreamReader]::new($entry.Open(), [System.Text.Encoding]::UTF8, $true)
        try {
            $manifest = $reader.ReadToEnd() | ConvertFrom-Json
        } finally {
            $reader.Dispose()
        }
        if ($manifest.name -ne $plugin.name) {
            $manifestErrors.Add("$($plugin.name): manifest.name=$($manifest.name)")
        }
    } finally {
        $archive.Dispose()
    }
    $hashes[$plugin.uuid] = (Get-FileHash -LiteralPath $zipPath -Algorithm MD5).Hash.ToLowerInvariant()
}
if ($manifestErrors.Count -gt 0) {
    throw ($manifestErrors -join '; ')
}

foreach ($plugin in $catalog.data.plugins) {
    if ($null -ne $plugin.download_url) {
        $plugin.download_url = "https://raw.githubusercontent.com/hzgz/store/refs/heads/main/releases/$ReleaseDate/$($plugin.uuid).zip"
        if ($null -eq $plugin.PSObject.Properties['download_filename']) {
            $plugin | Add-Member -NotePropertyName download_filename -NotePropertyValue $null
        }
        if ($null -eq $plugin.PSObject.Properties['md5']) {
            $plugin | Add-Member -NotePropertyName md5 -NotePropertyValue $null
        }
        $plugin.download_filename = "$($plugin.name).zip"
        $plugin.md5 = $hashes[$plugin.uuid]
    } else {
        if ($null -eq $plugin.PSObject.Properties['download_filename']) {
            $plugin | Add-Member -NotePropertyName download_filename -NotePropertyValue $null
        }
        if ($null -eq $plugin.PSObject.Properties['md5']) {
            $plugin | Add-Member -NotePropertyName md5 -NotePropertyValue $null
        }
        $plugin.download_url = $null
        $plugin.download_filename = $null
        $plugin.md5 = $null
    }
}
$catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$oldArchives = @(Get-ChildItem -LiteralPath $releaseRoot -File -Filter '*.zip')
$oldArchives | Remove-Item -Force
Get-ChildItem -LiteralPath $stageRoot -File -Filter '*.zip' | Move-Item -Destination $releaseRoot
Remove-Item -LiteralPath $stageRoot -Recurse -Force

Write-Output "packaged=$($downloadable.Count)"
Write-Output "release_zips=$(@(Get-ChildItem -LiteralPath $releaseRoot -File -Filter '*.zip').Count)"
Write-Output "catalog=$jsonPath"
