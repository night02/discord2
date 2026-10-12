# Windows fallback for Veylor V0.3.3 when GitHub-hosted runners cannot start.
# Requires Flutter stable, Visual Studio C++ desktop workload, Node.js 22+, Inno Setup 6.
[CmdletBinding()]
param()
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$clientRoot = Join-Path $repoRoot "apps\client"
$serverRoot = Join-Path $repoRoot "apps\server"
$version = "0.3.3"
$setupName = "Veylor-v$version-Setup-Windows-x64.exe"
$zipName = "Veylor-v$version-Windows-x64.zip"
$releaseDir = Join-Path $clientRoot "build\windows\x64\runner\Release"
$distDir = Join-Path $repoRoot "dist"
New-Item -ItemType Directory -Path $distDir -Force | Out-Null

function Invoke-Checked([string]$file, [string[]]$arguments) {
    Write-Host ("> " + $file + " " + ($arguments -join " "))
    & $file @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$file exited with code $LASTEXITCODE"
    }
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter stable is missing from PATH."
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "Node.js 22+ is required for backend tests."
}
try {
    Push-Location $serverRoot
    Invoke-Checked "npm.cmd" @("install", "--no-audit", "--no-fund")
    Invoke-Checked "node" @("--test", "test/api.test.mjs", "test/v02.test.mjs", "test/two_clients.test.mjs", "test/updates.test.mjs", "test/startup.test.mjs", "test/reconnect.test.mjs")
    Pop-Location
    Push-Location $clientRoot
    Invoke-Checked "flutter" @("config", "--enable-windows-desktop")
    Invoke-Checked "flutter" @("create", "--project-name", "veylor", "--platforms=windows", ".")
    Invoke-Checked "flutter" @("pub", "get")
    # Remove only the known Flutter-generated MyApp counter test (not Veylor tests).
    $generatedTest = Join-Path $clientRoot "test\widget_test.dart"
    if (Test-Path $generatedTest) {
        $generatedContent = Get-Content $generatedTest -Raw
        if ($generatedContent -match 'pumpWidget\(const MyApp\(') {
            Remove-Item $generatedTest -Force
        }
    }
    Invoke-Checked "flutter" @("analyze", "--no-fatal-infos")
    # Do not run Flutter's generated counter-app test; run all real app tests.
    $testFiles = @(Get-ChildItem -Path (Join-Path $clientRoot "test") -Filter "*_test.dart" |
        Where-Object { $_.Name -ne "widget_test.dart" } |
        ForEach-Object { "test/$($_.Name)" })
    if ($testFiles.Count -lt 1) { throw "No tests found, refusing build." }
    Invoke-Checked "flutter" (@("test") + $testFiles)
    Invoke-Checked "flutter" @("build", "windows", "--release")
    $exe = Join-Path $releaseDir "veylor.exe"
    if (-not (Test-Path $exe)) { throw "No Windows EXE produced." }
    $zip = Join-Path $distDir $zipName
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $releaseDir "*") -DestinationPath $zip -CompressionLevel Optimal
    if ((Get-Item $zip).Length -lt 1048576) { throw "Portable ZIP unexpectedly small." }
    $pf86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    $iscc = @(
        (Join-Path $pf86 "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $iscc) { throw "Inno Setup 6 not installed. Portable ZIP exists in dist." }
    Invoke-Checked $iscc @("windows-installer.iss")
    $setupSrc = Join-Path $clientRoot "dist\$setupName"
    if (-not (Test-Path $setupSrc)) { throw "Expected installer EXE not generated." }
    $setupDst = Join-Path $distDir $setupName
    Copy-Item $setupSrc $setupDst -Force
    Get-FileHash -Algorithm SHA256 -Path $zip, $setupDst |
        ForEach-Object { "$($_.Hash.ToLowerInvariant())  $(Split-Path $_.Path -Leaf)" } |
        Set-Content -Path (Join-Path $distDir "SHA256SUMS-windows.txt") -Encoding ascii
    Write-Host ("OK! Installer: " + $setupDst)
    Write-Host ("Portable: " + $zip)
    Write-Warning "Installer has no Authenticode signature. Keep Windows security enabled."
}
finally {
    Set-Location $repoRoot
}
