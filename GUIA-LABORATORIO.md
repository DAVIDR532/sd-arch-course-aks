# Guía del laboratorio · AKS Store Demo

Esta guía te lleva, comando por comando, desde un computador vacío hasta una tienda de microservicios
funcionando en Azure Kubernetes Service, actualizada sin downtime y validada de punto a punto.

**Duración:** ~90 minutos (de los cuales ~10 son esperando a que Azure cree el cluster).
**Costo:** unos pocos USD si destruyes todo al final ([Parte 12](#parte-12--limpieza-obligatorio)).

---

## Cómo usar esta guía

1. **Copia y pega los comandos en el orden en que aparecen.** No te saltes pasos: muchos comandos usan variables
   creadas en pasos anteriores.
2. **Elige el bloque de tu sistema operativo** cuando el paso tenga dos:

   | Etiqueta | Úsalo si trabajas en… |
   |---|---|
   | 🪟 **Windows (PowerShell 7)** | Windows, en una ventana de **PowerShell 7** (`pwsh`) |
   | 🐧 **macOS / Linux (Bash)** | Terminal de macOS, Linux, WSL o Git Bash |

   Si un bloque **no** tiene etiqueta, el comando es **igual en todos los sistemas** (`az`, `kubectl`, `terraform`, `git`).
3. **Trabaja siempre en la misma terminal** y **dentro de la carpeta del repositorio** (`sd-arch-course-aks`).
   Si cierras la terminal, ve a [Recuperar variables](#recuperar-variables-si-cerraste-la-terminal).
4. Al final de cada paso hay un **✅ Checkpoint**: no avances hasta que se cumpla.
5. Los bloques **📋 Salida esperada** son ejemplos reales; tus nombres, IPs y tiempos serán distintos.
6. Si algo falla, mira el bloque **🆘 Si falla** del paso o la tabla de
   [Troubleshooting del README](README.md#8-troubleshooting).

7. ¿Quieres entender **por qué** funciona cada paso? Debajo de cada punto hay un enlace **📘 Teoría del punto X.Y**
   con la explicación: teoría, qué pasó por dentro, conceptos core de Azure y dónde aprender más.
   Índice completo: [docs/teoria/](docs/teoria/README.md).

**Leyenda:** 🎯 qué vas a lograr · ▶️ ejecuta · 🔎 qué está pasando · 📋 salida esperada · ✅ checkpoint · 🆘 si falla · 📖 para profundizar · 📘 teoría del paso

---

## Índice

| Parte | Tema | Tiempo |
|---|---|---|
| [0](#parte-0--preparar-tu-equipo-una-sola-vez) | Preparar tu equipo (una sola vez) | 10-20 min |
| [1](#parte-1--conectarte-a-azure) | Conectarte a Azure | 5 min |
| [2](#parte-2--crear-la-infraestructura-con-terraform) | Crear la infraestructura con Terraform | 15 min |
| [3](#parte-3--conectar-kubectl-al-cluster) | Conectar kubectl al cluster | 5 min |
| [4](#parte-4--copiar-las-imágenes-al-registro-privado-acr) | Copiar las imágenes al registro privado (ACR) | 5 min |
| [5](#parte-5--desplegar-la-tienda-pieza-por-pieza) | Desplegar la tienda pieza por pieza | 20 min |
| [6](#parte-6--desplegar-el-backoffice) | Desplegar el backoffice | 5 min |
| [7](#parte-7--aplicar-network-policies) | Aplicar Network Policies | 5 min |
| [8](#parte-8--construir-tu-versión-personalizada-de-la-tienda) | Construir tu versión personalizada de la tienda | 5 min |
| [9](#parte-9--rolling-update-sin-downtime-y-rollback) | Rolling update sin downtime y rollback | 10 min |
| [10](#parte-10--validación-punto-a-punto) | Validación punto a punto | 3 min |
| [11](#parte-11--experimentos-opcionales) | Experimentos (opcionales) | 15 min |
| [12](#parte-12--limpieza-obligatorio) | Limpieza (**obligatorio**) | 10 min |

---

## Parte 0 · Preparar tu equipo (una sola vez)

> 📘 [Teoría de la Parte 0 (todos sus puntos)](docs/teoria/parte-00-preparar-equipo.md)

🎯 Tener las herramientas instaladas y el repositorio descargado.

### 0.1 Abrir la terminal correcta

> 📘 [Teoría del punto 0.1](docs/teoria/parte-00-preparar-equipo.md#01-abrir-la-terminal-correcta)

| Sistema | Cómo abrirla |
|---|---|
| 🪟 Windows | Menú Inicio → escribe **PowerShell 7** (ícono negro). Si no aparece, instálala en el paso 0.2 y vuelve aquí. **No uses** "Windows PowerShell" (ícono azul, versión 5.1) |
| 🍎 macOS | `Cmd + Espacio` → escribe **Terminal** → Enter |
| 🐧 Linux / WSL | Abre tu terminal (o Ubuntu en WSL) |

En Windows, verifica que estás en PowerShell 7:

```powershell
$PSVersionTable.PSVersion
```

📋 Debe mostrar `Major` igual a **7**.

### 0.2 Instalar las herramientas

> 📘 [Teoría del punto 0.2](docs/teoria/parte-00-preparar-equipo.md#02-instalar-las-herramientas)

🪟 **Windows (PowerShell 7)**: copia el bloque completo. Al terminar, **cierra y vuelve a abrir** la terminal.

```powershell
winget install --id Microsoft.PowerShell -e
winget install --id Microsoft.AzureCLI -e
winget install --id Hashicorp.Terraform -e
winget install --id Kubernetes.kubectl -e
winget install --id Git.Git -e
```

🍎 **macOS (Terminal)**: requiere [Homebrew](https://brew.sh). Al terminar, cierra y vuelve a abrir la terminal.

```bash
brew install azure-cli kubectl git
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

🐧 **Linux Ubuntu/Debian o WSL (Bash)**

```bash
# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
# kubectl
sudo az aks install-cli
# Terraform
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl git
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform
```

### 0.3 Verificar las herramientas

> 📘 [Teoría del punto 0.3](docs/teoria/parte-00-preparar-equipo.md#03-verificar-las-herramientas)

▶️ Igual en todos los sistemas:

```bash
az version --query '"azure-cli"' -o tsv
terraform version
kubectl version --client
git --version
```

📋 **Salida esperada** (los números de versión variarán):

```
2.x.x
Terraform v1.x.x
Client Version: v1.x.x
git version 2.x.x
```

✅ **Checkpoint:** los 4 comandos responden con una versión (Terraform ≥ 1.9). Si uno dice "no se reconoce" o
"command not found", reinstálalo y **reabre la terminal**.

### 0.4 Descargar el repositorio

> 📘 [Teoría del punto 0.4](docs/teoria/parte-00-preparar-equipo.md#04-descargar-el-repositorio)

▶️ Igual en todos los sistemas. Se descarga en tu carpeta personal:

```bash
cd ~
git clone https://github.com/DAVIDR532/sd-arch-course-aks.git
cd sd-arch-course-aks
```

🔎 Desde ahora **todos** los comandos se ejecutan dentro de `sd-arch-course-aks`. Compruébalo:

🪟 **Windows (PowerShell 7)**

```powershell
Get-Location; Get-ChildItem -Name
```

🐧 **macOS / Linux (Bash)**

```bash
pwd; ls
```

📋 **Salida esperada:** la ruta termina en `sd-arch-course-aks` y ves:

```
docs  GUIA-LABORATORIO.md  infra  k8s  README.md  scripts
```

### 0.5 Permitir la ejecución de los scripts

> 📘 [Teoría del punto 0.5](docs/teoria/parte-00-preparar-equipo.md#05-permitir-la-ejecución-de-los-scripts)

🪟 **Windows (PowerShell 7)**: permite ejecutar scripts locales (solo para tu usuario):

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
```

🐧 **macOS / Linux (Bash)**: da permiso de ejecución a los scripts:

```bash
chmod +x scripts/*.sh
```

✅ **Checkpoint de la Parte 0:** estás en la carpeta `sd-arch-course-aks` y las 4 herramientas responden.

---

## Parte 1 · Conectarte a Azure

> 📘 [Teoría de la Parte 1 (todos sus puntos)](docs/teoria/parte-01-conectarse-azure.md)

🎯 Iniciar sesión, elegir la suscripción del laboratorio y confirmar que tiene lo necesario.

### 1.1 Iniciar sesión

> 📘 [Teoría del punto 1.1](docs/teoria/parte-01-conectarse-azure.md#11-iniciar-sesión)

▶️ Igual en todos los sistemas:

```bash
az login
```

🔎 Se abre el navegador para autenticarte. Si la terminal muestra una lista de suscripciones y pregunta cuál usar,
escribe el **número** de la suscripción del laboratorio y presiona Enter.

🆘 **Si falla:**
- No se abre el navegador (por ejemplo, en WSL): usa `az login --use-device-code` y sigue las instrucciones.
- Error `AADSTS50078 ... multi-factor authentication has expired`: usa `az login --tenant <id-del-tenant>`.

### 1.2 Elegir la suscripción del laboratorio

> 📘 [Teoría del punto 1.2](docs/teoria/parte-01-conectarse-azure.md#12-elegir-la-suscripción-del-laboratorio)

▶️ Lista tus suscripciones:

```bash
az account list --query "[].{Nombre:name, Id:id, Actual:isDefault}" -o table
```

▶️ Selecciona la del laboratorio. Reemplaza el texto entre comillas por el **Nombre** o el **Id** que te indicó el profesor:

```bash
az account set --subscription "NOMBRE-O-ID-DE-TU-SUSCRIPCION"
```

▶️ Confirma:

```bash
az account show --query "{Suscripcion:name, Id:id, Usuario:user.name}" -o table
```

✅ **Checkpoint:** `Suscripcion` es la del laboratorio.

### 1.3 Registrar los proveedores de recursos

> 📘 [Teoría del punto 1.3](docs/teoria/parte-01-conectarse-azure.md#13-registrar-los-proveedores-de-recursos)

🔎 Una suscripción nueva no siempre tiene "activados" los servicios que vamos a usar. Esto los activa (si ya lo están, no pasa nada).

▶️ Igual en todos los sistemas:

```bash
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.OperationsManagement
```

▶️ Verifica (repite el comando hasta que todos digan `Registered`; puede tardar 1-2 minutos):

```bash
az provider list --query "[?namespace=='Microsoft.ContainerService' || namespace=='Microsoft.ContainerRegistry' || namespace=='Microsoft.OperationalInsights' || namespace=='Microsoft.OperationsManagement'].{Proveedor:namespace, Estado:registrationState}" -o table
```

📋 **Salida esperada:**

```
Proveedor                       Estado
------------------------------  ----------
Microsoft.ContainerRegistry     Registered
Microsoft.ContainerService      Registered
Microsoft.OperationalInsights   Registered
Microsoft.OperationsManagement  Registered
```

### 1.4 Verificar la cuota de máquinas virtuales

> 📘 [Teoría del punto 1.4](docs/teoria/parte-01-conectarse-azure.md#14-verificar-la-cuota-de-máquinas-virtuales)

🔎 El cluster usa 2 máquinas virtuales de 2 vCPU (puede crecer hasta 4). Necesitas cuota disponible en la región **eastus2**.

🪟 **Windows (PowerShell 7)**

```powershell
az vm list-usage -l eastus2 -o table | Select-String "Total Regional vCPUs|Standard DSv5 Family|Standard DSv4 Family"
```

🐧 **macOS / Linux (Bash)**

```bash
az vm list-usage -l eastus2 -o table | grep -E "Total Regional vCPUs|Standard DSv5 Family|Standard DSv4 Family"
```

📋 **Salida esperada** (columnas: uso actual y límite):

```
Total Regional vCPUs              0               10
Standard DSv4 Family vCPUs        0               10
Standard DSv5 Family vCPUs        0               10
```

✅ **Checkpoint:** "Total Regional vCPUs" tiene al menos **8 libres** (límite − uso actual) y la familia **DSv5**
también. Si **DSv5 tiene límite 0** pero **DSv4** sí tiene cuota, no hay problema: en el paso 2.1 cambiarás el tamaño de VM.

---

## Parte 2 · Crear la infraestructura con Terraform

> 📘 [Teoría de la Parte 2 (todos sus puntos)](docs/teoria/parte-02-terraform.md)

🎯 Crear con código: Resource Group, Log Analytics, Azure Container Registry (ACR) y el cluster AKS con 2 node pools.

📖 Qué crea cada recurso y por qué: [docs/02-aks-para-arquitectos.md](docs/02-aks-para-arquitectos.md) e [infra/main.tf](infra/main.tf).

### 2.1 Crear el archivo de variables

> 📘 [Teoría del punto 2.1](docs/teoria/parte-02-terraform.md#21-crear-el-archivo-de-variables)

🔎 Terraform lee los valores (suscripción, región, tamaños) desde `infra/terraform.tfvars`. Lo creamos a partir de la
plantilla, poniendo automáticamente el Id de **tu** suscripción.

🪟 **Windows (PowerShell 7)**

```powershell
$SUB_ID = az account show --query id -o tsv
(Get-Content infra/terraform.tfvars.example) -replace '00000000-0000-0000-0000-000000000000', $SUB_ID | Set-Content infra/terraform.tfvars
Get-Content infra/terraform.tfvars
```

🐧 **macOS / Linux (Bash)**

```bash
SUB_ID=$(az account show --query id -o tsv)
sed "s/00000000-0000-0000-0000-000000000000/$SUB_ID/" infra/terraform.tfvars.example > infra/terraform.tfvars
cat infra/terraform.tfvars
```

📋 **Salida esperada:** la primera línea ya tiene tu Id (no ceros):

```
subscription_id = "1fb70a14-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
location        = "eastus2"
prefix          = "sdaks"
...
system_node_vm_size = "Standard_D2s_v5"
```

⚠️ **Solo si en el paso 1.4 la familia DSv5 tenía límite 0**, cambia el tamaño de VM a DSv4:

🪟 **Windows (PowerShell 7)**

```powershell
(Get-Content infra/terraform.tfvars) -replace 'Standard_D2s_v5', 'Standard_D2s_v4' | Set-Content infra/terraform.tfvars
Select-String vm_size infra/terraform.tfvars
```

🐧 **macOS / Linux (Bash)**

```bash
sed -i.bak 's/Standard_D2s_v5/Standard_D2s_v4/g' infra/terraform.tfvars && rm infra/terraform.tfvars.bak
grep vm_size infra/terraform.tfvars
```

### 2.2 Indicarle a Terraform con qué cuenta trabajar

> 📘 [Teoría del punto 2.2](docs/teoria/parte-02-terraform.md#22-indicarle-a-terraform-con-qué-cuenta-trabajar)

🔎 Terraform usa la sesión de `az login`. Estas dos líneas evitan los dos errores más comunes: usar el tenant equivocado
(si tienes varias organizaciones) o usar credenciales de un *service principal* guardadas en tu equipo.

🪟 **Windows (PowerShell 7)**

```powershell
$env:ARM_TENANT_ID = az account show --query tenantId -o tsv
Remove-Item env:ARM_CLIENT_ID, env:ARM_CLIENT_SECRET, env:ARM_SUBSCRIPTION_ID -ErrorAction SilentlyContinue
```

🐧 **macOS / Linux (Bash)**

```bash
export ARM_TENANT_ID=$(az account show --query tenantId -o tsv)
unset ARM_CLIENT_ID ARM_CLIENT_SECRET ARM_SUBSCRIPTION_ID
```

⚠️ Estas variables solo viven en **esta** terminal. Si la cierras, repite este paso antes de cualquier comando `terraform`.

### 2.3 Inicializar Terraform

> 📘 [Teoría del punto 2.3](docs/teoria/parte-02-terraform.md#23-inicializar-terraform)

▶️ Igual en todos los sistemas:

```bash
terraform -chdir=infra init
```

🔎 Descarga los *providers* (los plugins que saben hablar con Azure) en `infra/.terraform`. `-chdir=infra` le dice
a Terraform que trabaje sobre la carpeta `infra` sin que tengas que entrar a ella.

📋 **Salida esperada** (al final):

```
Terraform has been successfully initialized!
```

### 2.4 Revisar el plan

> 📘 [Teoría del punto 2.4](docs/teoria/parte-02-terraform.md#24-revisar-el-plan)

▶️ Igual en todos los sistemas:

```bash
terraform -chdir=infra plan -out tfplan
```

🔎 Terraform compara el código con lo que existe en Azure (nada todavía) y muestra qué va a **crear**, sin crear nada aún.
El plan se guarda en `infra/tfplan`.

📋 **Salida esperada** (al final):

```
  # azurerm_container_registry.this will be created
  # azurerm_kubernetes_cluster.this will be created
  # azurerm_kubernetes_cluster_node_pool.apps will be created
  # azurerm_log_analytics_workspace.this will be created
  # azurerm_resource_group.this will be created
  # azurerm_role_assignment.aks_acr_pull will be created
  # random_string.suffix will be created

Plan: 7 to add, 0 to change, 0 to destroy.
```

✅ **Checkpoint:** `Plan: 7 to add`.

🆘 **Si falla:**

| Error | Solución |
|---|---|
| `InvalidAuthenticationTokenTenant` o `AADSTS700016` | Repite el paso 2.2 |
| `subscription_id ... 00000000` | Repite el paso 2.1 (el archivo no tiene tu Id) |

### 2.5 Crear la infraestructura

> 📘 [Teoría del punto 2.5](docs/teoria/parte-02-terraform.md#25-crear-la-infraestructura)

▶️ Igual en todos los sistemas:

```bash
terraform -chdir=infra apply tfplan
```

⏳ **Tarda 7-10 minutos.** Mientras tanto, ve al [portal de Azure](https://portal.azure.com), busca **Resource groups**
y observa cómo aparece `rg-sdaks-demo-xxxxx` y luego los recursos dentro.

📋 **Salida esperada** (al final):

```
azurerm_kubernetes_cluster.this: Creation complete after 4m16s
azurerm_role_assignment.aks_acr_pull: Creation complete after 27s
azurerm_kubernetes_cluster_node_pool.apps: Creation complete after 1m49s

Apply complete! Resources: 7 added, 0 changed, 0 destroyed.
```

✅ **Checkpoint:** `Apply complete! Resources: 7 added`.

🆘 **Si falla:**

| Error | Solución |
|---|---|
| `QuotaExceeded` / `insufficient quota` | Vuelve al paso 1.4 y cambia el tamaño de VM (paso 2.1), luego repite 2.4 y 2.5 |
| `SkuNotAvailable` / `NotAvailableForSubscription` | Lo mismo: prueba `Standard_D2s_v4` o pide al profesor otro tamaño |
| `AuthorizationFailed` en `role_assignment` | Tu usuario necesita rol **Owner** en la suscripción: pídeselo al profesor |

### 2.6 Guardar los nombres generados en variables

> 📘 [Teoría del punto 2.6](docs/teoria/parte-02-terraform.md#26-guardar-los-nombres-generados-en-variables)

🔎 Los nombres llevan un sufijo aleatorio (por ejemplo `acrsdaksdemor5e01`). En lugar de copiarlos a mano,
los guardamos en variables que usaremos el resto del laboratorio.

🪟 **Windows (PowerShell 7)**

```powershell
$ACR_NAME = terraform -chdir=infra output -raw acr_name
$ACR      = terraform -chdir=infra output -raw acr_login_server
$RG       = terraform -chdir=infra output -raw resource_group_name
$AKS      = terraform -chdir=infra output -raw aks_name
"ACR=$ACR  RG=$RG  AKS=$AKS"
```

🐧 **macOS / Linux (Bash)**

```bash
ACR_NAME=$(terraform -chdir=infra output -raw acr_name)
ACR=$(terraform -chdir=infra output -raw acr_login_server)
RG=$(terraform -chdir=infra output -raw resource_group_name)
AKS=$(terraform -chdir=infra output -raw aks_name)
echo "ACR=$ACR  RG=$RG  AKS=$AKS"
```

📋 **Salida esperada:**

```
ACR=acrsdaksdemor5e01.azurecr.io  RG=rg-sdaks-demo-r5e01  AKS=aks-sdaks-demo-r5e01
```

### 2.7 Recorrido por el portal

> 📘 [Teoría del punto 2.7](docs/teoria/parte-02-terraform.md#27-recorrido-por-el-portal)

Abre el [portal de Azure](https://portal.azure.com) y busca:

| Dónde | Qué observar | Concepto |
|---|---|---|
| **Resource groups** | Hay **dos**: `rg-sdaks-demo-xxxxx` (el tuyo) y `rg-sdaks-demo-xxxxx-nodes` | El segundo lo crea y administra AKS: VMs, discos, red, Load Balancer |
| `rg-...-nodes` | Dos **Virtual machine scale sets**: `aks-system-...` y `aks-apps-...` | Cada node pool es un VM Scale Set |
| AKS → **Settings → Node pools** | `system` (Mode **System**) y `apps` (Mode **User**, autoscaling 1-3) | Separar add-ons del sistema de las aplicaciones |
| ACR → **Access control (IAM) → Role assignments** | La identidad `aks-sdaks-...-agentpool` con rol **AcrPull** | AKS descarga imágenes sin usuario/contraseña |

✅ **Checkpoint de la Parte 2:** existen los dos resource groups y las variables `ACR`, `RG` y `AKS` tienen valor.

---

## Parte 3 · Conectar kubectl al cluster

> 📘 [Teoría de la Parte 3 (todos sus puntos)](docs/teoria/parte-03-kubectl.md)

🎯 Configurar `kubectl` para que hable con tu cluster y explorar sus nodos.

### 3.1 Descargar las credenciales

> 📘 [Teoría del punto 3.1](docs/teoria/parte-03-kubectl.md#31-descargar-las-credenciales)

▶️ Igual en todos los sistemas (usa las variables del paso 2.6):

```bash
az aks get-credentials --resource-group $RG --name $AKS --overwrite-existing
```

🔎 Escribe la dirección del cluster y un certificado de acceso en tu archivo `~/.kube/config`. Desde ahora `kubectl` apunta a tu AKS.

📋 **Salida esperada:**

```
Merged "aks-sdaks-demo-r5e01" as current context in /home/usuario/.kube/config
```

### 3.2 Ver los nodos

> 📘 [Teoría del punto 3.2](docs/teoria/parte-03-kubectl.md#32-ver-los-nodos)

```bash
kubectl get nodes -L agentpool,workload
```

📋 **Salida esperada:**

```
NAME                             STATUS   ROLES    AGE   VERSION   AGENTPOOL   WORKLOAD
aks-apps-94602605-vmss000000     Ready    <none>   59s   v1.35.8   apps        apps
aks-system-22944399-vmss000000   Ready    <none>   3m    v1.35.8   system
```

🔎 Cada nodo es una VM del Scale Set. La columna `WORKLOAD=apps` es una etiqueta que pusimos en Terraform.

### 3.3 Ver por qué las apps no caen en el nodo "system"

> 📘 [Teoría del punto 3.3](docs/teoria/parte-03-kubectl.md#33-ver-por-qué-las-apps-no-caen-en-el-nodo-system)

🪟 **Windows (PowerShell 7)**

```powershell
kubectl describe nodes -l agentpool=system | Select-String "Taints"
```

🐧 **macOS / Linux (Bash)**

```bash
kubectl describe nodes -l agentpool=system | grep Taints
```

📋 **Salida esperada:**

```
Taints:             CriticalAddonsOnly=true:NoSchedule
```

🔎 Un **taint** es un "repelente": solo los pods que lo toleran (los del sistema) pueden ejecutarse en ese nodo.
Tus aplicaciones irán automáticamente al nodo `apps`.

### 3.4 Ver los componentes del sistema

> 📘 [Teoría del punto 3.4](docs/teoria/parte-03-kubectl.md#34-ver-los-componentes-del-sistema)

```bash
kubectl get pods -n kube-system
```

🔎 Son los add-ons que AKS instala: `coredns` (DNS interno), `metrics-server` (métricas para el autoescalado),
`cilium` (red y Network Policies), `ama-logs` (envía logs a Log Analytics), etc.

✅ **Checkpoint de la Parte 3:** `kubectl get nodes` muestra **2 nodos `Ready`**.

---

## Parte 4 · Copiar las imágenes al registro privado (ACR)

> 📘 [Teoría de la Parte 4 (todos sus puntos)](docs/teoria/parte-04-acr.md)

🎯 Que el cluster descargue las imágenes **solo de tu ACR**, no de registros públicos de internet.

### 4.1 Ejecutar la importación

> 📘 [Teoría del punto 4.1](docs/teoria/parte-04-acr.md#41-ejecutar-la-importación)

🪟 **Windows (PowerShell 7)**

```powershell
./scripts/01-import-images.ps1
```

🐧 **macOS / Linux (Bash)**

```bash
./scripts/01-import-images.sh
```

⏳ Tarda 3-5 minutos (10 imágenes).

🔎 Por cada imagen ejecuta `az acr import`, que copia la imagen **de registro a registro dentro de Azure**:
no necesitas Docker y la imagen no pasa por tu computador.
📖 [Cómo funciona el script por dentro](docs/03-scripts-explicados.md#01-import-images--llevar-las-imágenes-al-acr).

📋 **Salida esperada** (al final):

```
==> Importando ghcr.io/documentdb/documentdb/documentdb-local:pg17-0.112.0 -> acrsdaksdemor5e01.azurecr.io/documentdb/documentdb-local:pg17-0.112.0

==> Repositorios en el ACR
Result
--------------------------------
aks-store-demo/makeline-service
aks-store-demo/order-service
aks-store-demo/product-service
aks-store-demo/store-admin
aks-store-demo/store-front
aks-store-demo/virtual-customer
aks-store-demo/virtual-worker
documentdb/documentdb-local
library/busybox
library/rabbitmq
```

🆘 **Si ves `429 Too Many Requests`:** Docker Hub limita las descargas anónimas. El script reintenta solo
(espera 60 s, hasta 3 veces). Si al final falla, espera 5 minutos y vuelve a ejecutarlo: es seguro repetirlo.

> 💡 Este error es justamente la razón de tener un registro privado: si los nodos dependieran de Docker Hub,
> un nodo nuevo podría no arrancar tus apps en el peor momento.

### 4.2 Verificar

> 📘 [Teoría del punto 4.2](docs/teoria/parte-04-acr.md#42-verificar)

```bash
az acr repository list --name $ACR_NAME -o table
```

✅ **Checkpoint de la Parte 4:** la lista tiene **10 repositorios**.

---

## Parte 5 · Desplegar la tienda pieza por pieza

> 📘 [Teoría de la Parte 5 (todos sus puntos)](docs/teoria/parte-05-tienda.md)

🎯 Desplegar el núcleo de la tienda (el mismo escenario del tutorial de Microsoft) objeto por objeto, entendiendo cada uno.

🔎 **Cómo aplicamos los YAML:** los archivos de `k8s/` tienen el marcador `__ACR_LOGIN_SERVER__` donde va el nombre de
tu ACR. El script `k8s-apply` lo reemplaza y ejecuta `kubectl apply`.
📖 [Cómo funciona y cómo hacerlo sin el script](docs/03-scripts-explicados.md#k8s-apply--aplicar-yamls-con-el-acr-correcto).

### 5.1 Abrir una segunda terminal para observar (recomendado)

> 📘 [Teoría del punto 5.1](docs/teoria/parte-05-tienda.md#51-abrir-una-segunda-terminal-para-observar-recomendado)

Abre **otra** terminal (mismo tipo: PowerShell 7 o Bash), entra a la carpeta y deja corriendo:

```bash
cd ~/sd-arch-course-aks
kubectl get pods -n aks-store -w
```

🔎 `-w` (*watch*) muestra en vivo cada cambio de estado de los pods. Al principio dirá
`No resources found` (el namespace aún no existe). Déjala abierta; **sigue trabajando en la primera terminal**.
Para detenerla en cualquier momento: `Ctrl + C`.

### 5.2 Namespace, cuota y límites

> 📘 [Teoría del punto 5.2](docs/teoria/parte-05-tienda.md#52-namespace-cuota-y-límites)

🎯 Crear el espacio aislado `aks-store` con un tope de recursos.

🪟 **Windows (PowerShell 7)**

```powershell
./scripts/k8s-apply.ps1 k8s/00-namespace
```

🐧 **macOS / Linux (Bash)**

```bash
./scripts/k8s-apply.sh k8s/00-namespace
```

📋 **Salida esperada:**

```
--> kubectl apply namespace.yaml
namespace/aks-store created
--> kubectl apply limitrange.yaml
limitrange/aks-store-defaults created
--> kubectl apply resourcequota.yaml
resourcequota/aks-store-quota created
```

▶️ Mira la cuota (todavía en 0 porque no hay pods):

```bash
kubectl describe resourcequota aks-store-quota -n aks-store
```

📋 **Salida esperada:**

```
Resource                Used  Hard
--------                ----  ----
limits.cpu              0     10
limits.memory           0     10Gi
pods                    0     30
requests.cpu            0     2
requests.memory         0     4Gi
services.loadbalancers  0     2
```

🔎 **Namespace** = partición lógica del cluster. **ResourceQuota** = máximo que puede consumir todo el namespace.
**LimitRange** = valores por defecto para contenedores que no declaran recursos. Archivos: [k8s/00-namespace/](k8s/00-namespace).

### 5.3 RabbitMQ (mensajería)

> 📘 [Teoría del punto 5.3](docs/teoria/parte-05-tienda.md#53-rabbitmq-mensajería)

🎯 Desplegar la cola de mensajes donde se publican los pedidos.

🪟 **Windows (PowerShell 7)**

```powershell
./scripts/k8s-apply.ps1 k8s/01-rabbitmq
```

🐧 **macOS / Linux (Bash)**

```bash
./scripts/k8s-apply.sh k8s/01-rabbitmq
```

▶️ Espera a que esté listo (el comando termina solo cuando el pod está `Ready`):

```bash
kubectl rollout status statefulset/rabbitmq -n aks-store --timeout=300s
kubectl get statefulset,pods,svc -n aks-store
```

📋 **Salida esperada:**

```
partitioned roll out complete: 1 new pods have been updated...

NAME                        READY   AGE
statefulset.apps/rabbitmq   1/1     40s

NAME             READY   STATUS    RESTARTS   AGE
pod/rabbitmq-0   1/1     Running   0          40s

NAME               TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)              AGE
service/rabbitmq   ClusterIP   10.0.58.110   <none>        5672/TCP,15672/TCP   40s
```

🔎 Fíjate:
- El pod se llama **`rabbitmq-0`**, no un nombre aleatorio: los **StatefulSet** dan identidad estable (útil para bases de datos y colas).
- El **Service ClusterIP** da un nombre DNS interno fijo: los demás pods se conectan a `rabbitmq:5672`.
- El usuario y la contraseña vienen de un **Secret** ([secret.yaml](k8s/01-rabbitmq/secret.yaml)).

### 5.4 Product service y order service (APIs)

> 📘 [Teoría del punto 5.4](docs/teoria/parte-05-tienda.md#54-product-service-y-order-service-apis)

🎯 Desplegar el catálogo de productos y el servicio que recibe pedidos.

🪟 **Windows (PowerShell 7)**

```powershell
./scripts/k8s-apply.ps1 k8s/02-product-service
./scripts/k8s-apply.ps1 k8s/03-order-service
```

🐧 **macOS / Linux (Bash)**

```bash
./scripts/k8s-apply.sh k8s/02-product-service
./scripts/k8s-apply.sh k8s/03-order-service
```

👀 **Mira la segunda terminal:** los pods de `order-service` pasan por `Init:0/1` → `PodInitializing` → `Running`.
El *init container* espera a que RabbitMQ acepte conexiones antes de arrancar la app.

▶️ Espera a que estén listos:

```bash
kubectl rollout status deployment/product-service -n aks-store --timeout=300s
kubectl rollout status deployment/order-service -n aks-store --timeout=300s
kubectl get pods -n aks-store -o wide
```

📋 **Salida esperada:**

```
deployment "product-service" successfully rolled out
deployment "order-service" successfully rolled out

NAME                               READY   STATUS    RESTARTS   AGE   IP             NODE
order-service-f6c766c6b-4l5sg      1/1     Running   0          62s   10.244.1.184   aks-apps-94602605-vmss000000
order-service-f6c766c6b-wkrjw      1/1     Running   0          62s   10.244.1.187   aks-apps-94602605-vmss000000
product-service-5486db5bcd-4k5nr   1/1     Running   0          69s   10.244.1.183   aks-apps-94602605-vmss000000
product-service-5486db5bcd-gctsm   1/1     Running   0          69s   10.244.1.118   aks-apps-94602605-vmss000000
rabbitmq-0                         1/1     Running   0          71s   10.244.1.111   aks-apps-94602605-vmss000000
```

🔎 Fíjate:
- Hay **2 réplicas** de cada API (`replicas: 2` en el Deployment).
- Todos corren en el nodo **`aks-apps-...`**, nunca en `aks-system-...` (por el taint del paso 3.3).
- Las IPs de los pods (`10.244.x.x`) son del rango *overlay*: no consumen IPs de la red virtual.

▶️ Mira cómo el Service encuentra a los pods por sus etiquetas:

```bash
kubectl get endpoints product-service -n aks-store
```

📋 Muestra las 2 IPs de los pods de product-service: el Service balancea entre ellas.

### 5.5 Store front (la tienda web)

> 📘 [Teoría del punto 5.5](docs/teoria/parte-05-tienda.md#55-store-front-la-tienda-web)

🎯 Publicar la tienda en internet con una IP pública.

🪟 **Windows (PowerShell 7)**

```powershell
./scripts/k8s-apply.ps1 k8s/04-store-front
```

🐧 **macOS / Linux (Bash)**

```bash
./scripts/k8s-apply.sh k8s/04-store-front
```

▶️ Espera a que los pods estén listos:

```bash
kubectl rollout status deployment/store-front -n aks-store --timeout=300s
```

▶️ Espera la IP pública. Repite este comando cada 15 segundos hasta que `EXTERNAL-IP` muestre una IP (no `<pending>`):

```bash
kubectl get svc store-front -n aks-store
```

📋 **Salida esperada:**

```
NAME          TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)        AGE
store-front   LoadBalancer   10.0.110.188   20.161.209.142   80:32285/TCP   56s
```

▶️ Guarda la IP en una variable:

🪟 **Windows (PowerShell 7)**

```powershell
$IP = kubectl get svc store-front -n aks-store -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
"Tienda: http://$IP"
```

🐧 **macOS / Linux (Bash)**

```bash
IP=$(kubectl get svc store-front -n aks-store -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Tienda: http://$IP"
```

🔎 En AKS, un **Service tipo LoadBalancer** crea automáticamente una IP pública y una regla en el Azure Load Balancer.
Búscala en el portal: resource group `rg-...-nodes` → aparece un nuevo recurso **Public IP address**.

### 5.6 Probar la tienda

> 📘 [Teoría del punto 5.6](docs/teoria/parte-05-tienda.md#56-probar-la-tienda)

▶️ Abre la URL que mostró el paso anterior (`http://20.x.x.x`) en tu navegador y:

1. Agrega 2 o 3 productos al carrito (**Add to Cart**).
2. Entra a **Cart** y presiona **Checkout**.
3. Debe aparecer el mensaje **"Order submitted successfully"**.

▶️ Comprueba que el pedido llegó a la cola de RabbitMQ:

```bash
kubectl exec -n aks-store rabbitmq-0 -- rabbitmqctl list_queues name messages
```

📋 **Salida esperada:**

```
Timeout: 60.0 seconds ...
Listing queues for vhost / ...
name    messages
orders  1
```

🔎 Recorrido del pedido: navegador → IP pública → **store-front** (nginx) → `order-service:3000` (DNS interno) →
cola `orders` en **RabbitMQ**. Cada flecha es un Service de Kubernetes.

▶️ (Opcional) Abre la consola web de RabbitMQ. Este comando **se queda corriendo**:

```bash
kubectl port-forward -n aks-store svc/rabbitmq 15672:15672
```

Abre <http://localhost:15672> (usuario `username`, contraseña `password`) → pestaña **Queues**.
Cuando termines, vuelve a la terminal y presiona `Ctrl + C`.

✅ **Checkpoint de la Parte 5:** la tienda abre en el navegador, el pedido se envía y la cola `orders` tiene al menos 1 mensaje.

---

## Parte 6 · Desplegar el backoffice

> 📘 [Teoría del punto 6](docs/teoria/parte-06-backoffice.md)

🎯 Completar el flujo de negocio: un worker procesa los pedidos de la cola, los guarda en una base de datos y un
portal administrativo permite verlos. Además, dos simuladores generan tráfico.

🪟 **Windows (PowerShell 7)**

```powershell
./scripts/k8s-apply.ps1 k8s/05-backoffice
```

🐧 **macOS / Linux (Bash)**

```bash
./scripts/k8s-apply.sh k8s/05-backoffice
```

▶️ Espera a que todo esté listo (la base de datos tarda ~1 minuto):

```bash
kubectl rollout status statefulset/documentdb -n aks-store --timeout=400s
kubectl rollout status deployment/makeline-service -n aks-store --timeout=300s
kubectl rollout status deployment/store-admin -n aks-store --timeout=300s
kubectl get pods -n aks-store
```

📋 **Salida esperada:** 12 pods en `Running` y `1/1`:

```
NAME                                READY   STATUS    RESTARTS   AGE
documentdb-0                        1/1     Running   0          35s
makeline-service-7c45878cd8-xxt77   1/1     Running   0          34s
order-service-f6c766c6b-4l5sg       1/1     Running   0          2m16s
...
store-admin-9f9c76fc5-l7wnc         1/1     Running   0          32s
virtual-customer-68c84958f8-fj667   1/1     Running   0          29s
virtual-worker-6b758fdc56-h6npg     1/1     Running   0          28s
```

▶️ Obtén la IP del portal administrativo (repite si sale vacía; tarda ~1 minuto):

🪟 **Windows (PowerShell 7)**

```powershell
$ADMIN_IP = kubectl get svc store-admin -n aks-store -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
"Portal admin: http://$ADMIN_IP"
```

🐧 **macOS / Linux (Bash)**

```bash
ADMIN_IP=$(kubectl get svc store-admin -n aks-store -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Portal admin: http://$ADMIN_IP"
```

▶️ Abre esa URL: en **Orders** verás los pedidos pendientes (los tuyos y los del simulador).

▶️ Mira al simulador enviando pedidos (`Ctrl + C` para salir):

```bash
kubectl logs -n aks-store deploy/virtual-customer -f
```

📋 **Salida esperada:**

```
Order 1 sent at 409.73ms with status of 201 Created. {"customerId":"1544851940","items":[...]}
Order 2 sent at 36.61s with status of 201 Created. {"customerId":"1164600166","items":[...]}
```

▶️ La cola ahora se vacía, porque `makeline-service` la consume y guarda en la base de datos:

```bash
kubectl exec -n aks-store rabbitmq-0 -- rabbitmqctl list_queues name messages
```

📋 `orders  0`

✅ **Checkpoint de la Parte 6:** el portal admin muestra pedidos y la cola `orders` está en 0.

---

## Parte 7 · Aplicar Network Policies

> 📘 [Teoría de la Parte 7 (todos sus puntos)](docs/teoria/parte-07-network-policies.md)

🎯 Restringir qué pods pueden hablar con RabbitMQ, la base de datos y el catálogo (por defecto, **todos** pueden hablar con **todos**).

### 7.1 Probar ANTES de aplicar las políticas

> 📘 [Teoría del punto 7.1](docs/teoria/parte-07-network-policies.md#71-probar-antes-de-aplicar-las-políticas)

▶️ Un pod "intruso" intenta conectarse a RabbitMQ:

🪟 **Windows (PowerShell 7)**

```powershell
kubectl run intruso -n aks-store --rm -i --restart=Never --image="$ACR/library/busybox:1.37.0" -- nc -zv -w 3 rabbitmq 5672
```

🐧 **macOS / Linux (Bash)**

```bash
kubectl run intruso -n aks-store --rm -i --restart=Never --image="$ACR/library/busybox:1.37.0" -- nc -zv -w 3 rabbitmq 5672
```

📋 **Salida esperada:** la conexión **funciona**:

```
rabbitmq (10.0.58.110:5672) open
pod "intruso" deleted
```

### 7.2 Aplicar las políticas

> 📘 [Teoría del punto 7.2](docs/teoria/parte-07-network-policies.md#72-aplicar-las-políticas)

🪟 **Windows (PowerShell 7)**

```powershell
./scripts/k8s-apply.ps1 k8s/06-network-policies
```

🐧 **macOS / Linux (Bash)**

```bash
./scripts/k8s-apply.sh k8s/06-network-policies
```

```bash
kubectl get networkpolicy -n aks-store
```

📋 **Salida esperada:**

```
NAME                                 POD-SELECTOR          AGE
documentdb-allow-makeline            app=documentdb        5s
product-service-allow-frontends      app=product-service   5s
rabbitmq-allow-producers-consumers   app=rabbitmq          5s
```

### 7.3 Probar DESPUÉS de aplicar las políticas

> 📘 [Teoría del punto 7.3](docs/teoria/parte-07-network-policies.md#73-probar-después-de-aplicar-las-políticas)

▶️ Repite **exactamente** el comando del paso 7.1.

📋 **Salida esperada:** ahora la conexión **se bloquea**:

```
nc: rabbitmq (10.0.58.110:5672): Connection timed out
pod "intruso" deleted
```

🔎 La política [rabbitmq-allow-producers-consumers.yaml](k8s/06-network-policies/rabbitmq-allow-producers-consumers.yaml)
solo permite tráfico desde pods con la etiqueta `app=order-service` o `app=makeline-service`. El pod `intruso` no la
tiene, así que Cilium descarta sus paquetes. Las políticas filtran por **etiquetas**, no por IPs.

▶️ Comprueba que la tienda **sigue funcionando**: haz otro pedido en el navegador.

✅ **Checkpoint de la Parte 7:** el intruso recibe `Connection timed out` y la tienda sigue aceptando pedidos.

---

## Parte 8 · Construir tu versión personalizada de la tienda

> 📘 [Teoría de la Parte 8 (todos sus puntos)](docs/teoria/parte-08-build.md)

🎯 Cambiar el nombre y el color de la tienda y compilar una imagen nueva **en Azure** (ACR Tasks), sin Docker en tu equipo.

### 8.1 Compilar la imagen

> 📘 [Teoría del punto 8.1](docs/teoria/parte-08-build.md#81-compilar-la-imagen)

▶️ Cambia `TU-NOMBRE` por tu nombre (sin espacios ni tildes), por ejemplo `TAG` = `2.2.0-ana`:

🪟 **Windows (PowerShell 7)**

```powershell
$MI_TAG = "2.2.0-TU-NOMBRE"
./scripts/02-build-storefront.ps1 -StoreName "Tienda de TU-NOMBRE" -BrandColor "#0b3d91" -Tag $MI_TAG
```

🐧 **macOS / Linux (Bash)**

```bash
MI_TAG="2.2.0-TU-NOMBRE"
STORE_NAME="Tienda de TU-NOMBRE" BRAND_COLOR="#0b3d91" TAG="$MI_TAG" ./scripts/02-build-storefront.sh
```

⏳ Tarda 1-2 minutos.

🔎 El script:
1. Descarga el código fuente oficial de la tienda (versión `2.2.0`).
2. Cambia el título, agrega el nombre junto al logo y cambia el color de la barra.
3. Sube el código al ACR, que ejecuta el `Dockerfile` (compila Vue con Node y lo empaqueta con nginx) y guarda la imagen
   con tu tag.

📖 [Explicación paso a paso con diagrama](docs/03-scripts-explicados.md#02-build-storefront--construir-una-imagen-personalizada-en-azure).

📋 **Salida esperada** (al final):

```
==> Compilando la imagen en ACR Tasks -> acrsdaksdemor5e01.azurecr.io/aks-store-demo/store-front:2.2.0-ana
(compilando en Azure, ~1-2 min...)
Build: Succeeded

==> Tags disponibles de store-front
Result
-----------
2.2.0
2.2.0-ana
```

💡 Puedes probar otros colores: `#7a1fa2` (morado), `#c62828` (rojo), `#2e7d32` (verde).

✅ **Checkpoint de la Parte 8:** `Build: Succeeded` y tu tag aparece en la lista.

---

## Parte 9 · Rolling update sin downtime y rollback

> 📘 [Teoría de la Parte 9 (todos sus puntos)](docs/teoria/parte-09-rolling-update.md)

🎯 Publicar tu versión mientras la tienda recibe tráfico, comprobar que **ninguna petición falla** y luego volver atrás.

### 9.1 Preparar el medidor de disponibilidad (segunda terminal)

> 📘 [Teoría del punto 9.1](docs/teoria/parte-09-rolling-update.md#91-preparar-el-medidor-de-disponibilidad-segunda-terminal)

▶️ En la **segunda terminal**, detén el `watch` con `Ctrl + C` y pega el bloque de tu sistema. Consulta la versión de
la tienda 5 veces por segundo; **déjalo corriendo**.

🪟 **Windows (PowerShell 7)**

```powershell
$IP = kubectl get svc store-front -n aks-store -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
while ($true) { try { "{0}  {1}" -f (Get-Date -Format HH:mm:ss), (Invoke-RestMethod "http://$IP/health" -TimeoutSec 2).version } catch { "{0}  ERROR" -f (Get-Date -Format HH:mm:ss) }; Start-Sleep -Milliseconds 200 }
```

🐧 **macOS / Linux (Bash)**

```bash
IP=$(kubectl get svc store-front -n aks-store -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
while true; do echo "$(date +%H:%M:%S)  $(curl -s -m 2 http://$IP/health || echo ERROR)"; sleep 0.2; done
```

📋 Verás líneas repitiéndose con la versión actual:

```
10:41:02  2.2.0
10:41:02  2.2.0
```

### 9.2 Cambiar la imagen en el YAML

> 📘 [Teoría del punto 9.2](docs/teoria/parte-09-rolling-update.md#92-cambiar-la-imagen-en-el-yaml)

▶️ Vuelve a la **primera terminal**. Este comando cambia la línea `image:` de
[k8s/04-store-front/deployment.yaml](k8s/04-store-front/deployment.yaml) de `store-front:2.2.0` a tu tag:

🪟 **Windows (PowerShell 7)**

```powershell
(Get-Content k8s/04-store-front/deployment.yaml) -replace '^(\s*image: .*store-front:).*$', "`${1}$MI_TAG" | Set-Content k8s/04-store-front/deployment.yaml
Select-String "image:" k8s/04-store-front/deployment.yaml
```

🐧 **macOS / Linux (Bash)**

```bash
sed -i.bak -E "s#^([[:space:]]*image: .*store-front:).*#\1$MI_TAG#" k8s/04-store-front/deployment.yaml && rm k8s/04-store-front/deployment.yaml.bak
grep "image:" k8s/04-store-front/deployment.yaml
```

📋 **Salida esperada:**

```
          image: __ACR_LOGIN_SERVER__/aks-store-demo/store-front:2.2.0-ana
```

> También puedes hacer este cambio a mano: abre el archivo en tu editor, busca la línea `image:` y cambia el tag.

### 9.3 Aplicar el cambio (rolling update)

> 📘 [Teoría del punto 9.3](docs/teoria/parte-09-rolling-update.md#93-aplicar-el-cambio-rolling-update)

🪟 **Windows (PowerShell 7)**

```powershell
./scripts/k8s-apply.ps1 k8s/04-store-front/deployment.yaml
kubectl rollout status deployment/store-front -n aks-store
```

🐧 **macOS / Linux (Bash)**

```bash
./scripts/k8s-apply.sh k8s/04-store-front/deployment.yaml
kubectl rollout status deployment/store-front -n aks-store
```

📋 **Salida esperada:**

```
deployment.apps/store-front configured
Waiting for deployment "store-front" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "store-front" rollout to finish: 1 old replicas are pending termination...
deployment "store-front" successfully rolled out
```

👀 **Mira la segunda terminal:** la versión cambia de `2.2.0` a tu tag **sin ninguna línea `ERROR`**:

```
10:42:15  2.2.0
10:42:15  2.2.0-ana
10:42:16  2.2.0
10:42:16  2.2.0-ana
10:42:17  2.2.0-ana
```

🔎 Durante unos segundos conviven ambas versiones. ¿Por qué no hay errores?

| Pieza (en [deployment.yaml](k8s/04-store-front/deployment.yaml)) | Qué hace |
|---|---|
| `maxSurge: 1`, `maxUnavailable: 0` | Primero crea un pod nuevo; no elimina uno viejo hasta que el nuevo esté listo |
| `readinessProbe` | El pod nuevo no recibe tráfico hasta que responde `/health` |
| `preStop: sleep 10` | El pod viejo espera 10 s antes de apagarse, mientras el Load Balancer deja de enviarle tráfico |

> 📏 Medido al preparar este laboratorio: **sin** `preStop` falló 1 de 143 peticiones durante el cambio;
> **con** `preStop`, 0 de 516.

▶️ Recarga la tienda en el navegador (`Ctrl + F5`): verás tu nombre y tu color.

▶️ Mira los ReplicaSets: uno por versión. El viejo queda en 0 pero **no se borra**, para poder volver atrás:

```bash
kubectl get rs -n aks-store -l app=store-front
```

📋 **Salida esperada:**

```
NAME                     DESIRED   CURRENT   READY   AGE
store-front-796548567f   0         0         0       15m
store-front-7dd7c7cff5   2         2         2       1m
```

### 9.4 Rollback

> 📘 [Teoría del punto 9.4](docs/teoria/parte-09-rolling-update.md#94-rollback)

▶️ Mira el historial y vuelve a la versión anterior (sigue observando la segunda terminal):

```bash
kubectl rollout history deployment/store-front -n aks-store
kubectl rollout undo deployment/store-front -n aks-store
kubectl rollout status deployment/store-front -n aks-store
```

📋 **Salida esperada:**

```
deployment.apps/store-front rolled back
deployment "store-front" successfully rolled out
```

👀 La segunda terminal vuelve a mostrar `2.2.0`, de nuevo sin errores. La tienda vuelve a "Contoso Pet Store".

### 9.5 Volver a tu versión y dejar el repositorio consistente

> 📘 [Teoría del punto 9.5](docs/teoria/parte-09-rolling-update.md#95-volver-a-tu-versión-y-dejar-el-repositorio-consistente)

🔎 `rollout undo` cambió el **cluster**, pero el YAML todavía dice tu tag. La buena práctica es que el archivo
(el "estado deseado") coincida con lo que corre. Vuelve a aplicar el YAML para dejar tu versión publicada:

🪟 **Windows (PowerShell 7)**

```powershell
./scripts/k8s-apply.ps1 k8s/04-store-front/deployment.yaml
kubectl rollout status deployment/store-front -n aks-store
```

🐧 **macOS / Linux (Bash)**

```bash
./scripts/k8s-apply.sh k8s/04-store-front/deployment.yaml
kubectl rollout status deployment/store-front -n aks-store
```

▶️ En la segunda terminal, detén el medidor con `Ctrl + C`.

✅ **Checkpoint de la Parte 9:** la tienda muestra tu nombre y el medidor no mostró `ERROR` durante los cambios.

---

## Parte 10 · Validación punto a punto

> 📘 [Teoría del punto 10](docs/teoria/parte-10-validacion.md)

🎯 Comprobar automáticamente que toda la cadena funciona.

🪟 **Windows (PowerShell 7)**

```powershell
./scripts/04-validate.ps1
```

🐧 **macOS / Linux (Bash)**

```bash
./scripts/04-validate.sh
```

📋 **Salida esperada:**

```
[OK] Pods listos - todos Ready
[OK] Apps fuera del pool system - nodos usados: aks-apps-94602605-vmss000000
[OK] Todas las imágenes vienen del ACR - acrsdaksdemor5e01.azurecr.io
[OK] IP pública store-front - 20.161.209.142
[OK] GET /health (store-front) - version=2.2.0-ana
[OK] GET / (página web) - title='Tienda de ana'
[OK] GET /api/products - 10 productos (ej: Contoso Catnip's Friend)
[OK] POST /api/orders - HTTP 201
[OK] Cola "orders" en RabbitMQ - antes: [orders 0] después: [orders 0] (makeline-service consume la cola, puede quedar en 0)
[OK] IP pública store-admin - 20.94.24.219
[OK] store-admin -> makeline -> DocumentDB - 2 pedidos pendientes leídos de la base de datos
[OK] Pod no autorizado -> RabbitMQ bloqueado - BLOCKED
```

📖 Qué comprueba cada línea y su comando manual equivalente:
[docs/03-scripts-explicados.md](docs/03-scripts-explicados.md#04-validate--prueba-punto-a-punto).

✅ **Checkpoint de la Parte 10:** todas las líneas en `[OK]`. **¡Laboratorio completado!**
Si tienes tiempo, haz los experimentos; si no, ve directo a la [Parte 12](#parte-12--limpieza-obligatorio).

---

## Parte 11 · Experimentos (opcionales)

> 📘 [Teoría de la Parte 11 (todos sus puntos)](docs/teoria/parte-11-experimentos.md)

Cada experimento es independiente. Ten la segunda terminal con `kubectl get pods -n aks-store -w` para ver los efectos.

### 11.1 Auto-sanación: borrar pods

> 📘 [Teoría del punto 11.1](docs/teoria/parte-11-experimentos.md#111-auto-sanación-borrar-pods)

```bash
kubectl delete pod -n aks-store -l app=product-service
kubectl get pods -n aks-store -l app=product-service
```

🔎 En segundos aparecen 2 pods **nuevos** (con otro nombre): el ReplicaSet detecta que faltan réplicas y las recrea.
La tienda sigue funcionando.

### 11.2 Escalado manual

> 📘 [Teoría del punto 11.2](docs/teoria/parte-11-experimentos.md#112-escalado-manual)

```bash
kubectl scale deployment/order-service --replicas=4 -n aks-store
kubectl get pods -n aks-store -l app=order-service
kubectl get endpoints order-service -n aks-store
```

🔎 Ahora hay 4 pods y el Service balancea entre las 4 IPs. Vuelve a 2:

```bash
kubectl scale deployment/order-service --replicas=2 -n aks-store
```

### 11.3 La cuota en acción

> 📘 [Teoría del punto 11.3](docs/teoria/parte-11-experimentos.md#113-la-cuota-en-acción)

```bash
kubectl scale deployment/order-service --replicas=40 -n aks-store
kubectl get deployment order-service -n aks-store
kubectl get events -n aks-store --field-selector reason=FailedCreate
```

📋 El Deployment no llega a 40 (`READY` se queda en un número menor) y los eventos muestran:

```
Error creating: pods "order-service-..." is forbidden: exceeded quota: aks-store-quota, requested: ..., limited: ...
```

🔎 La **ResourceQuota** del namespace impide que una app consuma todo el cluster. Vuelve a 2:

```bash
kubectl scale deployment/order-service --replicas=2 -n aks-store
```

### 11.4 Autoescalado (HPA)

> 📘 [Teoría del punto 11.4](docs/teoria/parte-11-experimentos.md#114-autoescalado-hpa)

▶️ Mira el estado del autoescalador (`cpu: 2%/60%` significa: uso actual / objetivo):

```bash
kubectl get hpa store-front -n aks-store
```

▶️ Genera carga con 3 pods que piden la página sin parar:

🪟 **Windows (PowerShell 7)**

```powershell
1..3 | ForEach-Object { kubectl run "carga$_" -n aks-store --image="$ACR/library/busybox:1.37.0" --restart=Never -- sh -c "while true; do wget -q -O- http://store-front/ >/dev/null; done" }
```

🐧 **macOS / Linux (Bash)**

```bash
for n in 1 2 3; do kubectl run "carga$n" -n aks-store --image="$ACR/library/busybox:1.37.0" --restart=Never -- sh -c "while true; do wget -q -O- http://store-front/ >/dev/null; done"; done
```

▶️ Observa el HPA cada 20 segundos durante ~2 minutos (`Ctrl + C` para salir):

```bash
kubectl get hpa store-front -n aks-store -w
```

📋 **Salida esperada:**

```
NAME          REFERENCE                TARGETS        MINPODS   MAXPODS   REPLICAS
store-front   Deployment/store-front   cpu: 2%/60%    2         5         2
store-front   Deployment/store-front   cpu: 71%/60%   2         5         2
store-front   Deployment/store-front   cpu: 71%/60%   2         5         3
```

▶️ Detén la carga:

```bash
kubectl delete pod carga1 carga2 carga3 -n aks-store
```

🔎 Al superar el 60% de CPU el HPA agregó réplicas. Al quitar la carga reducirá a 2 tras **5 minutos**
(ventana de estabilización, que evita subir y bajar constantemente). Si ves `cpu: <unknown>`, espera 1 minuto:
los pods nuevos tardan en reportar métricas.

### 11.5 DNS interno (service discovery)

> 📘 [Teoría del punto 11.5](docs/teoria/parte-11-experimentos.md#115-dns-interno-service-discovery)

```bash
kubectl run dns -n aks-store --rm -i --restart=Never --image="$ACR/library/busybox:1.37.0" -- nslookup order-service
```

📋 Resuelve `order-service.aks-store.svc.cluster.local` a una IP `10.0.x.x`: la IP del Service, no la de un pod.

### 11.6 Diagnóstico: una imagen que no existe

> 📘 [Teoría del punto 11.6](docs/teoria/parte-11-experimentos.md#116-diagnóstico-una-imagen-que-no-existe)

```bash
kubectl run roto -n aks-store --image="$ACR/no/existe:1"
kubectl get pod roto -n aks-store
kubectl describe pod roto -n aks-store
```

📋 El estado es `ErrImagePull` / `ImagePullBackOff`. Al final de `describe`, la sección **Events** explica el motivo.
**Esta es la primera herramienta de diagnóstico en Kubernetes.** Limpia:

```bash
kubectl delete pod roto -n aks-store
```

### 11.7 Monitoreo con Container Insights

> 📘 [Teoría del punto 11.7](docs/teoria/parte-11-experimentos.md#117-monitoreo-con-container-insights)

Portal de Azure → tu cluster AKS → **Monitoring → Insights** → pestañas **Nodes**, **Controllers** y **Containers**.
Busca `store-front` y mira su CPU durante el experimento 11.4.

---

## Parte 12 · Limpieza (obligatorio)

> 📘 [Teoría de la Parte 12 (todos sus puntos)](docs/teoria/parte-12-limpieza.md)

🎯 Eliminar **todos** los recursos para no seguir pagando.

### 12.1 Borrar la aplicación

> 📘 [Teoría del punto 12.1](docs/teoria/parte-12-limpieza.md#121-borrar-la-aplicación)

▶️ Libera las IPs públicas y el Load Balancer de forma ordenada (~1-2 min):

```bash
kubectl delete namespace aks-store
```

### 12.2 Destruir la infraestructura

> 📘 [Teoría del punto 12.2](docs/teoria/parte-12-limpieza.md#122-destruir-la-infraestructura)

▶️ Si abriste una terminal nueva, repite primero el [paso 2.2](#22-indicarle-a-terraform-con-qué-cuenta-trabajar). Luego:

```bash
terraform -chdir=infra destroy
```

Terraform muestra la lista de recursos a eliminar y pregunta `Enter a value:`. Escribe **`yes`** y presiona Enter.

⏳ Tarda ~10 minutos.

📋 **Salida esperada:**

```
Destroy complete! Resources: 7 destroyed.
```

### 12.3 Verificar que no quedó nada

> 📘 [Teoría del punto 12.3](docs/teoria/parte-12-limpieza.md#123-verificar-que-no-quedó-nada)

🪟 **Windows (PowerShell 7)**

```powershell
az group list --query "[?starts_with(name, 'rg-sdaks')].name" -o tsv
```

🐧 **macOS / Linux (Bash)**

```bash
az group list --query "[?starts_with(name, 'rg-sdaks')].name" -o tsv
```

📋 **Salida esperada:** **nada** (ninguna línea). Si aparece algún grupo, espera unos minutos y repite: AKS borra el
grupo `-nodes` en segundo plano.

▶️ Elimina el contexto del cluster en tu `kubectl`:

```bash
kubectl config delete-context $AKS
```

▶️ Deja el YAML del store-front como estaba (opcional):

```bash
git checkout -- k8s/04-store-front/deployment.yaml
```

✅ **Checkpoint final:** no aparece ningún resource group `rg-sdaks-*`.

---

## Recuperar variables si cerraste la terminal

Abre una terminal nueva, entra a la carpeta del repositorio y pega el bloque de tu sistema:

🪟 **Windows (PowerShell 7)**

```powershell
cd ~/sd-arch-course-aks
$env:ARM_TENANT_ID = az account show --query tenantId -o tsv
Remove-Item env:ARM_CLIENT_ID, env:ARM_CLIENT_SECRET, env:ARM_SUBSCRIPTION_ID -ErrorAction SilentlyContinue
$ACR_NAME = terraform -chdir=infra output -raw acr_name
$ACR      = terraform -chdir=infra output -raw acr_login_server
$RG       = terraform -chdir=infra output -raw resource_group_name
$AKS      = terraform -chdir=infra output -raw aks_name
$IP       = kubectl get svc store-front -n aks-store -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
"ACR=$ACR  RG=$RG  AKS=$AKS  IP=$IP"
```

🐧 **macOS / Linux (Bash)**

```bash
cd ~/sd-arch-course-aks
export ARM_TENANT_ID=$(az account show --query tenantId -o tsv)
unset ARM_CLIENT_ID ARM_CLIENT_SECRET ARM_SUBSCRIPTION_ID
ACR_NAME=$(terraform -chdir=infra output -raw acr_name)
ACR=$(terraform -chdir=infra output -raw acr_login_server)
RG=$(terraform -chdir=infra output -raw resource_group_name)
AKS=$(terraform -chdir=infra output -raw aks_name)
IP=$(kubectl get svc store-front -n aks-store -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "ACR=$ACR  RG=$RG  AKS=$AKS  IP=$IP"
```

Si en la Parte 8 definiste un tag, vuelve a definirlo: 🪟 `$MI_TAG = "2.2.0-TU-NOMBRE"` · 🐧 `MI_TAG="2.2.0-TU-NOMBRE"`.
