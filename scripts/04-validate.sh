#!/usr/bin/env bash
# Validación punto a punto de la tienda desplegada en AKS.
#
#   Internet -> Load Balancer -> store-front (nginx) -> product-service
#                                                    -> order-service -> RabbitMQ
#                                                       -> makeline-service -> DocumentDB
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
set +e   # las verificaciones manejan sus propios errores

failures=0
summary=""
result() { # result <ok:true|false> <check> <detalle>
  local tag color
  if [ "$1" = true ]; then tag="OK"; color='\033[32m'; else tag="FAIL"; color='\033[31m'; failures=$((failures + 1)); fi
  printf "${color}[%s] %s - %s\033[0m\n" "$tag" "$2" "$3"
  summary="${summary}$(printf '%-5s %s' "$tag" "$2")
"
}

lb_ip() {
  local ip i
  for i in $(seq 1 30); do
    ip="$(kubectl get svc "$1" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)"
    [ -n "$ip" ] && { echo "$ip"; return; }
    sleep 10
  done
}

rabbit_orders() {
  kubectl exec -n "$NAMESPACE" rabbitmq-0 -c rabbitmq -- rabbitmqctl list_queues name messages --quiet 2>/dev/null \
    | tr -d '\r' | grep -E '^orders[[:space:]]' | tr '\t' ' '
}

step "1. Nodos y pods"
kubectl get nodes -L agentpool,workload -o wide
kubectl get pods -n "$NAMESPACE" -o wide
not_ready="$(kubectl get pods -n "$NAMESPACE" \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{" "}{.status.containerStatuses[*].ready}{"\n"}{end}' \
  | grep -v ' Succeeded' | grep 'false' | cut -d' ' -f1 | tr '\n' ' ')"
if [ -z "$not_ready" ]; then result true 'Pods listos' 'todos Ready'; else result false 'Pods listos' "$not_ready"; fi

app_nodes="$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | tr '\n' ' ')"
if echo "$app_nodes" | grep -q 'system'; then
  result false 'Apps fuera del pool system' "nodos usados: $app_nodes"
else
  result true 'Apps fuera del pool system' "nodos usados: $app_nodes"
fi

step "2. Imágenes servidas desde ACR"
acr="$(acr_login_server)"
foreign="$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' \
  | sort -u | grep -v "^$acr/" | tr '\n' ' ')"
if [ -z "$foreign" ]; then result true 'Todas las imágenes vienen del ACR' "$acr"; else result false 'Todas las imágenes vienen del ACR' "$foreign"; fi

step "3. Store-front expuesto por el Load Balancer"
ip="$(lb_ip store-front)"
if [ -z "$ip" ]; then result false 'IP pública store-front' 'sin IP'; printf '%s' "$summary"; exit 1; fi
result true 'IP pública store-front' "$ip"
base="http://$ip"

health="$(curl -s --max-time 15 "$base/health")"
version="$(echo "$health" | sed -nE 's/.*"version":"([^"]*)".*/\1/p')"
if echo "$health" | grep -q '"status":"ok"'; then result true 'GET /health (store-front)' "version=$version"; else result false 'GET /health (store-front)' "$health"; fi

title="$(curl -s --max-time 15 "$base/" | sed -nE 's/.*<title>(.*)<\/title>.*/\1/p')"
if [ -n "$title" ]; then result true 'GET / (página web)' "title='$title'"; else result false 'GET / (página web)' 'sin respuesta'; fi

step "4. store-front -> product-service"
products="$(curl -s --max-time 15 "$base/api/products")"
count="$(echo "$products" | grep -o '"id":' | wc -l | tr -d ' ')"
first_id="$(echo "$products" | grep -oE '"id":[0-9]+' | head -1 | cut -d: -f2)"
first_price="$(echo "$products" | grep -oE '"price":[0-9.]+' | head -1 | cut -d: -f2)"
first_name="$(echo "$products" | grep -oE '"name":"[^"]*"' | head -1 | cut -d'"' -f4)"
if [ "${count:-0}" -gt 0 ]; then result true 'GET /api/products' "$count productos (ej: $first_name)"; else result false 'GET /api/products' "$products"; fi

step "5. store-front -> order-service -> RabbitMQ"
queue_before="$(rabbit_orders)"
order="{\"customerId\":\"smartdata-validation\",\"items\":[{\"productId\":${first_id:-1},\"quantity\":2,\"price\":${first_price:-1}}]}"
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -X POST -H 'Content-Type: application/json' -d "$order" "$base/api/orders")"
if [ "$code" = "201" ]; then result true 'POST /api/orders' "HTTP $code"; else result false 'POST /api/orders' "HTTP $code"; fi
sleep 3
queue_after="$(rabbit_orders)"
note=""
kubectl get deploy makeline-service -n "$NAMESPACE" >/dev/null 2>&1 && note=" (makeline-service consume la cola, puede quedar en 0)"
if [ -n "$queue_after" ]; then
  result true 'Cola "orders" en RabbitMQ' "antes: [$queue_before] después: [$queue_after]$note"
else
  result false 'Cola "orders" en RabbitMQ' 'la cola no existe'
fi

step "6. Backoffice (si está desplegado)"
if kubectl get svc store-admin -n "$NAMESPACE" >/dev/null 2>&1; then
  admin_ip="$(lb_ip store-admin)"
  if [ -n "$admin_ip" ]; then
    result true 'IP pública store-admin' "$admin_ip"
    response="$(curl -s -w '\n%{http_code}' --max-time 20 "http://$admin_ip/api/makeline/order/fetch")"
    pending_code="$(echo "$response" | tail -1)"
    pending="$(echo "$response" | grep -o '"orderId"' | wc -l | tr -d ' ')"
    if [ "$pending_code" = "200" ]; then
      result true 'store-admin -> makeline -> DocumentDB' "$pending pedidos pendientes leídos de la base de datos"
    else
      result false 'store-admin -> makeline -> DocumentDB' "HTTP $pending_code"
    fi
  else
    result false 'IP pública store-admin' 'sin IP'
  fi
else
  echo "Backoffice no desplegado: se omite."
fi

step "7. Network Policies (si están desplegadas)"
if kubectl get networkpolicy rabbitmq-allow-producers-consumers -n "$NAMESPACE" >/dev/null 2>&1; then
  # Un pod "intruso" (sin la etiqueta app=order-service) intenta llegar a RabbitMQ: debe ser bloqueado.
  out="$(kubectl run netpol-test -n "$NAMESPACE" --rm -i --restart=Never --quiet \
    --image "$acr/library/busybox:1.37.0" -- sh -c 'nc -zv -w 3 rabbitmq 5672 && echo CONNECTED || echo BLOCKED' 2>&1)"
  if echo "$out" | grep -q 'BLOCKED'; then
    result true 'Pod no autorizado -> RabbitMQ bloqueado' 'BLOCKED'
  else
    result false 'Pod no autorizado -> RabbitMQ bloqueado' "$(echo "$out" | tail -1)"
  fi
else
  echo "Network policies no desplegadas: se omite."
fi

step "Resumen"
printf '%s' "$summary"
printf '\033[32mTienda: %s\033[0m\n' "$base"
[ "$failures" -eq 0 ]
