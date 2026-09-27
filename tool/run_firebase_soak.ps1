[CmdletBinding()]
param(
  [string]$ProjectId,
  [string]$DeviceModel,
  [string]$OsVersion,
  [ValidateRange(5, 2400)][int]$SoakSeconds = 300,
  [ValidateRange(2, 100)][int]$LoadCycles = 10,
  [ValidateRange(1, 45)][int]$TimeoutMinutes = 15,
  [ValidateRange(1, 5)][int]$RepeatCount = 1,
  [string]$ResultsBucket,
  [string]$ResultsDirectory,
  [switch]$BuildOnly,
  [switch]$SkipBuild,
  [switch]$SkipDeviceValidation
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$exampleRoot = Join-Path $repositoryRoot 'example'
$androidRoot = Join-Path $exampleRoot 'android'
$targetPath = Join-Path $exampleRoot 'integration_test/performance_soak_test.dart'
$appApk = Join-Path $exampleRoot 'build/app/outputs/apk/debug/app-debug.apk'
$testApk = Join-Path $exampleRoot 'build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk'
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

if ($BuildOnly -and $SkipBuild) {
  throw '-BuildOnly and -SkipBuild cannot be used together.'
}

if (-not $SkipBuild) {
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

foreach ($artifact in @($appApk, $testApk)) {
  if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
    throw "Expected Firebase Test Lab artifact was not produced: $artifact"
  }
  $item = Get-Item -LiteralPath $artifact
  $hash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
  Write-Host "$($item.FullName) ($($item.Length) bytes, SHA256 $hash)"
}

if ($BuildOnly) {
  Write-Host 'Firebase Test Lab artifacts are ready; upload was skipped.'
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
    "--client-details=matrixLabel=$runResultsDirectory"
  )
  if (-not [string]::IsNullOrWhiteSpace($ResultsBucket)) {
    $gcloudArguments += "--results-bucket=$ResultsBucket"
    $gcloudArguments += "--results-dir=$runResultsDirectory"
  }

  Write-Host "Starting physical Firebase Test Lab run $run/$RepeatCount`: $DeviceModel / Android $OsVersion"
  Invoke-CheckedCommand `
    -Executable $gcloud.Source `
    -Arguments $gcloudArguments `
    -FailureMessage "Firebase Test Lab soak run $run/$RepeatCount failed."
}
