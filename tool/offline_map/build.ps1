param(
  [Parameter(Mandatory=$true)][string]$Pbf,
  [Parameter(Mandatory=$true)][string]$BasemapsJar,
  [Parameter(Mandatory=$true)][string]$WorkDirectory
)
$ErrorActionPreference = 'Stop'
# Protomaps basemaps 42ffaaa4a85a41bfcb23e43cc0f5b492a5eca123; Planetiler 0.10.2; Java 21.
$expectedPbf = '6d9b7a214e7617df8473e311466e0a2517209d937c579f6a2134a64421cc838d'
if ((Get-FileHash -LiteralPath $Pbf -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedPbf) {
  throw 'Use the shared D4 snapshot taiwan-261111.osm.pbf (see README).'
}
New-Item -ItemType Directory -Path $WorkDirectory -Force | Out-Null
$jar = (Resolve-Path -LiteralPath $BasemapsJar).Path
$pbfPath = (Resolve-Path -LiteralPath $Pbf).Path
$source = Join-Path $PSScriptRoot 'TaipeiBasemap.java'
& javac -cp $jar -d $WorkDirectory $source
if ($LASTEXITCODE -ne 0) { throw 'javac failed' }
Push-Location $WorkDirectory
try {
  & java -Xmx4g -cp "$jar$([IO.Path]::PathSeparator)$WorkDirectory" TaipeiBasemap "--osm=$pbfPath" '--bounds=121.44,24.95,121.68,25.22' '--minzoom=12' '--maxzoom=15' '--archive-version=1.3' '--threads=4' '--nodemap-type=sortedtable' '--storage=mmap' '--force'
  if ($LASTEXITCODE -ne 0) { throw 'Planetiler failed' }
} finally { Pop-Location }
