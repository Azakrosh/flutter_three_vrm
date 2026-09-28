$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'firebase_test_lab.ps1')
. (Join-Path $PSScriptRoot 'firebase_soak_evidence.ps1')

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

  $logcatPath = Join-Path $temporaryRoot 'logcat.txt'
  $junitPath = Join-Path $temporaryRoot 'junit.xml'
  $logcat = @'
09-27 18:35:00.000 I flutter : runtime_soak_load: loads=3, samples=3, frameP50Max=3925.5ms, frameP95Max=3925.5ms
09-27 18:35:01.000 I flutter : runtime_soak_steady: duration=30s, loads=3, samples=13, fps=28.8-31.5 (avg=30.8), frameP50Max=33.0ms, frameP95Max=53.6ms, longFrames=6/399, longestFrameMax=71.1ms, longFrameSources=none,externalScheduling, updateP95Max=16.5ms, renderP95Max=22.3ms, adaptiveDecisions=collectingFast,stable,atMaximum, pixelRatio=1.00-1.00, textures=28,28,28/0,0,0, modelTextureBytes=96818517, modelTextureMiB=92.3, loadMs=1043.4,1015.0,643.6/953.4
09-27 18:35:02.000 I flutter : runtime_soak_host: rssStartEndMiB=298.5-417.4, rssDeltaMiB=118.9, rssLoadedMiB=663.4,647.3,633.9,510.6, rssUnloadedMiB=522.9,511.5,527.8,417.4, rssSampledPeakMiB=663.4, rssLoadedSlopeMiBPerCycle=-68.34, rssUnloadedSlopeMiBPerCycle=-47.03, maxRssMiB=668.1, memoryPressure=4, thermal=none
09-27 18:35:03.000 I flutter : runtime_soak_pressure: injected=true, observed=4, postPressureHealth=15, postPressureAmplitudeBatches=30, postPressureMotionTransitions=6, modelLoadedAfterPressure=true, contextLossAfterPressure=0
'@
  $junit = @'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites tests="1" failures="0" errors="0" skipped="0" time="30.223">
  <testsuite name="instrumentation" tests="1" failures="0" errors="0" skipped="0" time="30.223">
    <testcase name="profiles Android rendering and keeps resources bounded" classname="MainActivityTest" time="30.223" />
  </testsuite>
</testsuites>
'@
  [IO.File]::WriteAllText($logcatPath, $logcat, [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($junitPath, $junit, [Text.UTF8Encoding]::new($false))

  $evidence = New-FirebaseSoakEvidence `
    -RunRecord $record `
    -LogcatPath $logcatPath `
    -JunitPath $junitPath
  Assert-Equal -Actual $evidence.allPassed -Expected $true -Message 'Valid evidence failed.'
  Assert-Equal -Actual $evidence.telemetry.steady.fpsAverage -Expected 30.8 -Message 'FPS parsing mismatch.'
  Assert-Equal -Actual $evidence.telemetry.host.rssLoadedSlopeMiBPerCycle -Expected (-68.34) -Message 'RSS slope parsing mismatch.'
  Assert-Equal -Actual $evidence.checks.pressureRecoveryPassed -Expected $true -Message 'Pressure recovery mismatch.'
  $markdown = ConvertTo-FirebaseSoakMarkdown -Evidence $evidence
  if ($markdown -notmatch 'matrix-sample123' -or $markdown -notmatch 'textureBaselineStable') {
    throw 'Evidence Markdown omitted required identity or checks.'
  }

  $unstableLogcatPath = Join-Path $temporaryRoot 'unstable-logcat.txt'
  [IO.File]::WriteAllText(
    $unstableLogcatPath,
    $logcat.Replace('textures=28,28,28/0,0,0', 'textures=28,31,35/0,0,0'),
    [Text.UTF8Encoding]::new($false)
  )
  $unstableEvidence = New-FirebaseSoakEvidence `
    -RunRecord $record `
    -LogcatPath $unstableLogcatPath `
    -JunitPath $junitPath
  Assert-Equal -Actual $unstableEvidence.allPassed -Expected $false -Message 'Unstable textures were accepted.'
  Assert-Equal -Actual $unstableEvidence.checks.textureBaselineStable -Expected $false -Message 'Texture regression was not identified.'

  try {
    ConvertFrom-SoakTelemetryLines -Lines @($logcat -split "`r?`n" | Where-Object { $_ -notmatch 'runtime_soak_pressure:' }) | Out-Null
    throw 'Incomplete telemetry was accepted.'
  }
  catch {
    if ($_.Exception.Message -notmatch 'runtime_soak_pressure') {
      throw
    }
  }
}
finally {
  if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
  }
}

Write-Host 'Firebase Test Lab tooling tests passed.'
