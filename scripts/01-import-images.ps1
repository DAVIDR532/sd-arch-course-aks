<#
.SYNOPSIS
  Copia las imágenes públicas del demo (GHCR / Docker Hub) al ACR privado.

.DESCRIPTION
  `az acr import` copia la imagen de registro a registro DENTRO de Azure:
  no necesita Docker local y no pasa por tu máquina.
  Así el cluster solo descarga imágenes del ACR (control, escaneo, sin
  dependencia de registros públicos ni de sus límites de descarga).
#>
param(
    [string]$AcrName
)
. "$PSScriptRoot/_common.ps1"

if (-not $AcrName) { $AcrName = Get-TfOutput 'acr_name' }

$version = '2.2.0'
$images = @(
    @{ Source = "ghcr.io/azure-samples/aks-store-demo/store-front:$version";      Target = "aks-store-demo/store-front:$version" }
    @{ Source = "ghcr.io/azure-samples/aks-store-demo/product-service:$version";  Target = "aks-store-demo/product-service:$version" }
    @{ Source = "ghcr.io/azure-samples/aks-store-demo/order-service:$version";    Target = "aks-store-demo/order-service:$version" }
    @{ Source = "ghcr.io/azure-samples/aks-store-demo/makeline-service:$version"; Target = "aks-store-demo/makeline-service:$version" }
    @{ Source = "ghcr.io/azure-samples/aks-store-demo/store-admin:$version";      Target = "aks-store-demo/store-admin:$version" }
    @{ Source = "ghcr.io/azure-samples/aks-store-demo/virtual-customer:$version"; Target = "aks-store-demo/virtual-customer:$version" }
    @{ Source = "ghcr.io/azure-samples/aks-store-demo/virtual-worker:$version";   Target = "aks-store-demo/virtual-worker:$version" }
    @{ Source = "docker.io/library/rabbitmq:4.3.2-management-alpine";             Target = "library/rabbitmq:4.3.2-management-alpine" }
    @{ Source = "docker.io/library/busybox:1.37.0";                               Target = "library/busybox:1.37.0" }
    @{ Source = "ghcr.io/documentdb/documentdb/documentdb-local:pg17-0.112.0";    Target = "documentdb/documentdb-local:pg17-0.112.0" }
)

function Test-AcrTag([string]$Target) {
    $repo, $tag = $Target -split ':', 2
    $tags = az acr repository show-tags --name $AcrName --repository $repo -o tsv 2>$null
    return ($LASTEXITCODE -eq 0 -and ($tags -contains $tag))
}

foreach ($img in $images) {
    Write-Step "Importando $($img.Source) -> $AcrName.azurecr.io/$($img.Target)"
    $done = $false
    for ($attempt = 1; $attempt -le 3 -and -not $done; $attempt++) {
        az acr import --name $AcrName --source $img.Source --image $img.Target --force --only-show-errors
        # Docker Hub limita descargas anónimas (HTTP 429). A veces az reporta error
        # pero el ACR completa la importación reintentando: verificamos el tag.
        $done = ($LASTEXITCODE -eq 0) -or (Test-AcrTag $img.Target)
        if (-not $done -and $attempt -lt 3) {
            Write-Host "Reintentando en 60s (intento $attempt de 3)..." -ForegroundColor Yellow
            Start-Sleep -Seconds 60
        }
    }
    if (-not $done) {
        throw "Falló la importación de $($img.Source). Si es un 429 de Docker Hub, usa el mirror " +
              "public.ecr.aws/docker/library/<imagen> o importa con credenciales (--username/--password)."
    }
}

Write-Step "Repositorios en el ACR"
az acr repository list --name $AcrName -o table
