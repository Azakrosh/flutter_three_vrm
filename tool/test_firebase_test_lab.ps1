$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'firebase_test_lab.ps1')

function Assert-Equal {
  param(
    [Parameter(Mandatory = $true)]$Actual,
    [Parameter(Mandatory = $true)]$Expected,
    [Parameter(Mandatory = $true)][string]$Message
  )

  if ($Actual -ne $Expected) {
    throw "$Message Expected '$Expected', received '$Actual'."
  }
}

Assert-Equal `
  -Actual (Resolve-FirebaseMatrixId -Output @('matrix-exact123')) `
  -Expected 'matrix-exact123' `
  -Message 'Formatted matrix ID was not preserved.'
Assert-Equal `
  -Actual (Resolve-FirebaseMatrixId -Output @(
    'Test [matrix-fallback123] was created.',
    'Matrix [matrix-fallback123] failed validation.'
  )) `
  -Expected 'matrix-fallback123' `
  -Message 'Validation-error matrix ID was not recovered.'
try {
  Resolve-FirebaseMatrixId -Output @('matrix-first', 'matrix-second') | Out-Null
  throw 'Ambiguous matrix IDs were accepted.'
}
catch {
  if ($_.Exception.Message -notmatch 'unambiguous') {
    throw
  }
}

foreach ($terminalState in @(
  'FINISHED',
  'ERROR',
  'UNSUPPORTED_ENVIRONMENT',
  'INCOMPATIBLE_ENVIRONMENT',
  'INCOMPATIBLE_ARCHITECTURE',
  'CANCELLED',
  'INVALID'
)) {
  Assert-Equal `
    -Actual (Test-FirebaseMatrixTerminalState -State $terminalState) `
    -Expected $true `
    -Message "$terminalState must be terminal."
}
Assert-Equal `
  -Actual (Test-FirebaseMatrixTerminalState -State 'RUNNING') `
  -Expected $false `
  -Message 'RUNNING must not be terminal.'

$matrix = [pscustomobject]@{
  testMatrixId = 'matrix-sample123'
  projectId = 'sample-project'
  state = 'FINISHED'
  outcomeSummary = 'SUCCESS'
  invalidMatrixDetails = $null
  extendedInvalidMatrixDetails = @()
  timestamp = '2026-09-27T00:00:00Z'
  resultStorage = [pscustomobject]@{
    googleCloudStorage = [pscustomobject]@{
      gcsPath = 'gs://sample-bucket/results/'
    }
    toolResultsExecution = [pscustomobject]@{
      historyId = 'history-1'
      executionId = 'execution-1'
    }
  }
  testExecutions = @(
    [pscustomobject]@{
      id = 'device-execution-1'
      state = 'FINISHED'
      environment = [pscustomobject]@{
        androidDevice = [pscustomobject]@{
          androidModelId = 'austin'
          androidVersionId = '33'
          locale = 'en'
          orientation = 'portrait'
        }
      }
    }
  )
}
$artifactManifest = [pscustomobject]@{
  schemaVersion = 1
  createdAtUtc = '2026-09-27T00:00:00Z'
  soakSeconds = 30
  loadCycles = 3
  injectMemoryPressure = $true
  target = 'integration_test/performance_soak_test.dart'
  targetPlatform = 'android-arm64'
  appApk = [pscustomobject]@{
    fileName = 'app-debug.apk'
    length = 123
    sha256 = 'APP_HASH'
  }
  testApk = [pscustomobject]@{
    fileName = 'app-debug-androidTest.apk'
    length = 456
    sha256 = 'TEST_HASH'
  }
}
$record = ConvertTo-FirebaseRunRecord `
  -Matrix $matrix `
  -Label 'sample-run' `
  -RunIndex 1 `
  -RunCount 2 `
  -RequestedDeviceModel 'austin' `
  -RequestedOsVersion '33' `
  -ArtifactManifest $artifactManifest
Assert-Equal -Actual $record.matrixId -Expected 'matrix-sample123' -Message 'Matrix ID mismatch.'
Assert-Equal -Actual $record.outcomeSummary -Expected 'SUCCESS' -Message 'Outcome mismatch.'
Assert-Equal -Actual $record.executions[0].deviceModel -Expected 'austin' -Message 'Device mismatch.'
Assert-Equal -Actual $record.artifacts.appApk.sha256 -Expected 'APP_HASH' -Message 'APK hash mismatch.'
Assert-Equal `
  -Actual $record.resultStorage.consoleUrl `
  -Expected 'https://console.firebase.google.com/project/sample-project/testlab/histories/history-1/matrices/execution-1' `
  -Message 'Console URL mismatch.'

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "flutter-three-vrm-test-$([Guid]::NewGuid())"
$recordPath = Join-Path $temporaryRoot 'record.json'
try {
  Write-AtomicJson -Path $recordPath -Value $record
  $saved = Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json
  Assert-Equal -Actual $saved.schemaVersion -Expected 1 -Message 'Saved schema mismatch.'
  Assert-Equal -Actual $saved.matrixId -Expected 'matrix-sample123' -Message 'Saved matrix mismatch.'
  if (Test-Path -LiteralPath "$recordPath.tmp") {
    throw 'Atomic writer left a temporary file behind.'
  }
}
finally {
  if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
  }
}

Write-Host 'Firebase Test Lab tooling tests passed.'
