# Funciones compartidas por los scripts del demo.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$RepoRoot = Split-Path $PSScriptRoot -Parent
$InfraDir = Join-Path $RepoRoot 'infra'
$K8sDir = Join-Path $RepoRoot 'k8s'
$Namespace = 'aks-store'

function Get-TfOutput([string]$Name) {
    $value = terraform "-chdir=$InfraDir" output -raw $Name
    if ($LASTEXITCODE -ne 0 -or -not $value) {
        throw "No se pudo leer el output '$Name' de Terraform. ¿Ya ejecutaste 'terraform apply' en infra/?"
    }
    return $value
}

function Get-AcrLoginServer {
    if ($env:ACR_LOGIN_SERVER) { return $env:ACR_LOGIN_SERVER }
    return Get-TfOutput 'acr_login_server'
}

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}
