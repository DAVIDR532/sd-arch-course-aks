<#
.SYNOPSIS
  Despliega la tienda completa en orden (atajo de los pasos manuales de la guía).

.PARAMETER Core
  Solo namespace + rabbitmq + product + order + store-front (escenario del tutorial).
#>
param(
    [switch]$Core
)
. "$PSScriptRoot/_common.ps1"

$folders = @('00-namespace', '01-rabbitmq', '02-product-service', '03-order-service', '04-store-front')
if (-not $Core) { $folders += @('05-backoffice', '06-network-policies') }

foreach ($folder in $folders) {
    Write-Step "Aplicando k8s/$folder"
    & "$PSScriptRoot/k8s-apply.ps1" (Join-Path $K8sDir $folder)
}

Write-Step "Esperando a que los workloads estén listos"
$workloads = @('statefulset/rabbitmq', 'deployment/product-service', 'deployment/order-service', 'deployment/store-front')
if (-not $Core) {
    $workloads += @('statefulset/documentdb', 'deployment/makeline-service', 'deployment/store-admin',
                    'deployment/virtual-customer', 'deployment/virtual-worker')
}
foreach ($w in $workloads) {
    kubectl rollout status $w -n $Namespace --timeout=600s
    if ($LASTEXITCODE -ne 0) { throw "$w no quedó listo. Revisa: kubectl describe $w -n $Namespace" }
}

kubectl get all -n $Namespace
