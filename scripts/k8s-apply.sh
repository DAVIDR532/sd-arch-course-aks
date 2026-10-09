#!/usr/bin/env bash
# Aplica (o borra) un YAML o una carpeta de YAMLs reemplazando __ACR_LOGIN_SERVER__.
#
#   ./scripts/k8s-apply.sh k8s/00-namespace
#   ./scripts/k8s-apply.sh k8s/04-store-front/deployment.yaml
#   ./scripts/k8s-apply.sh k8s/05-backoffice --delete
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

if [ $# -lt 1 ]; then
  echo "Uso: $0 <archivo.yaml|carpeta> [--delete]" >&2
  exit 1
fi
target="$1"
verb="apply"
[ "${2:-}" = "--delete" ] && verb="delete"

acr="$(acr_login_server)"

# Orden dentro de una carpeta: namespace/cuotas -> secrets/configmaps -> el resto
priority() {
  case "$1" in
    namespace*) echo 0 ;;
    *quota*|*limitrange*) echo 1 ;;
    *secret*) echo 2 ;;
    *configmap*) echo 3 ;;
    *) echo 5 ;;
  esac
}

files=()
if [ -d "$target" ]; then
  sort_flags="-k1,1n -k2,2"
  [ "$verb" = "delete" ] && sort_flags="-k1,1nr -k2,2r"
  while IFS= read -r line; do
    files+=("$line")
  done < <(for f in "$target"/*.yaml; do printf '%s\t%s\n' "$(priority "$(basename "$f")")" "$f"; done \
           | sort -t "$(printf '\t')" $sort_flags | cut -f2)
elif [ -f "$target" ]; then
  files=("$target")
else
  echo "No existe: $target" >&2
  exit 1
fi

for f in "${files[@]}"; do
  printf '\033[2m--> kubectl %s %s\033[0m\n' "$verb" "$(basename "$f")"
  if [ "$verb" = "delete" ]; then
    sed "s|__ACR_LOGIN_SERVER__|$acr|g" "$f" | kubectl delete --ignore-not-found -f -
  else
    sed "s|__ACR_LOGIN_SERVER__|$acr|g" "$f" | kubectl apply -f -
  fi
done
