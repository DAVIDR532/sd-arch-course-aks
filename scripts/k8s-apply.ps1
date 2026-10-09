<#
.SYNOPSIS
  Aplica (o borra) un YAML o una carpeta de YAMLs reemplazando __ACR_LOGIN_SERVER__.

.EXAMPLE
  ./scripts/k8s-apply.ps1 k8s/00-namespace
  ./scripts/k8s-apply.ps1 k8s/04-store-front/deployment.yaml
  ./scripts/k8s-apply.ps1 k8s/05-backoffice -Delete

.NOTES
  Equivalente en bash:
    sed "s|__ACR_LOGIN_SERVER__|$ACR|g" k8s/04-store-front/deployment.yaml | kubectl apply -f -
#>
param(
    [Parameter(Mandatory, Position = 0)][string]$Path,
    [switch]$Delete
)
. "$PSScriptRoot/_common.ps1"

$acr = Get-AcrLoginServer
$verb = if ($Delete) { 'delete' } else { 'apply' }

# Orden dentro de una carpeta: namespace/cuotas -> secrets/configmaps -> el resto
function Get-Priority($file) {
    switch -Regex ($file.Name) {
        '^namespace' { 0 }
        'quota|limitrange' { 1 }
        'secret' { 2 }
        'configmap' { 3 }
        default { 5 }
    }
}

$item = Get-Item $Path
$files = if ($item.PSIsContainer) {
    Get-ChildItem $item.FullName -Filter *.yaml | Sort-Object { Get-Priority $_ }, Name
} else { @($item) }
if ($Delete) { [array]::Reverse($files) }

foreach ($f in $files) {
    Write-Host "--> kubectl $verb $($f.Name)" -ForegroundColor DarkCyan
    $yaml = [IO.File]::ReadAllText($f.FullName).Replace('__ACR_LOGIN_SERVER__', $acr)
    if ($Delete) {
        $yaml | kubectl delete --ignore-not-found -f -
    } else {
        $yaml | kubectl apply -f -
    }
    if ($LASTEXITCODE -ne 0) { throw "kubectl $verb falló en $($f.FullName)" }
}
