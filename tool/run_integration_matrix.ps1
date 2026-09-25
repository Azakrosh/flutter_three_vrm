[CmdletBinding()]
param(
  [string]$AndroidDeviceId,
  [switch]$SkipAndroid,
  [switch]$SkipWindows,
  [switch]$SkipPerformance
)

$ErrorActionPreference = 'Stop'

if ($SkipAndroid -and $SkipWindows) {
  throw 'At least one target platform must be enabled.'
}
if (-not $SkipAndroid -and [string]::IsNullOrWhiteSpace($AndroidDeviceId)) {
  throw 'Pass -AndroidDeviceId or use -SkipAndroid.'
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$exampleRoot = Join-Path $repositoryRoot 'example'
$flutter = Get-Command flutter -ErrorAction Stop
$crossPlatformGates = @(
  'runtime_smoke_test.dart',
  'motion_speech_test.dart',
  'runtime_recovery_test.dart',
  'runtime_race_test.dart',
  'resource_loading_test.dart'
)

function Invoke-IntegrationGate {
  param(
    [Parameter(Mandatory = $true)][string]$Device,
    [Parameter(Mandatory = $true)][string]$TestFile
  )

  Write-Host "[$Device] $TestFile"
  & $flutter.Source test "integration_test/$TestFile" -d $Device
  if ($LASTEXITCODE -ne 0) {
    throw "Integration gate failed: $TestFile on $Device."
  }
}

Push-Location -LiteralPath $exampleRoot
try {
  if (-not $SkipAndroid) {
    foreach ($testFile in $crossPlatformGates) {
      Invoke-IntegrationGate -Device $AndroidDeviceId -TestFile $testFile
    }
    if (-not $SkipPerformance) {
      Invoke-IntegrationGate `
        -Device $AndroidDeviceId `
        -TestFile 'performance_soak_test.dart'
    }
  }

  if (-not $SkipWindows) {
    foreach ($testFile in $crossPlatformGates) {
      Invoke-IntegrationGate -Device 'windows' -TestFile $testFile
    }
  }
}
finally {
  Pop-Location
}

Write-Host 'Integration matrix passed.'
