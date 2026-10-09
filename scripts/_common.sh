#!/usr/bin/env bash
# Funciones compartidas por los scripts Bash del demo (macOS / Linux / WSL / Git Bash).
# Compatible con bash 3.2 (macOS) y sed BSD/GNU. Sin dependencias extra (no requiere jq).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$REPO_ROOT/infra"
K8S_DIR="$REPO_ROOT/k8s"
NAMESPACE="aks-store"

# Lee un output de Terraform (tr -d '\r' por si az/terraform corren como .exe en Git Bash)
tf_output() {
  local value
  value="$(cd "$INFRA_DIR" && terraform output -raw "$1" 2>/dev/null | tr -d '\r')" || true
  if [ -z "$value" ]; then
    echo "No se pudo leer el output '$1' de Terraform. ¿Ya ejecutaste 'terraform apply' en infra/?" >&2
    exit 1
  fi
  printf '%s' "$value"
}

acr_login_server() {
  if [ -n "${ACR_LOGIN_SERVER:-}" ]; then printf '%s' "$ACR_LOGIN_SERVER"; else tf_output acr_login_server; fi
}

step() { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
