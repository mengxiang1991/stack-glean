param([string]$Studio = 'C:\Program Files\Huawei\DevEco Studio')
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $project
if (!(Test-Path -LiteralPath (Join-Path $project 'build-profile.json5'))) {
  Copy-Item -LiteralPath (Join-Path $project 'build-profile.example.json5') -Destination (Join-Path $project 'build-profile.json5')
}
$env:JAVA_HOME = Join-Path $Studio 'jbr'
$env:DEVECO_SDK_HOME = Join-Path $Studio 'sdk'
$env:HVIGOR_USER_HOME = Join-Path $project '.hvigor-user'
$env:NODE_PATH = Join-Path $project 'node_modules'
# Reuse the version-matched toolchain bundled with DevEco; no online pnpm bootstrap.
$moduleRoot = Join-Path $project 'node_modules\@ohos'
New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
foreach ($name in @('hvigor', 'hvigor-ohos-plugin')) {
  $link = Join-Path $moduleRoot $name
  if (!(Test-Path -LiteralPath $link)) {
    New-Item -ItemType Junction -Path $link -Target (Join-Path $Studio "tools\hvigor\$name") | Out-Null
  }
}
& (Join-Path $Studio 'tools\node\node.exe') (Join-Path $Studio 'tools\hvigor\hvigor\bin\hvigor.js') --mode module -p product=default -p module=entry@default assembleHap --no-daemon
exit $LASTEXITCODE
