#!/usr/bin/env bash
# Copia las imágenes públicas del demo (GHCR / Docker Hub) al ACR privado.
# `az acr import` copia de registro a registro DENTRO de Azure: no requiere Docker local.
#
#   ./scripts/01-import-images.sh [nombre-acr]
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

acr_name="${1:-$(tf_output acr_name)}"
version="2.2.0"

images=(
  "ghcr.io/azure-samples/aks-store-demo/store-front:$version|aks-store-demo/store-front:$version"
  "ghcr.io/azure-samples/aks-store-demo/product-service:$version|aks-store-demo/product-service:$version"
  "ghcr.io/azure-samples/aks-store-demo/order-service:$version|aks-store-demo/order-service:$version"
  "ghcr.io/azure-samples/aks-store-demo/makeline-service:$version|aks-store-demo/makeline-service:$version"
  "ghcr.io/azure-samples/aks-store-demo/store-admin:$version|aks-store-demo/store-admin:$version"
  "ghcr.io/azure-samples/aks-store-demo/virtual-customer:$version|aks-store-demo/virtual-customer:$version"
  "ghcr.io/azure-samples/aks-store-demo/virtual-worker:$version|aks-store-demo/virtual-worker:$version"
  "docker.io/library/rabbitmq:4.3.2-management-alpine|library/rabbitmq:4.3.2-management-alpine"
  "docker.io/library/busybox:1.37.0|library/busybox:1.37.0"
  "ghcr.io/documentdb/documentdb/documentdb-local:pg17-0.112.0|documentdb/documentdb-local:pg17-0.112.0"
)

acr_has_tag() {
  local repo="${1%%:*}" tag="${1#*:}"
  az acr repository show-tags --name "$acr_name" --repository "$repo" -o tsv 2>/dev/null | tr -d '\r' | grep -qx "$tag"
}

for img in "${images[@]}"; do
  source_img="${img%%|*}"
  target_img="${img#*|}"
  step "Importando $source_img -> $acr_name.azurecr.io/$target_img"
  done_ok=false
  for attempt in 1 2 3; do
    # Docker Hub limita descargas anónimas (HTTP 429). A veces az reporta error
    # pero el ACR completa la importación reintentando: verificamos el tag.
    if az acr import --name "$acr_name" --source "$source_img" --image "$target_img" --force --only-show-errors \
       || acr_has_tag "$target_img"; then
      done_ok=true
      break
    fi
    if [ "$attempt" -lt 3 ]; then
      echo "Reintentando en 60s (intento $attempt de 3)..."
      sleep 60
    fi
  done
  if [ "$done_ok" != true ]; then
    echo "Falló la importación de $source_img. Si es un 429 de Docker Hub, usa el mirror" \
         "public.ecr.aws/docker/library/<imagen> o importa con --username/--password." >&2
    exit 1
  fi
done

step "Repositorios en el ACR"
az acr repository list --name "$acr_name" -o table
