<#
.SYNOPSIS
  Validación punto a punto de la tienda desplegada en AKS.

  Internet -> Load Balancer -> store-front (nginx) -> product-service
                                                   -> order-service -> RabbitMQ
                                                      -> makeline-service -> DocumentDB
#>
. "$PSScriptRoot/_common.ps1"

$results = [System.Collections.Generic.List[object]]::new()
function Add-Result([string]$Check, [bool]$Ok, [string]$Detail) {
    $results.Add([pscustomobject]@{ Check = $Check; Result = $(if ($Ok) { 'OK' } else { 'FAIL' }); Detail = $Detail })
    $color = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1} - {2}" -f $(if ($Ok) { 'OK' } else { 'FAIL' }), $Check, $Detail) -ForegroundColor $color
}

function Get-LbIp([string]$Service) {
    for ($i = 0; $i -lt 30; $i++) {
        $ip = kubectl get svc $Service -n $Namespace -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
        if ($ip) { return $ip }
        Start-Sleep -Seconds 10
    }
    return $null
}

Write-Step "1. Nodos y pods"
kubectl get nodes -L agentpool,workload -o wide
kubectl get pods -n $Namespace -o wide
$notReady = kubectl get pods -n $Namespace -o json | ConvertFrom-Json |
    ForEach-Object items | Where-Object {
        $_.status.phase -ne 'Succeeded' -and
        ($_.status.containerStatuses | Where-Object { -not $_.ready })
    }
Add-Result 'Pods listos' (-not $notReady) $(if ($notReady) { ($notReady.metadata.name -join ', ') } else { 'todos Ready' })

$appNodes = kubectl get pods -n $Namespace -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | Sort-Object -Unique
$onSystem = $appNodes | Where-Object { $_ -match 'system' }
Add-Result 'Apps fuera del pool system' (-not $onSystem) ("nodos usados: " + ($appNodes -join ', '))

Write-Step "2. Imágenes servidas desde ACR"
$acr = Get-AcrLoginServer
$images = kubectl get pods -n $Namespace -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | Sort-Object -Unique
$foreign = $images | Where-Object { $_ -and -not $_.StartsWith($acr) }
Add-Result 'Todas las imágenes vienen del ACR' (-not $foreign) $(if ($foreign) { $foreign -join ', ' } else { $acr })

Write-Step "3. Store-front expuesto por el Load Balancer"
$ip = Get-LbIp 'store-front'
Add-Result 'IP pública store-front' ([bool]$ip) "$ip"
if (-not $ip) { $results | Format-Table -AutoSize; throw 'El servicio store-front no tiene IP pública.' }
$base = "http://$ip"

try {
    $health = Invoke-RestMethod "$base/health" -TimeoutSec 15
    Add-Result 'GET /health (store-front)' ($health.status -eq 'ok') "version=$($health.version)"
} catch { Add-Result 'GET /health (store-front)' $false $_.Exception.Message }

try {
    $html = Invoke-WebRequest $base -TimeoutSec 15
    $title = [regex]::Match($html.Content, '<title>(.*?)</title>').Groups[1].Value
    Add-Result 'GET / (página web)' ($html.StatusCode -eq 200) "title='$title'"
} catch { Add-Result 'GET / (página web)' $false $_.Exception.Message }

Write-Step "4. store-front -> product-service"
$products = $null
try {
    $products = Invoke-RestMethod "$base/api/products" -TimeoutSec 15
    Add-Result 'GET /api/products' ($products.Count -gt 0) "$($products.Count) productos (ej: $($products[0].name))"
} catch { Add-Result 'GET /api/products' $false $_.Exception.Message }

Write-Step "5. store-front -> order-service -> RabbitMQ"
$queueBefore = kubectl exec -n $Namespace rabbitmq-0 -c rabbitmq -- rabbitmqctl list_queues name messages --quiet 2>$null
$order = @{
    customerId = 'smartdata-validation'
    items      = @(@{ productId = $(if ($products) { $products[0].id } else { 1 }); quantity = 2; price = $(if ($products) { $products[0].price } else { 1 }) })
} | ConvertTo-Json -Depth 5
try {
    $resp = Invoke-WebRequest "$base/api/orders" -Method Post -Body $order -ContentType 'application/json' -TimeoutSec 15
    Add-Result 'POST /api/orders' ($resp.StatusCode -eq 201) "HTTP $($resp.StatusCode)"
} catch { Add-Result 'POST /api/orders' $false $_.Exception.Message }

Start-Sleep -Seconds 3
$queueAfter = kubectl exec -n $Namespace rabbitmq-0 -c rabbitmq -- rabbitmqctl list_queues name messages --quiet 2>$null
$hasQueue = ($queueAfter | Select-String -Pattern '^orders\s') -ne $null
$note = if (kubectl get deploy makeline-service -n $Namespace --ignore-not-found -o name) { ' (makeline-service consume la cola, puede quedar en 0)' } else { '' }
Add-Result 'Cola "orders" en RabbitMQ' $hasQueue ("antes: [" + (($queueBefore | Select-String '^orders') -join '') + "] después: [" + (($queueAfter | Select-String '^orders') -join '') + "]" + $note)

Write-Step "6. Backoffice (si está desplegado)"
$hasAdmin = kubectl get svc store-admin -n $Namespace --ignore-not-found -o name
if ($hasAdmin) {
    $adminIp = Get-LbIp 'store-admin'
    Add-Result 'IP pública store-admin' ([bool]$adminIp) "$adminIp"
    if ($adminIp) {
        try {
            $pending = Invoke-RestMethod "http://$adminIp/api/makeline/order/fetch" -TimeoutSec 20
            $count = @($pending).Count
            Add-Result 'store-admin -> makeline -> DocumentDB' $true "$count pedidos pendientes leídos de la base de datos"
        } catch { Add-Result 'store-admin -> makeline -> DocumentDB' $false $_.Exception.Message }
    }
} else {
    Write-Host "Backoffice no desplegado: se omite."
}

Write-Step "7. Network Policies (si están desplegadas)"
$hasNetpol = kubectl get networkpolicy rabbitmq-allow-producers-consumers -n $Namespace --ignore-not-found -o name
if ($hasNetpol) {
    # Un pod "intruso" (sin la etiqueta app=order-service) intenta llegar a RabbitMQ: debe ser bloqueado.
    $out = kubectl run netpol-test -n $Namespace --rm -i --restart=Never --quiet `
        --image "$acr/library/busybox:1.37.0" -- sh -c 'nc -zv -w 3 rabbitmq 5672 && echo CONNECTED || echo BLOCKED' 2>&1
    $blocked = ($out -join ' ') -match 'BLOCKED'
    Add-Result 'Pod no autorizado -> RabbitMQ bloqueado' $blocked (($out | Select-Object -Last 1) -join '')
} else {
    Write-Host "Network policies no desplegadas: se omite."
}

Write-Step "Resumen"
$results | Format-Table -AutoSize
Write-Host "Tienda: $base" -ForegroundColor Green
if ($results | Where-Object Result -eq 'FAIL') { exit 1 }
