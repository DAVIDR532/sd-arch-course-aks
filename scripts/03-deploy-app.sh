#!/usr/bin/env bash
# Despliega la tienda completa en orden (atajo de los pasos manuales de la guía).
#
#   ./scripts/03-deploy-app.sh          # todo
#   ./scripts/03-deploy-app.sh --core   # solo namespace + rabbitmq + product + order + store-front
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

core=false
[ "${1:-}" = "--core" ] && core=true

folders=(00-namespace 01-rabbitmq 02-product-service 03-order-service 04-store-front)
workloads=(statefulset/rabbitmq deployment/product-service deployment/order-service deployment/store-front)
if [ "$core" = false ]; then
  folders+=(05-backoffice 06-network-policies)
  workloads+=(statefulset/documentdb deployment/makeline-service deployment/store-admin
              deployment/virtual-customer deployment/virtual-worker)
fi

for folder in "${folders[@]}"; do
  step "Aplicando k8s/$folder"
  "$SCRIPT_DIR/k8s-apply.sh" "$K8S_DIR/$folder"
done

step "Esperando a que los workloads estén listos"
for w in "${workloads[@]}"; do
  kubectl rollout status "$w" -n "$NAMESPACE" --timeout=600s
done

kubectl get all -n "$NAMESPACE"
