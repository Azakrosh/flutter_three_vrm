function Get-FirebaseTestMatrix {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$GcloudExecutable,
    [Parameter(Mandatory = $true)][string]$ProjectId,
    [Parameter(Mandatory = $true)][string]$MatrixId
  )

  $accessTokenOutput = @(& $GcloudExecutable auth print-access-token 2>$null)
  $tokenExitCode = $LASTEXITCODE
  $accessToken = $accessTokenOutput | Select-Object -First 1
  if ($tokenExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($accessToken)) {
    throw 'Unable to obtain an access token for the Firebase Testing API.'
  }
  $escapedProject = [Uri]::EscapeDataString($ProjectId)
  $escapedMatrix = [Uri]::EscapeDataString($MatrixId)
  $uri = "https://testing.googleapis.com/v1/projects/$escapedProject/testMatrices/$escapedMatrix"
  try {
    return Invoke-RestMethod `
      -Method Get `
      -Uri $uri `
      -Headers @{ Authorization = "Bearer $accessToken" }
  }
  catch {
    throw "Unable to read Firebase Test Lab matrix ${MatrixId}: $($_.Exception.Message)"
  }
}

function Test-FirebaseMatrixTerminalState {
  param([Parameter(Mandatory = $true)][string]$State)

  return $State -in @(
    'FINISHED',
    'ERROR',
    'UNSUPPORTED_ENVIRONMENT',
    'INCOMPATIBLE_ENVIRONMENT',
    'INCOMPATIBLE_ARCHITECTURE',
    'CANCELLED',
    'INVALID'
  )
}

function Resolve-FirebaseMatrixId {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][object[]]$Output)

  $lines = @($Output | ForEach-Object { $_.ToString().Trim() })
  $formattedIds = @(
    $lines | Where-Object { $_ -match '^matrix-[a-z0-9]+$' } | Select-Object -Unique
  )
  if ($formattedIds.Count -eq 1) {
    return $formattedIds[0]
  }
  $discoveredIds = @(
    @(
      foreach ($line in $lines) {
        foreach ($match in [regex]::Matches($line, '\bmatrix-[a-z0-9]+\b')) {
          $match.Value
        }
      }
    ) | Select-Object -Unique
  )
  if ($discoveredIds.Count -eq 1) {
    return $discoveredIds[0]
  }
  throw 'Firebase Test Lab output did not contain one unambiguous matrix ID.'
}

function ConvertTo-FirebaseRunRecord {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$Matrix,
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][int]$RunIndex,
    [Parameter(Mandatory = $true)][int]$RunCount,
    [Parameter(Mandatory = $true)][string]$RequestedDeviceModel,
    [Parameter(Mandatory = $true)][string]$RequestedOsVersion,
    [Parameter(Mandatory = $true)]$ArtifactManifest
  )

  if ([string]::IsNullOrWhiteSpace($Matrix.testMatrixId) -or
      [string]::IsNullOrWhiteSpace($Matrix.projectId) -or
      [string]::IsNullOrWhiteSpace($Matrix.state)) {
    throw 'Firebase Testing API returned an incomplete test matrix.'
  }
  $toolResults = $Matrix.resultStorage.toolResultsExecution
  $consoleUrl = $null
  if (-not [string]::IsNullOrWhiteSpace($toolResults.historyId) -and
      -not [string]::IsNullOrWhiteSpace($toolResults.executionId)) {
    $consoleUrl = 'https://console.firebase.google.com/project/' +
      "$($Matrix.projectId)/testlab/histories/$($toolResults.historyId)/matrices/$($toolResults.executionId)"
  }
  $executions = @(
    foreach ($execution in @($Matrix.testExecutions)) {
      [ordered]@{
        id = $execution.id
        state = $execution.state
        deviceModel = $execution.environment.androidDevice.androidModelId
        osVersion = $execution.environment.androidDevice.androidVersionId
        locale = $execution.environment.androidDevice.locale
        orientation = $execution.environment.androidDevice.orientation
      }
    }
  )
  return [ordered]@{
    schemaVersion = 1
    recordedAtUtc = [DateTime]::UtcNow.ToString('o')
    label = $Label
    runIndex = $RunIndex
    runCount = $RunCount
    projectId = $Matrix.projectId
    matrixId = $Matrix.testMatrixId
    state = $Matrix.state
    outcomeSummary = $Matrix.outcomeSummary
    invalidMatrixDetails = $Matrix.invalidMatrixDetails
    matrixErrors = @($Matrix.extendedInvalidMatrixDetails)
    matrixTimestamp = $Matrix.timestamp
    requestedDevice = [ordered]@{
      model = $RequestedDeviceModel
      osVersion = $RequestedOsVersion
      locale = 'en'
      orientation = 'portrait'
    }
    executions = $executions
    resultStorage = [ordered]@{
      gcsPath = $Matrix.resultStorage.googleCloudStorage.gcsPath
      historyId = $toolResults.historyId
      executionId = $toolResults.executionId
      consoleUrl = $consoleUrl
    }
    artifacts = [ordered]@{
      schemaVersion = $ArtifactManifest.schemaVersion
      createdAtUtc = $ArtifactManifest.createdAtUtc
      soakSeconds = $ArtifactManifest.soakSeconds
      loadCycles = $ArtifactManifest.loadCycles
      injectMemoryPressure = $ArtifactManifest.injectMemoryPressure
      target = $ArtifactManifest.target
      targetPlatform = $ArtifactManifest.targetPlatform
      appApk = $ArtifactManifest.appApk
      testApk = $ArtifactManifest.testApk
    }
  }
}

function Write-AtomicJson {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)]$Value
  )

  $parent = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  $temporaryPath = "$Path.tmp"
  $json = $Value | ConvertTo-Json -Depth 10
  [IO.File]::WriteAllText(
    $temporaryPath,
    "$json`n",
    [Text.UTF8Encoding]::new($false)
  )
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}
