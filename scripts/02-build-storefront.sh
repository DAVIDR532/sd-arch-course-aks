#!/usr/bin/env bash
# Construye una versión PERSONALIZADA del store-front con ACR Tasks (compila en Azure, sin Docker local).
#
#   ./scripts/02-build-storefront.sh
#   STORE_NAME="Mi Tienda" BRAND_COLOR="#7a1fa2" TAG="2.2.0-mitienda" ./scripts/02-build-storefront.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

STORE_NAME="${STORE_NAME:-SmartData Pet Store}"
BRAND_COLOR="${BRAND_COLOR:-#0b3d91}"
TAG="${TAG:-2.2.0-smartdata}"
acr_name="${ACR_NAME:-$(tf_output acr_name)}"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

step "Clonando aks-store-demo (tag 2.2.0)"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch 2.2.0 \
  https://github.com/Azure-Samples/aks-store-demo.git "$work_dir/aks-store-demo"
store_front="$work_dir/aks-store-demo/src/store-front"

# Un tag de Git se puede mover; verificamos el commit exacto para construir siempre el mismo código.
expected_commit="fca8fe76b1763e1375f739d345f38c102bb39b96"
actual_commit="$(git -C "$work_dir/aks-store-demo" rev-parse HEAD)"
if [ "$actual_commit" != "$expected_commit" ]; then
  echo "El tag 2.2.0 apunta a $actual_commit y se esperaba $expected_commit. Se detiene el build por seguridad." >&2
  exit 1
fi

# Reemplazo literal de texto (sin regex) que falla si no encuentra el texto original
replace_in_file() {
  local file="$1" find="$2" replace="$3" content
  content="$(cat "$file")"
  case "$content" in
    *"$find"*) ;;
    *) echo "No se encontró el texto a reemplazar en $file: $find" >&2; exit 1 ;;
  esac
  printf '%s\n' "${content//"$find"/$replace}" > "$file"
}

step "Personalizando: '$STORE_NAME' / color $BRAND_COLOR"
# 1) Título de la pestaña del navegador
replace_in_file "$store_front/index.html" '<title>Contoso Pet Store</title>' "<title>$STORE_NAME</title>"

# 2) Nombre de la tienda junto al logo + color corporativo de la barra
top_nav="$store_front/src/components/TopNav.vue"
replace_in_file "$top_nav" '<img src="/contoso-pet-store-logo.png" alt="Contoso Pet Store Logo" />' \
  "<img src=\"/contoso-pet-store-logo.png\" alt=\"$STORE_NAME Logo\" /><span class=\"brand-name\">$STORE_NAME</span>"
replace_in_file "$top_nav" 'background-color: #333;' "background-color: $BRAND_COLOR;"
replace_in_file "$top_nav" 'nav img {' \
  ".brand-name { color: #fff; font-size: 1.4rem; font-weight: bold; margin-left: 0.75rem; vertical-align: middle; }
nav img {"

step "Compilando la imagen en ACR Tasks -> $acr_name.azurecr.io/aks-store-demo/store-front:$TAG"
echo "(compilando en Azure, ~1-2 min...)"
status="$(az acr build \
  --registry "$acr_name" \
  --image "aks-store-demo/store-front:$TAG" \
  --build-arg "APP_VERSION=$TAG" \
  --no-logs --only-show-errors \
  --query status -o tsv \
  "$store_front" | tr -d '\r')" || status="error"
if [ "$status" != "Succeeded" ]; then
  echo "Falló az acr build (estado: $status). Revisa: az acr task list-runs -r $acr_name -o table" >&2
  exit 1
fi
echo "Build: $status"

step "Tags disponibles de store-front"
az acr repository show-tags --name "$acr_name" --repository aks-store-demo/store-front -o table

cat <<EOF

Siguiente paso: en k8s/04-store-front/deployment.yaml cambia la imagen a ':$TAG' y ejecuta:
  ./scripts/k8s-apply.sh k8s/04-store-front/deployment.yaml
  kubectl rollout status deployment/store-front -n aks-store
EOF
