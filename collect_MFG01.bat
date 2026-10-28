@echo off
setlocal
set "MFG_COLLECT_SCRIPT=%~f0"
set "MFG_COLLECT_ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:MFG_COLLECT_SCRIPT); $m='# POWERSHELL_PAYLOAD'; $p=$s.Substring($s.LastIndexOf($m)+$m.Length); & ([scriptblock]::Create($p))"
set "MFG_COLLECT_RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %MFG_COLLECT_RESULT%
# POWERSHELL_PAYLOAD
$ErrorActionPreference = 'Stop'
$release = $null
try {
    $root = $env:MFG_COLLECT_ROOT
    $source = Join-Path $root 'Project Outputs for MFG01'
    $pdf = Join-Path $root 'MFG01_02.pdf'
    $groups = @('BOM', 'ERC', 'DRC', 'Gerber', 'NC Drill')
    $filesByGroup = @{}
    $missing = @()
    foreach ($group in $groups) {
        $folder = Join-Path $source $group
        $files = @()
        if (Test-Path -LiteralPath $folder -PathType Container) {
            $files = @(Get-ChildItem -LiteralPath $folder -File -Recurse)
        }
        if (@($files | Where-Object { $_.Length -gt 0 }).Count -eq 0) {
            $missing += "Missing or empty folder: $folder"
        }
        $filesByGroup[$group] = $files
    }
    if (!(Test-Path -LiteralPath $pdf -PathType Leaf)) {
        $missing += "Missing PDF: $pdf"
    } elseif ((Get-Item -LiteralPath $pdf).Length -eq 0) {
        $missing += "Empty PDF: $pdf"
    }
    if ($missing.Count -gt 0) {
        throw ($missing -join [Environment]::NewLine)
    }
    $releaseBase = Join-Path $root 'Release'
    New-Item -ItemType Directory -Path $releaseBase -Force | Out-Null
    $name = 'MFG01_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [guid]::NewGuid().ToString('N').Substring(0,6)
    $release = Join-Path $releaseBase $name
    New-Item -ItemType Directory -Path $release | Out-Null
    foreach ($group in $groups) {
        $from = Join-Path $source $group
        $to = Join-Path $release $group
        New-Item -ItemType Directory -Path $to | Out-Null
        foreach ($file in $filesByGroup[$group]) {
            $relative = $file.FullName.Substring($from.Length).TrimStart([char]'\')
            $target = Join-Path $to $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $target
        }
    }
    $pdfFolder = Join-Path $release 'PDF'
    New-Item -ItemType Directory -Path $pdfFolder | Out-Null
    Copy-Item -LiteralPath $pdf -Destination $pdfFolder
    $manifest = foreach ($file in Get-ChildItem -LiteralPath $release -File -Recurse) {
        [pscustomobject]@{
            File = $file.FullName.Substring($release.Length + 1)
            Bytes = $file.Length
            SourceModified = $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            SHA256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
    }
    $manifest | Export-Csv -LiteralPath (Join-Path $release 'files.csv') -NoTypeInformation -Encoding UTF8
    @(
        'MFG01 - collected existing output files'
        ('Collected: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
        'This script copies existing files. It does not run Altium, ERC, DRC or exports.'
        'Files may come from different export dates. Review files.csv and the reports.'
        'Folder presence does not establish manufacturing completeness or successful validation.'
        'ERC may be a manually transcribed Messages report. Preserve its warnings.'
    ) | Set-Content -LiteralPath (Join-Path $release 'README.txt') -Encoding UTF8
    Write-Host ('Created: ' + $release) -ForegroundColor Green
    Write-Host ('Copied files: ' + @($manifest).Count)
    Write-Host 'Existing reports and fabrication files have NOT been regenerated.'
    exit 0
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    if ($release) { Write-Host ('Incomplete output may remain at: ' + $release) }
    exit 1
}
