$script:InvariantCulture = [Globalization.CultureInfo]::InvariantCulture

function ConvertTo-SoakDouble {
  param([Parameter(Mandatory = $true)][string]$Value)

  return [double]::Parse($Value, $script:InvariantCulture)
}

function ConvertTo-SoakDoubleList {
  param([Parameter(Mandatory = $true)][string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return @()
  }
  return @($Value.Split(',') | ForEach-Object { ConvertTo-SoakDouble $_ })
}

function ConvertTo-SoakIntList {
  param([Parameter(Mandatory = $true)][string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return @()
  }
  return @($Value.Split(',') | ForEach-Object { [int]::Parse($_, $script:InvariantCulture) })
}

function Get-SoakTelemetryPayload {
  param(
    [Parameter(Mandatory = $true)][string[]]$Lines,
    [Parameter(Mandatory = $true)][string]$Phase
  )

  $pattern = "runtime_soak_${Phase}: (?<payload>.+)$"
  $matches = @(
    foreach ($line in $Lines) {
      $match = [regex]::Match($line, $pattern)
      if ($match.Success) {
        $match.Groups['payload'].Value
      }
    }
  )
  if ($matches.Count -ne 1) {
    throw "Expected exactly one runtime_soak_${Phase} line, found $($matches.Count)."
  }
  return $matches[0]
}

function ConvertFrom-SoakTelemetryLines {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string[]]$Lines)

  $loadPayload = Get-SoakTelemetryPayload -Lines $Lines -Phase 'load'
  $loadMatch = [regex]::Match(
    $loadPayload,
    '^loads=(?<loads>\d+), samples=(?<samples>\d+), frameP50Max=(?<p50>[\d.]+)ms, frameP95Max=(?<p95>[\d.]+)ms$'
  )
  if (-not $loadMatch.Success) {
    throw 'runtime_soak_load does not match the supported evidence schema.'
  }

  $steadyPayload = Get-SoakTelemetryPayload -Lines $Lines -Phase 'steady'
  $steadyMatch = [regex]::Match(
    $steadyPayload,
    '^duration=(?<duration>\d+)s, loads=(?<loads>\d+), samples=(?<samples>\d+), fps=(?<fpsMin>[\d.]+)-(?<fpsMax>[\d.]+) \(avg=(?<fpsAverage>[\d.]+)\), frameP50Max=(?<p50>[\d.]+)ms, frameP95Max=(?<p95>[\d.]+)ms, longFrames=(?<longFrames>\d+)/(?<frameSamples>\d+), longestFrameMax=(?<longest>[\d.]+)ms, longFrameSources=(?<sources>.*?), updateP95Max=(?<updateP95>[\d.]+)ms, renderP95Max=(?<renderP95>[\d.]+)ms, adaptiveDecisions=(?<decisions>.*?), pixelRatio=(?<ratioMin>[\d.]+)-(?<ratioMax>[\d.]+), textures=(?<loadedTextures>[\d,]+)/(?<unloadedTextures>[\d,]+), modelTextureBytes=(?<textureBytes>\d+), modelTextureMiB=(?<textureMiB>[\d.]+), loadMs=(?<loadMs>[\d.,]+)/(?<finalLoadMs>[\d.]+)$'
  )
  if (-not $steadyMatch.Success) {
    throw 'runtime_soak_steady does not match the supported evidence schema.'
  }

  $hostPayload = Get-SoakTelemetryPayload -Lines $Lines -Phase 'host'
  $hostMatch = [regex]::Match(
    $hostPayload,
    '^rssStartEndMiB=(?<rssStart>-?[\d.]+)-(?<rssEnd>-?[\d.]+), rssDeltaMiB=(?<rssDelta>-?[\d.]+), rssLoadedMiB=(?<rssLoaded>-?[\d.,]+), rssUnloadedMiB=(?<rssUnloaded>-?[\d.,]+), rssSampledPeakMiB=(?<rssPeak>-?[\d.]+), rssLoadedSlopeMiBPerCycle=(?<loadedSlope>-?[\d.]+), rssUnloadedSlopeMiBPerCycle=(?<unloadedSlope>-?[\d.]+), maxRssMiB=(?<maxRss>-?[\d.]+), memoryPressure=(?<memoryPressure>\d+), thermal=(?<thermal>[a-zA-Z]+)$'
  )
  if (-not $hostMatch.Success) {
    throw 'runtime_soak_host does not match the supported evidence schema.'
  }

  $pressurePayload = Get-SoakTelemetryPayload -Lines $Lines -Phase 'pressure'
  $pressureMatch = [regex]::Match(
    $pressurePayload,
    '^injected=(?<injected>true|false), observed=(?<observed>\d+), postPressureHealth=(?<health>\d+), postPressureAmplitudeBatches=(?<amplitude>\d+), postPressureMotionTransitions=(?<motion>\d+), modelLoadedAfterPressure=(?<model>true|false|notChecked), contextLossAfterPressure=(?<context>\d+|notChecked)$'
  )
  if (-not $pressureMatch.Success) {
    throw 'runtime_soak_pressure does not match the supported evidence schema.'
  }

  $loadedTextureCounts = ConvertTo-SoakIntList $steadyMatch.Groups['loadedTextures'].Value
  $unloadedTextureCounts = ConvertTo-SoakIntList $steadyMatch.Groups['unloadedTextures'].Value
  return [ordered]@{
    load = [ordered]@{
      loads = [int]$loadMatch.Groups['loads'].Value
      samples = [int]$loadMatch.Groups['samples'].Value
      frameP50MaxMs = ConvertTo-SoakDouble $loadMatch.Groups['p50'].Value
      frameP95MaxMs = ConvertTo-SoakDouble $loadMatch.Groups['p95'].Value
    }
    steady = [ordered]@{
      durationSeconds = [int]$steadyMatch.Groups['duration'].Value
      loads = [int]$steadyMatch.Groups['loads'].Value
      samples = [int]$steadyMatch.Groups['samples'].Value
      fpsMin = ConvertTo-SoakDouble $steadyMatch.Groups['fpsMin'].Value
      fpsMax = ConvertTo-SoakDouble $steadyMatch.Groups['fpsMax'].Value
      fpsAverage = ConvertTo-SoakDouble $steadyMatch.Groups['fpsAverage'].Value
      frameP50MaxMs = ConvertTo-SoakDouble $steadyMatch.Groups['p50'].Value
      frameP95MaxMs = ConvertTo-SoakDouble $steadyMatch.Groups['p95'].Value
      longFrameCount = [int]$steadyMatch.Groups['longFrames'].Value
      frameSampleCount = [int]$steadyMatch.Groups['frameSamples'].Value
      longestFrameMaxMs = ConvertTo-SoakDouble $steadyMatch.Groups['longest'].Value
      longFrameSources = @($steadyMatch.Groups['sources'].Value.Split(','))
      updateP95MaxMs = ConvertTo-SoakDouble $steadyMatch.Groups['updateP95'].Value
      renderP95MaxMs = ConvertTo-SoakDouble $steadyMatch.Groups['renderP95'].Value
      adaptiveDecisions = @($steadyMatch.Groups['decisions'].Value.Split(','))
      pixelRatioMin = ConvertTo-SoakDouble $steadyMatch.Groups['ratioMin'].Value
      pixelRatioMax = ConvertTo-SoakDouble $steadyMatch.Groups['ratioMax'].Value
      loadedTextureCounts = $loadedTextureCounts
      unloadedTextureCounts = $unloadedTextureCounts
      modelTextureBytes = [long]$steadyMatch.Groups['textureBytes'].Value
      modelTextureMiB = ConvertTo-SoakDouble $steadyMatch.Groups['textureMiB'].Value
      loadDurationsMs = ConvertTo-SoakDoubleList $steadyMatch.Groups['loadMs'].Value
      finalLoadDurationMs = ConvertTo-SoakDouble $steadyMatch.Groups['finalLoadMs'].Value
    }
    host = [ordered]@{
      rssStartMiB = ConvertTo-SoakDouble $hostMatch.Groups['rssStart'].Value
      rssEndMiB = ConvertTo-SoakDouble $hostMatch.Groups['rssEnd'].Value
      rssDeltaMiB = ConvertTo-SoakDouble $hostMatch.Groups['rssDelta'].Value
      rssLoadedMiB = ConvertTo-SoakDoubleList $hostMatch.Groups['rssLoaded'].Value
      rssUnloadedMiB = ConvertTo-SoakDoubleList $hostMatch.Groups['rssUnloaded'].Value
      rssSampledPeakMiB = ConvertTo-SoakDouble $hostMatch.Groups['rssPeak'].Value
      rssLoadedSlopeMiBPerCycle = ConvertTo-SoakDouble $hostMatch.Groups['loadedSlope'].Value
      rssUnloadedSlopeMiBPerCycle = ConvertTo-SoakDouble $hostMatch.Groups['unloadedSlope'].Value
      maxRssMiB = ConvertTo-SoakDouble $hostMatch.Groups['maxRss'].Value
      memoryPressureCount = [int]$hostMatch.Groups['memoryPressure'].Value
      thermal = $hostMatch.Groups['thermal'].Value
    }
    pressure = [ordered]@{
      injected = $pressureMatch.Groups['injected'].Value -eq 'true'
      observed = [int]$pressureMatch.Groups['observed'].Value
      postPressureHealth = [int]$pressureMatch.Groups['health'].Value
      postPressureAmplitudeBatches = [int]$pressureMatch.Groups['amplitude'].Value
      postPressureMotionTransitions = [int]$pressureMatch.Groups['motion'].Value
      modelLoadedAfterPressure = $pressureMatch.Groups['model'].Value
      contextLossAfterPressure = $pressureMatch.Groups['context'].Value
    }
    raw = [ordered]@{
      load = $loadPayload
      steady = $steadyPayload
      host = $hostPayload
      pressure = $pressurePayload
    }
  }
}

function Read-FirebaseJUnitEvidence {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Path)

  [xml]$document = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  $suites = @($document.testsuites.testsuite)
  if ($suites.Count -eq 0) {
    throw "JUnit artifact contains no test suites: $Path"
  }
  $tests = 0
  $failures = 0
  $errors = 0
  $skipped = 0
  $durationSeconds = 0.0
  $cases = @()
  foreach ($suite in $suites) {
    $tests += [int]$suite.tests
    $failures += [int]$suite.failures
    $errors += [int]$suite.errors
    $skipped += [int]$suite.skipped
    $durationSeconds += ConvertTo-SoakDouble $suite.time
    $cases += @(
      foreach ($case in @($suite.testcase)) {
        [ordered]@{
          name = $case.name
          className = $case.classname
          durationSeconds = ConvertTo-SoakDouble $case.time
        }
      }
    )
  }
  return [ordered]@{
    tests = $tests
    failures = $failures
    errors = $errors
    skipped = $skipped
    durationSeconds = $durationSeconds
    testCases = $cases
  }
}

function New-FirebaseSoakEvidence {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$RunRecord,
    [Parameter(Mandatory = $true)][string]$LogcatPath,
    [Parameter(Mandatory = $true)][string]$JunitPath
  )

  $telemetry = ConvertFrom-SoakTelemetryLines -Lines (Get-Content -LiteralPath $LogcatPath -Encoding UTF8)
  $junit = Read-FirebaseJUnitEvidence -Path $JunitPath
  $expectedCycles = [int]$RunRecord.artifacts.loadCycles
  $loadedTextures = @($telemetry.steady.loadedTextureCounts)
  $unloadedTextures = @($telemetry.steady.unloadedTextureCounts)
  $loadedTextureRange = ($loadedTextures | Measure-Object -Maximum).Maximum -
    ($loadedTextures | Measure-Object -Minimum).Minimum
  $unloadedTextureRange = ($unloadedTextures | Measure-Object -Maximum).Maximum -
    ($unloadedTextures | Measure-Object -Minimum).Minimum
  $textureBaselineStable = $loadedTextures.Count -eq $expectedCycles -and
    $unloadedTextures.Count -eq $expectedCycles -and
    $loadedTextureRange -le 1 -and
    $unloadedTextureRange -le 1
  $profileMatchesManifest = $telemetry.load.loads -eq $expectedCycles -and
    $telemetry.steady.loads -eq $expectedCycles -and
    $telemetry.steady.durationSeconds -eq [int]$RunRecord.artifacts.soakSeconds
  $junitPassed = $junit.tests -gt 0 -and $junit.failures -eq 0 -and
    $junit.errors -eq 0 -and $junit.skipped -eq 0
  $pressureRecoveryPassed = $true
  if ([bool]$RunRecord.artifacts.injectMemoryPressure) {
    $pressureRecoveryPassed = $telemetry.pressure.injected -and
      $telemetry.pressure.postPressureHealth -gt 0 -and
      $telemetry.pressure.postPressureAmplitudeBatches -gt 0 -and
      $telemetry.pressure.postPressureMotionTransitions -gt 0 -and
      $telemetry.pressure.modelLoadedAfterPressure -eq 'true' -and
      $telemetry.pressure.contextLossAfterPressure -eq '0'
  }
  $checks = [ordered]@{
    matrixSuccess = $RunRecord.state -eq 'FINISHED' -and
      $RunRecord.outcomeSummary -eq 'SUCCESS'
    junitPassed = $junitPassed
    profileMatchesManifest = $profileMatchesManifest
    textureBaselineStable = $textureBaselineStable
    pressureRecoveryPassed = $pressureRecoveryPassed
  }
  $allPassed = -not (@($checks.Values) -contains $false)
  return [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    run = $RunRecord
    junit = $junit
    telemetry = $telemetry
    checks = $checks
    allPassed = $allPassed
    sourceFiles = [ordered]@{
      logcat = (Resolve-Path $LogcatPath).Path
      junit = (Resolve-Path $JunitPath).Path
    }
  }
}

function ConvertTo-FirebaseSoakMarkdown {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)]$Evidence)

  $run = $Evidence.run
  $steady = $Evidence.telemetry.steady
  $hostMetrics = $Evidence.telemetry.host
  $lines = @(
    "# Firebase soak evidence: $($run.matrixId)",
    '',
    "- Outcome: $($run.state) / $($run.outcomeSummary)",
    "- Device: $($run.requestedDevice.model) / Android $($run.requestedDevice.osVersion)",
    "- Profile: $($run.artifacts.soakSeconds)s / $($run.artifacts.loadCycles) cycles",
    "- App APK SHA-256: $($run.artifacts.appApk.sha256)",
    "- Console: $($run.resultStorage.consoleUrl)",
    '',
    '## Checks',
    '',
    '| Check | Result |',
    '|---|---|'
  )
  foreach ($entry in $Evidence.checks.GetEnumerator()) {
    $lines += "| $($entry.Key) | $($entry.Value) |"
  }
  $lines += @(
    '',
    '## Profile',
    '',
    '| Metric | Value |',
    '|---|---:|',
    "| Steady FPS min-max / average | $($steady.fpsMin)-$($steady.fpsMax) / $($steady.fpsAverage) |",
    "| Frame p50 / p95 max | $($steady.frameP50MaxMs) / $($steady.frameP95MaxMs) ms |",
    "| Long frames | $($steady.longFrameCount) / $($steady.frameSampleCount) |",
    "| Pixel ratio | $($steady.pixelRatioMin)-$($steady.pixelRatioMax) |",
    "| Texture baseline | $($steady.loadedTextureCounts -join ',') / $($steady.unloadedTextureCounts -join ',') |",
    "| RSS sampled / normalized max | $($hostMetrics.rssSampledPeakMiB) / $($hostMetrics.maxRssMiB) MiB |",
    "| RSS loaded / unloaded slope | $($hostMetrics.rssLoadedSlopeMiBPerCycle) / $($hostMetrics.rssUnloadedSlopeMiBPerCycle) MiB/cycle |",
    "| Memory pressure / thermal | $($hostMetrics.memoryPressureCount) / $($hostMetrics.thermal) |",
    '',
    "Overall: **$($Evidence.allPassed)**"
  )
  return $lines -join "`n"
}

function Write-AtomicUtf8Text {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Value
  )

  $parent = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  $temporaryPath = "$Path.tmp"
  [IO.File]::WriteAllText($temporaryPath, "$Value`n", [Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Export-FirebaseSoakEvidence {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$GcloudExecutable,
    [Parameter(Mandatory = $true)]$RunRecord,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
  )

  if ($RunRecord.state -ne 'FINISHED' -or $RunRecord.outcomeSummary -ne 'SUCCESS') {
    throw "Evidence can only be exported for a successful matrix: $($RunRecord.matrixId)"
  }
  $gcsPath = $RunRecord.resultStorage.gcsPath
  if ([string]::IsNullOrWhiteSpace($gcsPath) -or -not $gcsPath.StartsWith('gs://')) {
    throw "Run record does not contain a valid GCS path: $($RunRecord.matrixId)"
  }
  $listing = @(& $GcloudExecutable storage ls --recursive "${gcsPath}**" 2>&1)
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to list Firebase artifacts for $($RunRecord.matrixId)."
  }
  $uris = @($listing | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -match '^gs://' })
  $logcatUris = @($uris | Where-Object { $_ -match '/logcat$' })
  $junitUris = @($uris | Where-Object { $_ -match '/test_result_\d+\.xml$' })
  if ($logcatUris.Count -ne 1 -or $junitUris.Count -ne 1) {
    throw "Expected one logcat and one JUnit artifact for $($RunRecord.matrixId); found $($logcatUris.Count) and $($junitUris.Count)."
  }
  New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
  $logcatPath = Join-Path $OutputDirectory 'logcat.txt'
  $junitPath = Join-Path $OutputDirectory 'junit.xml'
  & $GcloudExecutable storage cp $logcatUris[0] $logcatPath
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to download Firebase logcat for $($RunRecord.matrixId)."
  }
  & $GcloudExecutable storage cp $junitUris[0] $junitPath
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to download Firebase JUnit for $($RunRecord.matrixId)."
  }

  $evidence = New-FirebaseSoakEvidence `
    -RunRecord $RunRecord `
    -LogcatPath $logcatPath `
    -JunitPath $junitPath
  $jsonPath = Join-Path $OutputDirectory 'evidence.json'
  $markdownPath = Join-Path $OutputDirectory 'evidence.md'
  Write-AtomicJson -Path $jsonPath -Value $evidence
  Write-AtomicUtf8Text `
    -Path $markdownPath `
    -Value (ConvertTo-FirebaseSoakMarkdown -Evidence $evidence)
  if (-not $evidence.allPassed) {
    throw "Firebase soak evidence checks failed for $($RunRecord.matrixId): $jsonPath"
  }
  return [ordered]@{
    schemaVersion = 1
    directory = (Resolve-Path $OutputDirectory).Path
    json = (Resolve-Path $jsonPath).Path
    markdown = (Resolve-Path $markdownPath).Path
    logcat = (Resolve-Path $logcatPath).Path
    junit = (Resolve-Path $junitPath).Path
  }
}
