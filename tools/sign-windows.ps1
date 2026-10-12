# Sign an .exe with a trusted, timestamped Authenticode certificate.
# Signing material exists on the hosted runner only, never in the repository.
param([Parameter(Mandatory = $true)][string]$FilePath)
$ErrorActionPreference = 'Stop'
$inputFile = (Resolve-Path -LiteralPath $FilePath -ErrorAction Stop).Path
if ([IO.Path]::GetExtension($inputFile).ToLowerInvariant() -ne '.exe') {
  throw 'Expected an .exe target.'
}
if ([string]::IsNullOrWhiteSpace($env:VEYLOR_WINDOWS_PFX_BASE64) -or [string]::IsNullOrWhiteSpace($env:VEYLOR_WINDOWS_PFX_PASSWORD)) {
  throw 'A valid Authenticode certificate and its password are required.'
}
$sdkRoot = [Environment]::GetFolderPath('ProgramFilesX86') + '\Windows Kits\10\bin'
$tools = @(Get-ChildItem -Path "$sdkRoot\*\x64\signtool.exe" -File -ErrorAction SilentlyContinue | Sort-Object FullName -Descending)
if ($tools.Count -eq 0) { throw 'Windows SDK SignTool.exe not found.' }
$tool = $tools[0].FullName
$pfxPath = Join-Path $env:RUNNER_TEMP ('veylor-signing-' + [guid]::NewGuid().ToString('N') + '.pfx')
try {
  $pfxBytes = [Convert]::FromBase64String($env:VEYLOR_WINDOWS_PFX_BASE64)
  if ($pfxBytes.Length -lt 400) { throw 'Signing certificate is invalid or empty.' }
  [IO.File]::WriteAllBytes($pfxPath, $pfxBytes)
  & $tool sign /fd SHA256 /td SHA256 /tr 'http://timestamp.digicert.com' /f "$pfxPath" /p "$env:VEYLOR_WINDOWS_PFX_PASSWORD" "$inputFile"
  if ($LASTEXITCODE -ne 0) { throw "SignTool sign failed for $(Split-Path -Leaf $inputFile)" }
  & $tool verify /pa /tw "$inputFile"
  if ($LASTEXITCODE -ne 0) { throw "SignTool trust/timestamp verification failed for $(Split-Path -Leaf $inputFile)" }
  Write-Output "Verified trusted Authenticode signature: $(Split-Path -Leaf $inputFile)"
} finally {
  if (Test-Path -LiteralPath $pfxPath) { Remove-Item -LiteralPath $pfxPath -Force }
  $pfxBytes = $null
}
