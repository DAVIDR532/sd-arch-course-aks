<#
.SYNOPSIS
  Construye una versión PERSONALIZADA del store-front con ACR Tasks.

.DESCRIPTION
  1. Descarga el código fuente oficial (tag 2.2.0) de Azure-Samples/aks-store-demo.
  2. Aplica la personalización: nombre de la tienda y color de la barra superior.
  3. `az acr build` sube el código al ACR y la imagen se compila EN AZURE
     (no se necesita Docker local) -> <acr>/aks-store-demo/store-front:<Tag>
#>
param(
    [string]$StoreName = 'SmartData Pet Store',
    [string]$BrandColor = '#0b3d91',
    [string]$Tag = '2.2.0-smartdata',
    [string]$AcrName
)
. "$PSScriptRoot/_common.ps1"

if (-not $AcrName) { $AcrName = Get-TfOutput 'acr_name' }

$workDir = Join-Path ([IO.Path]::GetTempPath()) 'aks-store-demo-build'
if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }

Write-Step "Clonando aks-store-demo (tag 2.2.0)"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch 2.2.0 https://github.com/Azure-Samples/aks-store-demo.git $workDir
if ($LASTEXITCODE -ne 0) { throw 'No se pudo clonar el repositorio.' }

$storeFront = Join-Path $workDir 'src/store-front'

function Update-File([string]$Path, [string]$Find, [string]$Replace) {
    $content = [IO.File]::ReadAllText($Path)
    if (-not $content.Contains($Find)) { throw "No se encontró el texto a reemplazar en $Path : $Find" }
    [IO.File]::WriteAllText($Path, $content.Replace($Find, $Replace))
}

Write-Step "Personalizando: '$StoreName' / color $BrandColor"
# 1) Título de la pestaña del navegador
Update-File (Join-Path $storeFront 'index.html') '<title>Contoso Pet Store</title>' "<title>$StoreName</title>"

# 2) Nombre de la tienda junto al logo + color corporativo de la barra
$topNav = Join-Path $storeFront 'src/components/TopNav.vue'
Update-File $topNav '<img src="/contoso-pet-store-logo.png" alt="Contoso Pet Store Logo" />' `
    "<img src=`"/contoso-pet-store-logo.png`" alt=`"$StoreName Logo`" /><span class=`"brand-name`">$StoreName</span>"
Update-File $topNav 'background-color: #333;' "background-color: $BrandColor;"
Update-File $topNav 'nav img {' ".brand-name { color: #fff; font-size: 1.4rem; font-weight: bold; margin-left: 0.75rem; vertical-align: middle; }`n`nnav img {"

Write-Step "Compilando la imagen en ACR Tasks -> $AcrName.azurecr.io/aks-store-demo/store-front:$Tag"
# --no-logs: en consolas Windows (cp1252) el streaming de logs de az falla con
# UnicodeEncodeError aunque el build sea exitoso. Esperamos el resultado y
# validamos el estado del run. Logs: portal -> ACR -> Services -> Tasks -> Runs.
Write-Host "(compilando en Azure, ~1-2 min...)"
$run = az acr build `
    --registry $AcrName `
    --image "aks-store-demo/store-front:$Tag" `
    --build-arg "APP_VERSION=$Tag" `
    --file (Join-Path $storeFront 'Dockerfile') `
    --no-logs `
    $storeFront --only-show-errors -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $run.status -ne 'Succeeded') {
    throw "Falló az acr build (run $($run.runId), estado $($run.status)). Revisa: az acr task logs -r $AcrName --run-id $($run.runId)"
}
Write-Host "Run $($run.runId): $($run.status)" -ForegroundColor Green

Write-Step "Tags disponibles de store-front"
az acr repository show-tags --name $AcrName --repository aks-store-demo/store-front -o table

Write-Host ""
Write-Host "Siguiente paso: en k8s/04-store-front/deployment.yaml cambia la imagen a ':$Tag' y ejecuta:" -ForegroundColor Yellow
Write-Host "  ./scripts/k8s-apply.ps1 k8s/04-store-front/deployment.yaml" -ForegroundColor Yellow
Write-Host "  kubectl rollout status deployment/store-front -n aks-store" -ForegroundColor Yellow
