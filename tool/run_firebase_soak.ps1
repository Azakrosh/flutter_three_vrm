[CmdletBinding()]
param(
  [string]$ProjectId,
  [string]$DeviceModel,
  [string]$OsVersion,
  [ValidateRange(5, 2400)][int]$SoakSeconds = 300,
  [ValidateRange(2, 100)][int]$LoadCycles = 10,
  [ValidateRange(1, 45)][int]$TimeoutMinutes = 15,
  [ValidateRange(5, 120)][int]$MatrixWaitMinutes = 30,
  [ValidateRange(1, 5)][int]$RepeatCount = 1,
  [switch]$InjectMemoryPressure,
  [string]$ResultsBucket,
  [string]$ResultsDirectory,
  [string]$RunRecordsDirectory,
  [switch]$BuildOnly,
  [switch]$SkipBuild,
  [switch]$ValidateArtifactsOnly,
  [switch]$SkipDeviceValidation
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'firebase_test_lab.ps1')

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$exampleRoot = Join-Path $repositoryRoot 'example'
$androidRoot = Join-Path $exampleRoot 'android'
$targetPath = Join-Path $exampleRoot 'integration_test/performance_soak_test.dart'
$appApk = Join-Path $exampleRoot 'build/app/outputs/apk/debug/app-debug.apk'
$testApk = Join-Path $exampleRoot 'build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk'
$artifactManifest = Join-Path $exampleRoot 'build/app/outputs/apk/firebase-soak-manifest.json'
$flutter = Get-Command flutter -ErrorAction Stop

function Invoke-CheckedCommand {
  param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$FailureMessage
  )

  & $Executable @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw $FailureMessage
  }
}

function ConvertTo-Base64DartDefine {
  param([Parameter(Mandatory = $true)][string]$Value)

  return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

function Get-ApkMetadata {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Expected Firebase Test Lab artifact was not produced: $Path"
  }
  $item = Get-Item -LiteralPath $Path
  return [ordered]@{
    fileName = $item.Name
    length = $item.Length
    sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
  }
}

function Resolve-AndroidJavaHome {
  param([Parameter(Mandatory = $true)][string]$FlutterExecutable)

  if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    $configuredJava = Join-Path $env:JAVA_HOME 'bin/java.exe'
    if (Test-Path -LiteralPath $configuredJava -PathType Leaf) {
      return $env:JAVA_HOME
    }
  }

  $doctorOutput = & $FlutterExecutable doctor -v
  if ($LASTEXITCODE -ne 0) {
    throw 'Unable to locate the JDK because flutter doctor failed.'
  }
  foreach ($line in $doctorOutput) {
    if ($line -match 'Java binary at:\s*(.+?)[\\/]bin[\\/]java(?:\.exe)?\s*$') {
      $candidate = $Matches[1].Trim()
      if (Test-Path -LiteralPath (Join-Path $candidate 'bin/java.exe') -PathType Leaf) {
        return $candidate
      }
    }
  }
  throw 'Unable to locate the JDK used by Flutter. Configure JAVA_HOME before running this script.'
}

if ($BuildOnly -and ($SkipBuild -or $ValidateArtifactsOnly)) {
  throw '-BuildOnly cannot be combined with -SkipBuild or -ValidateArtifactsOnly.'
}
if ($ValidateArtifactsOnly) {
  $SkipBuild = $true
}

if (-not $SkipBuild) {
  if (Test-Path -LiteralPath $artifactManifest -PathType Leaf) {
    Remove-Item -LiteralPath $artifactManifest -Force
  }
  Write-Host "Building Firebase Test Lab soak: ${SoakSeconds}s / $LoadCycles cycles"
  Push-Location -LiteralPath $exampleRoot
  try {
    Invoke-CheckedCommand `
      -Executable $flutter.Source `
      -Arguments @(
        'build', 'apk', '--debug',
        '--target-platform=android-arm64'
      ) `
      -FailureMessage 'Flutter debug APK bootstrap failed.'

    $javaHomeBeforeBuild = $env:JAVA_HOME
    $env:JAVA_HOME = Resolve-AndroidJavaHome $flutter.Source
    Push-Location -LiteralPath $androidRoot
    try {
      $gradle = Join-Path $androidRoot 'gradlew.bat'
      Invoke-CheckedCommand `
        -Executable $gradle `
        -Arguments @('app:assembleAndroidTest') `
        -FailureMessage 'Android instrumentation APK build failed.'

      $dartDefines = @(
        ConvertTo-Base64DartDefine "VRM_SOAK_SECONDS=$SoakSeconds"
        ConvertTo-Base64DartDefine "VRM_SOAK_LOAD_CYCLES=$LoadCycles"
        ConvertTo-Base64DartDefine "VRM_SOAK_INJECT_MEMORY_PRESSURE=$($InjectMemoryPressure.IsPresent.ToString().ToLowerInvariant())"
      ) -join ','
      Invoke-CheckedCommand `
        -Executable $gradle `
        -Arguments @(
          'app:assembleDebug',
          "-Ptarget=$targetPath",
          '-Ptarget-platform=android-arm64',
          "-Pdart-defines=$dartDefines"
        ) `
        -FailureMessage 'Targeted performance soak APK build failed.'
    }
    finally {
      Pop-Location
      $env:JAVA_HOME = $javaHomeBeforeBuild
    }
  }
  finally {
    Pop-Location
  }
}
else {
  Write-Host "Reusing Firebase Test Lab soak artifacts: ${SoakSeconds}s / $LoadCycles cycles"
}

$appMetadata = Get-ApkMetadata -Path $appApk
$testMetadata = Get-ApkMetadata -Path $testApk
Write-Host "$appApk ($($appMetadata.length) bytes, SHA256 $($appMetadata.sha256))"
Write-Host "$testApk ($($testMetadata.length) bytes, SHA256 $($testMetadata.sha256))"

if ($SkipBuild) {
  if (-not (Test-Path -LiteralPath $artifactManifest -PathType Leaf)) {
    throw "Firebase soak artifact manifest is missing: $artifactManifest. Rebuild without -SkipBuild."
  }
  try {
    $manifest = Get-Content -LiteralPath $artifactManifest -Raw -Encoding UTF8 | ConvertFrom-Json
  }
  catch {
    throw "Firebase soak artifact manifest is invalid: $artifactManifest. Rebuild without -SkipBuild."
  }
  $expectedInjection = $InjectMemoryPressure.IsPresent
  if ($manifest.schemaVersion -ne 1 -or
      $manifest.soakSeconds -ne $SoakSeconds -or
      $manifest.loadCycles -ne $LoadCycles -or
      $manifest.injectMemoryPressure -ne $expectedInjection) {
    throw "Requested soak configuration does not match $artifactManifest. Rebuild without -SkipBuild or use the manifest values."
  }
  if ($manifest.appApk.length -ne $appMetadata.length -or
      $manifest.appApk.sha256 -ne $appMetadata.sha256 -or
      $manifest.testApk.length -ne $testMetadata.length -or
      $manifest.testApk.sha256 -ne $testMetadata.sha256) {
    throw "Firebase soak APK hashes do not match $artifactManifest. Rebuild without -SkipBuild."
  }
  Write-Host "Validated Firebase soak artifact manifest: $artifactManifest"
}
else {
  $manifest = [ordered]@{
    schemaVersion = 1
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    soakSeconds = $SoakSeconds
    loadCycles = $LoadCycles
    injectMemoryPressure = $InjectMemoryPressure.IsPresent
    target = 'integration_test/performance_soak_test.dart'
    targetPlatform = 'android-arm64'
    appApk = $appMetadata
    testApk = $testMetadata
  }
  $manifestJson = $manifest | ConvertTo-Json -Depth 4
  $temporaryManifest = "$artifactManifest.tmp"
  [IO.File]::WriteAllText(
    $temporaryManifest,
    "$manifestJson`n",
    [Text.UTF8Encoding]::new($false)
  )
  Move-Item -LiteralPath $temporaryManifest -Destination $artifactManifest -Force
  Write-Host "Wrote Firebase soak artifact manifest: $artifactManifest"
}

if ($BuildOnly) {
  Write-Host 'Firebase Test Lab artifacts are ready; upload was skipped.'
  exit 0
}
if ($ValidateArtifactsOnly) {
  Write-Host 'Firebase Test Lab artifacts and manifest are valid; upload was skipped.'
  exit 0
}

foreach ($required in @{
  ProjectId = $ProjectId
  DeviceModel = $DeviceModel
  OsVersion = $OsVersion
}.GetEnumerator()) {
  if ([string]::IsNullOrWhiteSpace($required.Value)) {
    throw "-$($required.Key) is required unless -BuildOnly is used."
  }
}

$gcloud = Get-Command gcloud -ErrorAction Stop
$activeAccount = & $gcloud.Source auth list '--filter=status:ACTIVE' '--format=value(account)' 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($activeAccount -join ''))) {
  throw 'No active gcloud account. Run gcloud auth login or activate a service account outside this script.'
}

if (-not $SkipDeviceValidation) {
  $modelJson = & $gcloud.Source firebase test android models describe $DeviceModel '--format=json'
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to read Firebase Test Lab device model: $DeviceModel"
  }
  $model = ($modelJson -join "`n") | ConvertFrom-Json
  if ($model.form -ne 'PHYSICAL') {
    throw "Device $DeviceModel is $($model.form), not PHYSICAL."
  }
  if ($model.supportedVersionIds -notcontains $OsVersion) {
    throw "Device $DeviceModel does not advertise Android version $OsVersion."
  }
  if ($model.supportedAbis -notcontains 'arm64-v8a') {
    throw "Device $DeviceModel does not advertise the required arm64-v8a ABI."
  }
}

if ([string]::IsNullOrWhiteSpace($ResultsDirectory)) {
  $timestamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
  $ResultsDirectory = "flutter-three-vrm-soak-$timestamp"
}
if ([string]::IsNullOrWhiteSpace($RunRecordsDirectory)) {
  $RunRecordsDirectory = Join-Path $repositoryRoot '.dart_tool/firebase-soak-runs'
}

for ($run = 1; $run -le $RepeatCount; $run += 1) {
  $runResultsDirectory = if ($RepeatCount -eq 1) {
    $ResultsDirectory
  }
  else {
    "$ResultsDirectory-run$run"
  }
  $gcloudArguments = @(
    'firebase', 'test', 'android', 'run',
    '--type=instrumentation',
    "--project=$ProjectId",
    "--app=$appApk",
    "--test=$testApk",
    "--device=model=$DeviceModel,version=$OsVersion,locale=en,orientation=portrait",
    "--timeout=${TimeoutMinutes}m",
    "--client-details=matrixLabel=$runResultsDirectory",
    '--async',
    '--quiet',
    '--format=value(testMatrixId)'
  )
  if (-not [string]::IsNullOrWhiteSpace($ResultsBucket)) {
    $gcloudArguments += "--results-bucket=$ResultsBucket"
    $gcloudArguments += "--results-dir=$runResultsDirectory"
  }

  Write-Host "Starting physical Firebase Test Lab run $run/$RepeatCount`: $DeviceModel / Android $OsVersion"
  $errorActionPreferenceBeforeCreate = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $matrixCreateOutput = @(& $gcloud.Source @gcloudArguments 2>&1)
    $matrixCreateExitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $errorActionPreferenceBeforeCreate
  }
  foreach ($line in $matrixCreateOutput) {
    Write-Host $line
  }
  try {
    $matrixId = Resolve-FirebaseMatrixId -Output $matrixCreateOutput
  }
  catch {
    if ($matrixCreateExitCode -ne 0) {
      throw "Firebase Test Lab soak run $run/$RepeatCount could not be created and no matrix ID was returned."
    }
    throw
  }
  Write-Host "Created Firebase Test Lab matrix: $matrixId"

  $safeRecordLabel = $runResultsDirectory -replace '[^a-zA-Z0-9._-]', '_'
  $runRecordPath = Join-Path $RunRecordsDirectory "$safeRecordLabel-$matrixId.json"
  $deadline = [DateTime]::UtcNow.AddMinutes($MatrixWaitMinutes)
  $previousState = $null
  do {
    $matrix = Get-FirebaseTestMatrix `
      -GcloudExecutable $gcloud.Source `
      -ProjectId $ProjectId `
      -MatrixId $matrixId
    $record = ConvertTo-FirebaseRunRecord `
      -Matrix $matrix `
      -Label $runResultsDirectory `
      -RunIndex $run `
      -RunCount $RepeatCount `
      -RequestedDeviceModel $DeviceModel `
      -RequestedOsVersion $OsVersion `
      -ArtifactManifest $manifest
    Write-AtomicJson -Path $runRecordPath -Value $record
    if ($matrix.state -ne $previousState) {
      Write-Host "Matrix $matrixId state: $($matrix.state)"
      $previousState = $matrix.state
    }
    if (Test-FirebaseMatrixTerminalState -State $matrix.state) {
      break
    }
    if ([DateTime]::UtcNow -ge $deadline) {
      throw "Timed out waiting $MatrixWaitMinutes minutes for Firebase Test Lab matrix $matrixId. Latest record: $runRecordPath"
    }
    Start-Sleep -Seconds 10
  } while ($true)

  Write-Host "Wrote Firebase Test Lab run record: $runRecordPath"
  if ($matrixCreateExitCode -ne 0) {
    throw "Firebase Test Lab matrix $matrixId was created but gcloud reported a validation error. State: $($matrix.state); details: $($matrix.invalidMatrixDetails)."
  }
  if ($matrix.state -ne 'FINISHED' -or $matrix.outcomeSummary -ne 'SUCCESS') {
    throw "Firebase Test Lab matrix $matrixId finished with state $($matrix.state) and outcome $($matrix.outcomeSummary)."
  }
  Write-Host "Firebase Test Lab matrix $matrixId passed."
}
