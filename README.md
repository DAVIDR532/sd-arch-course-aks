# sd-arch-course-aks

Demo de **Azure Kubernetes Service (AKS)** para el curso de Arquitectos Azure (SmartData · AZ-305).

Desplegamos con Terraform un **ACR + AKS** y, sobre él, la tienda de ejemplo de Microsoft
([AKS Store Demo](https://learn.microsoft.com/en-us/azure/aks/tutorial-kubernetes-deploy-application)),
pieza por pieza con YAMLs independientes. Luego la personalizamos, la actualizamos sin downtime
y la validamos de punto a punto.

---

## Contenido

1. [Objetivos de aprendizaje](#1-objetivos-de-aprendizaje)
2. [Agenda sugerida](#2-agenda-sugerida)
3. [Arquitectura de la solución](#3-arquitectura-de-la-solución)
4. [Recorrido de una petición](#4-recorrido-de-una-petición)
5. [Mapa de conceptos → archivos](#5-mapa-de-conceptos--archivos)
6. [Estructura del repositorio](#6-estructura-del-repositorio)
7. [Prerrequisitos](#7-prerrequisitos)
8. [Guía paso a paso](#8-guía-paso-a-paso)
9. [Experimentos para la clase](#9-experimentos-para-la-clase)
10. [Limpieza y costos](#10-limpieza-y-costos)
11. [Troubleshooting](#11-troubleshooting)
12. [Material de apoyo](#12-material-de-apoyo)

---

## 1. Objetivos de aprendizaje

Al terminar la sesión el estudiante podrá:

- **Explicar la arquitectura de Kubernetes**: control plane, nodos, pods y el modelo declarativo (estado deseado vs. estado real).
- **Diseñar un cluster AKS como arquitecto**: node pools system/user, red (Azure CNI Overlay + Cilium), identidades administradas, integración con ACR, observabilidad y tiers de SLA.
- **Desplegar infraestructura como código** con Terraform (ACR + AKS + Log Analytics + RBAC).
- **Desplegar una aplicación de microservicios** usando los objetos básicos: Namespace, Deployment, StatefulSet, Service, ConfigMap, Secret, HPA y NetworkPolicy.
- **Operar la aplicación**: rolling update sin downtime, rollback, autoescalado, auto-sanación y diagnóstico con `kubectl`.
- **Entender la automatización**: qué hace cada script por dentro (ACR Import, ACR Tasks, `kubectl apply`, smoke tests) y cómo hacerlo a mano.

> 📘 Material de lectura:
> [01 · Intro a Kubernetes](docs/01-intro-kubernetes.md) (fundamentos) ·
> [02 · AKS para arquitectos](docs/02-aks-para-arquitectos.md) (decisiones de diseño) ·
> [03 · Los scripts, explicados](docs/03-scripts-explicados.md) (qué hace cada script y su equivalente manual)

## 2. Agenda sugerida

| Bloque | Tiempo | Contenido | Paso |
|---|---|---|---|
| Teoría | 20 min | Mini intro a Kubernetes y AKS para arquitectos | [docs/](docs/) |
| Infraestructura | 15 min | Terraform: ACR + AKS. Recorrido por el portal mientras se crea | [Pasos 0-2](#paso-0--preparar-el-entorno) |
| Registro privado | 5 min | Importar imágenes al ACR | [Paso 3](#paso-3--llevar-las-imágenes-al-acr-privado) |
| Aplicación core | 20 min | Namespace → RabbitMQ → APIs → Frontend | [Paso 4](#paso-4--desplegar-la-tienda-core-pieza-por-pieza) |
| Backoffice y seguridad | 10 min | Base de datos, workers, Network Policies | [Paso 5](#paso-5--backoffice-y-network-policies) |
| Operación | 20 min | Imagen personalizada, rolling update, rollback | [Paso 6](#paso-6--personalización-rolling-update-y-rollback) |
| Validación | 5 min | Prueba punto a punto automatizada | [Paso 7](#paso-7--validación-punto-a-punto) |
| Laboratorio | 15 min | Auto-sanación, HPA, cuotas, DNS | [Sección 9](#9-experimentos-para-la-clase) |

> ⏱️ Para ahorrar tiempo en clase, crea la infraestructura (Paso 1) **antes** de la sesión: tarda ~7-10 minutos.

---

## 3. Arquitectura de la solución

```
                         Internet
                            │
             ┌──────────────┴───────────────┐
             ▼                              ▼
      IP pública :80                 IP pública :80          ← Azure Standard Load Balancer
             │                              │                  (lo crea AKS por cada Service LoadBalancer)
┌────────────┼───────────── AKS · namespace aks-store ────────┼──────────────────────────────┐
│            ▼                              ▼                                                 │
│   store-front (Vue/nginx)          store-admin (Vue/nginx)                                  │
│      │           │                   │            │                                         │
│      │           ▼                   ▼            ▼                                         │
│      │     product-service ◄─────────┘      makeline-service ───► documentdb (API MongoDB)  │
│      ▼         (Rust)                         (Go)    ▲                                     │
│   order-service ─────────► rabbitmq ──────────────────┘                                     │
│    (Node.js)     publica   cola "orders"   consume                                          │
│      ▲                                                ▲                                     │
│   virtual-customer (simula clientes)        virtual-worker (simula despachos)               │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
         ▲ pull de imágenes (rol AcrPull, Managed Identity)        │ logs y métricas
   Azure Container Registry                                  Log Analytics (Container Insights)
```

**Infraestructura (Terraform)**

| Recurso | Decisión de diseño | Por qué |
|---|---|---|
| AKS · pool `system` | 1 nodo, taint `CriticalAddonsOnly` | Aísla CoreDNS, metrics-server y agentes de las apps |
| AKS · pool `apps` | Autoscaler 1 → 3 nodos | Las apps corren aquí; crece con la demanda |
| Red | Azure CNI Overlay + Cilium | No consume IPs de la VNet; Network Policies con eBPF |
| Identidad | Managed Identity + rol `AcrPull` | Sin contraseñas ni service principals |
| ACR | Standard, sin usuario admin | Registro privado; auth por identidad |
| Observabilidad | Container Insights → Log Analytics | Logs y métricas gestionadas |
| Operación | Auto-upgrade `patch` + `NodeImage` | Parches automáticos de K8s y SO |

**Aplicación (por fases)**

| Fase | Componentes | Carpeta |
|---|---|---|
| Base | Namespace, ResourceQuota, LimitRange | [k8s/00-namespace](k8s/00-namespace) |
| Core (= tutorial de Microsoft) | rabbitmq, product-service, order-service, store-front + HPA | [k8s/01](k8s/01-rabbitmq) · [02](k8s/02-product-service) · [03](k8s/03-order-service) · [04](k8s/04-store-front) |
| Backoffice | documentdb, makeline-service, store-admin, simuladores | [k8s/05-backoffice](k8s/05-backoffice) |
| Seguridad | Network Policies | [k8s/06-network-policies](k8s/06-network-policies) |

## 4. Recorrido de una petición

Qué pasa cuando un cliente compra en la tienda (útil para explicar Services, DNS y patrones asíncronos):

| # | Desde → hacia | Mecanismo de Kubernetes / Azure |
|---|---|---|
| 1 | Navegador → IP pública | **Service `LoadBalancer`** → Azure Load Balancer → nodo |
| 2 | Load Balancer → pod `store-front` | kube-proxy/Cilium balancea entre las réplicas *Ready* (**readinessProbe**) |
| 3 | `store-front` → `product-service:3002` | nginx hace proxy por **nombre DNS** del **Service ClusterIP** (CoreDNS) |
| 4 | `store-front` → `order-service:3000` | Igual: Service ClusterIP; credenciales vía **ConfigMap + Secret** |
| 5 | `order-service` → `rabbitmq:5672` | Publica el pedido en la cola `orders` → **desacoplamiento asíncrono** |
| 6 | `makeline-service` ← `rabbitmq` | Consume la cola y guarda en `documentdb` (**StatefulSet**) |
| 7 | `store-admin` → `makeline-service` | El empleado ve y completa pedidos |
| 🔒 | Cualquier otro pod → `rabbitmq` / `documentdb` | **Bloqueado** por NetworkPolicy |

## 5. Mapa de conceptos → archivos

| Concepto | Dónde verlo |
|---|---|
| Infraestructura como código | [infra/main.tf](infra/main.tf) |
| Node pools system/user, taints | [infra/main.tf](infra/main.tf) · `default_node_pool` y `azurerm_kubernetes_cluster_node_pool` |
| Integración AKS ↔ ACR | [infra/main.tf](infra/main.tf) · `azurerm_role_assignment.aks_acr_pull` |
| Namespace, cuotas y límites | [k8s/00-namespace/](k8s/00-namespace) |
| StatefulSet vs Deployment | [01-rabbitmq/statefulset.yaml](k8s/01-rabbitmq/statefulset.yaml) vs [02-product-service/deployment.yaml](k8s/02-product-service/deployment.yaml) |
| Secret (`envFrom` y `secretKeyRef`) | [01-rabbitmq/secret.yaml](k8s/01-rabbitmq/secret.yaml) · [05-backoffice/makeline-deployment.yaml](k8s/05-backoffice/makeline-deployment.yaml) |
| ConfigMap | [03-order-service/configmap.yaml](k8s/03-order-service/configmap.yaml) |
| Init container | [03-order-service/deployment.yaml](k8s/03-order-service/deployment.yaml) |
| Probes (startup, readiness, liveness) | [03-order-service/deployment.yaml](k8s/03-order-service/deployment.yaml) |
| Service ClusterIP vs LoadBalancer | [02-product-service/service.yaml](k8s/02-product-service/service.yaml) vs [04-store-front/service.yaml](k8s/04-store-front/service.yaml) |
| Rolling update, preStop, topology spread | [04-store-front/deployment.yaml](k8s/04-store-front/deployment.yaml) |
| HorizontalPodAutoscaler | [04-store-front/hpa.yaml](k8s/04-store-front/hpa.yaml) |
| NetworkPolicy | [k8s/06-network-policies/](k8s/06-network-policies) |
| Importar imágenes al registro privado | [scripts/01-import-images.sh](scripts/01-import-images.sh) · [explicación](docs/03-scripts-explicados.md#01-import-images--llevar-las-imágenes-al-acr) |
| Build en la nube (ACR Tasks) | [scripts/02-build-storefront.sh](scripts/02-build-storefront.sh) · [explicación](docs/03-scripts-explicados.md#02-build-storefront--construir-una-imagen-personalizada-en-azure) |
| Plantillas + valores por ambiente | [scripts/k8s-apply.sh](scripts/k8s-apply.sh) · [explicación](docs/03-scripts-explicados.md#k8s-apply--aplicar-yamls-con-el-acr-correcto) |
| Smoke test punto a punto | [scripts/04-validate.sh](scripts/04-validate.sh) · [explicación](docs/03-scripts-explicados.md#04-validate--prueba-punto-a-punto) |

## 6. Estructura del repositorio

```
sd-arch-course-aks/                ◄── 📂 RAÍZ DEL REPO: todos los comandos de la guía se ejecutan aquí
├── infra/                         Terraform
│   ├── providers.tf               azurerm ~> 4.0, random
│   ├── variables.tf               región, prefijo, tamaños de VM, autoscaler, SKU del ACR
│   ├── main.tf                    RG, Log Analytics, ACR, AKS, pool apps, rol AcrPull
│   ├── outputs.tf                 nombres, login server, comando get-credentials
│   └── terraform.tfvars.example   plantilla de variables
├── k8s/                           Un YAML por objeto, una carpeta por componente
│   ├── 00-namespace/              namespace · resourcequota · limitrange
│   ├── 01-rabbitmq/               secret · statefulset · service
│   ├── 02-product-service/        deployment · service
│   ├── 03-order-service/          configmap · secret · deployment · service
│   ├── 04-store-front/            deployment · service (LoadBalancer) · hpa
│   ├── 05-backoffice/             documentdb · makeline · store-admin · simuladores
│   └── 06-network-policies/       rabbitmq · product-service · documentdb
├── scripts/                       Cada script en dos versiones equivalentes: .ps1 (PowerShell) y .sh (Bash)
│   ├── 01-import-images           copia imágenes públicas al ACR (az acr import)
│   ├── 02-build-storefront        build personalizado del front con ACR Tasks
│   ├── 03-deploy-app              atajo: aplica todas las carpetas en orden
│   ├── 04-validate                validación punto a punto
│   ├── k8s-apply                  aplica/borra un YAML o carpeta con el ACR correcto
│   └── _common                    funciones compartidas
└── docs/
    ├── 01-intro-kubernetes.md
    ├── 02-aks-para-arquitectos.md
    └── 03-scripts-explicados.md   ◄── qué hace cada script por dentro y cómo hacerlo a mano
```

> 🔧 Los YAML usan el marcador `__ACR_LOGIN_SERVER__` en las imágenes, porque el nombre del ACR es único por
> despliegue. El script `k8s-apply` lo reemplaza con el valor de `terraform output`
> ([ver explicación](docs/03-scripts-explicados.md#k8s-apply--aplicar-yamls-con-el-acr-correcto)).

## 7. Prerrequisitos

### 7.1 Herramientas

| Herramienta | Windows (PowerShell) | macOS | Linux (Ubuntu/Debian) / WSL |
|---|---|---|---|
| Azure CLI | `winget install Microsoft.AzureCLI` | `brew install azure-cli` | `curl -sL https://aka.ms/InstallAzureCLIDeb \| sudo bash` |
| Terraform ≥ 1.9 | `winget install Hashicorp.Terraform` | `brew tap hashicorp/tap && brew install hashicorp/tap/terraform` | [Guía oficial (apt)](https://developer.hashicorp.com/terraform/install#linux) |
| kubectl | `az aks install-cli` | `brew install kubectl` | `sudo az aks install-cli` |
| git | `winget install Git.Git` | `xcode-select --install` | `sudo apt install git` |
| Shell para los scripts | PowerShell 7: `winget install Microsoft.PowerShell` | Bash/zsh (incluido) | Bash (incluido) |

> 💡 **¿Qué script uso?** En Windows usa los `.ps1` con **PowerShell 7** (`pwsh`). En macOS, Linux o WSL usa los `.sh`.
> Ambas versiones hacen exactamente lo mismo. En Windows también puedes usar los `.sh` desde **Git Bash** o **WSL**.

Verifica la instalación (igual en todos los SO):

```bash
az version
terraform version
kubectl version --client
git --version
```

### 7.2 Azure

| Requisito | Verificación (igual en todos los SO) |
|---|---|
| Rol **Owner** (o Contributor + User Access Administrator) en la suscripción, porque Terraform crea un *role assignment* | `az role assignment list --assignee <tu-usuario> --all -o table` |
| Cuota de al menos 4 vCPU (ideal 8-10) para el tamaño de VM en la región | `az vm list-usage -l eastus2 -o table` |
| Resource providers registrados | `az provider register -n Microsoft.ContainerService` (y `Microsoft.ContainerRegistry`, `Microsoft.OperationalInsights`, `Microsoft.OperationsManagement`) |

---

## 8. Guía paso a paso

### Convenciones

- 📂 **Ubicación:** **todos** los comandos se ejecutan desde la **raíz del repositorio** (`sd-arch-course-aks/`).
  Terraform se invoca con `terraform -chdir=infra ...` para no tener que cambiar de carpeta. Si te pierdes:
  `cd` a la carpeta donde clonaste el repo y verifica con `ls` que ves `infra/`, `k8s/` y `scripts/`.
- 🪟 **PowerShell** = Windows · 🐧 **Bash** = macOS, Linux, WSL o Git Bash. Si un bloque no indica SO, el comando es
  **igual en todos** (`az`, `kubectl` y `terraform` se escriben igual).
- Cada paso indica 🎯 objetivo · ▶️ comandos · 👀 qué observar · ✅ resultado esperado · 📖 cómo funciona el script.

### Paso 0 · Preparar el entorno

🎯 Obtener el código y autenticarse en la suscripción correcta.

▶️ Clonar y entrar a la raíz del repo:

```bash
git clone https://github.com/DAVIDR532/sd-arch-course-aks.git
cd sd-arch-course-aks
```

🐧 **Solo macOS/Linux/WSL:** dar permiso de ejecución a los scripts (una sola vez):

```bash
chmod +x scripts/*.sh
```

▶️ Iniciar sesión en Azure:

```bash
az login
az account set --subscription "<nombre o id>"
az account show -o table
```

✅ La suscripción mostrada es la del laboratorio.

### Paso 1 · Infraestructura con Terraform

🎯 Crear ACR + AKS + Log Analytics como código, de forma repetible.

▶️ Crear el archivo de variables (y editar `subscription_id`; si hace falta, el tamaño de VM):

```powershell
# 🪟 PowerShell
Copy-Item infra/terraform.tfvars.example infra/terraform.tfvars
notepad infra/terraform.tfvars          # o: code infra/terraform.tfvars
```

```bash
# 🐧 Bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
nano infra/terraform.tfvars             # o: code infra/terraform.tfvars
```

▶️ Indicar a Terraform el tenant de la sesión de `az` (evita usar el token de otro tenant si tienes varios):

```powershell
# 🪟 PowerShell
$env:ARM_TENANT_ID = (az account show --query tenantId -o tsv)
```

```bash
# 🐧 Bash
export ARM_TENANT_ID=$(az account show --query tenantId -o tsv)
```

▶️ Desplegar (igual en todos los SO):

```bash
terraform -chdir=infra init
terraform -chdir=infra plan -out tfplan       # revisa: 7 recursos a crear
terraform -chdir=infra apply tfplan           # ~7-10 min
terraform -chdir=infra output
```

👀 En el portal:
- **Dos resource groups:** `rg-sdaks-demo-xxxxx` (el tuyo) y `rg-sdaks-demo-xxxxx-nodes` (lo administra AKS: VMSS, Load Balancer, IPs).
- **AKS → Node pools:** `system` (modo System) y `apps` (modo User, con autoscaling).
- **ACR → Access control (IAM):** la identidad `*-agentpool` tiene el rol **AcrPull**.

✅ `Apply complete! Resources: 7 added`.

### Paso 2 · Conectar kubectl al cluster

🎯 Configurar el acceso y explorar los nodos y los componentes del sistema.

▶️ Descargar las credenciales (genera `~/.kube/config`):

```powershell
# 🪟 PowerShell
Invoke-Expression (terraform -chdir=infra output -raw get_credentials_command)
```

```bash
# 🐧 Bash
eval "$(terraform -chdir=infra output -raw get_credentials_command)"
```

> Ambos ejecutan el comando que entrega Terraform: `az aks get-credentials --resource-group <rg> --name <aks> --overwrite-existing`.

▶️ Explorar (igual en todos los SO):

```bash
kubectl get nodes -L agentpool,workload
kubectl get pods -n kube-system
kubectl describe node <nombre-del-nodo-system>      # busca la línea "Taints"
```

👀 El nodo `system` tiene el taint `CriticalAddonsOnly=true:NoSchedule`; el nodo `apps` tiene la etiqueta `workload=apps`.

✅ Dos nodos en estado `Ready`.

### Paso 3 · Llevar las imágenes al ACR privado

🎯 Que el cluster dependa solo de **nuestro** registro, no de registros públicos.

```powershell
# 🪟 PowerShell
./scripts/01-import-images.ps1
```

```bash
# 🐧 Bash
./scripts/01-import-images.sh
```

📖 Por cada imagen ejecuta `az acr import --source <registro-publico>/<imagen> --image <repo>:<tag>`, una copia de
registro a registro **dentro de Azure** (sin Docker local). [Explicación completa →](docs/03-scripts-explicados.md#01-import-images--llevar-las-imágenes-al-acr)

> 💡 **Caso real:** al preparar este demo Docker Hub respondió `429 Too Many Requests` (límite de descargas
> anónimas). Si los nodos descargaran directo de Docker Hub, un escalado o un nodo nuevo podría quedar en
> `ImagePullBackOff` en plena producción. Por eso las imágenes viven en **tu** ACR.

✅ Verificación (igual en todos los SO):

```bash
az acr repository list --name $(terraform -chdir=infra output -raw acr_name) -o table
```

Muestra 10 repositorios (`aks-store-demo/*`, `library/rabbitmq`, `library/busybox`, `documentdb/*`).

### Paso 4 · Desplegar la tienda (core) pieza por pieza

🎯 Entender cada objeto aplicándolos uno a uno, en orden de dependencias.

📖 `k8s-apply` reemplaza `__ACR_LOGIN_SERVER__` por tu ACR y ejecuta `kubectl apply -f -`.
[Explicación completa y cómo hacerlo sin el script →](docs/03-scripts-explicados.md#k8s-apply--aplicar-yamls-con-el-acr-correcto)

> En los bloques siguientes, 🪟 usa `./scripts/k8s-apply.ps1 <ruta>` y 🐧 usa `./scripts/k8s-apply.sh <ruta>`.
> Los comandos `kubectl` de observación son iguales en todos los SO.

**4.1 Namespace, cuota y límites**

```powershell
# 🪟 PowerShell
./scripts/k8s-apply.ps1 k8s/00-namespace
```

```bash
# 🐧 Bash
./scripts/k8s-apply.sh k8s/00-namespace
```

```bash
kubectl describe resourcequota -n aks-store
```

**4.2 Mensajería (StatefulSet + Secret + Service)**

```powershell
# 🪟 PowerShell
./scripts/k8s-apply.ps1 k8s/01-rabbitmq
```

```bash
# 🐧 Bash
./scripts/k8s-apply.sh k8s/01-rabbitmq
```

```bash
kubectl get statefulset,pods,svc -n aks-store       # el pod se llama rabbitmq-0 (identidad estable)
```

**4.3 APIs (Deployments + ConfigMap + Secret + init container)**

```powershell
# 🪟 PowerShell
./scripts/k8s-apply.ps1 k8s/02-product-service
./scripts/k8s-apply.ps1 k8s/03-order-service
```

```bash
# 🐧 Bash
./scripts/k8s-apply.sh k8s/02-product-service
./scripts/k8s-apply.sh k8s/03-order-service
```

```bash
kubectl get pods -n aks-store -w                     # observa Init:0/1 → PodInitializing → Running  (Ctrl+C para salir)
```

**4.4 Frontend (Service LoadBalancer + HPA)**

```powershell
# 🪟 PowerShell
./scripts/k8s-apply.ps1 k8s/04-store-front
```

```bash
# 🐧 Bash
./scripts/k8s-apply.sh k8s/04-store-front
```

```bash
kubectl get svc store-front -n aks-store -w          # espera la EXTERNAL-IP (~1 min, Ctrl+C para salir)
```

👀 En el portal, dentro del RG `-nodes`, aparece una **IP pública nueva** asociada al Load Balancer `kubernetes`.

✅ Abre `http://<EXTERNAL-IP>` en el navegador, agrega productos al carrito y envía un pedido. Luego verifica que llegó a la cola:

```bash
kubectl exec -n aks-store rabbitmq-0 -- rabbitmqctl list_queues name messages      # orders  1
kubectl port-forward -n aks-store svc/rabbitmq 15672:15672                          # http://localhost:15672 (username/password)
```

> ⚡ **Atajo:** `./scripts/03-deploy-app.ps1 -Core` (🪟) o `./scripts/03-deploy-app.sh --core` (🐧) aplica las carpetas
> 00-04 y espera a que todo esté listo. [¿Cómo funciona? →](docs/03-scripts-explicados.md#03-deploy-app--desplegar-todo-en-orden)

### Paso 5 · Backoffice y Network Policies

🎯 Completar el flujo de negocio y aplicar segmentación de red entre pods.

```powershell
# 🪟 PowerShell
./scripts/k8s-apply.ps1 k8s/05-backoffice
./scripts/k8s-apply.ps1 k8s/06-network-policies
```

```bash
# 🐧 Bash
./scripts/k8s-apply.sh k8s/05-backoffice
./scripts/k8s-apply.sh k8s/06-network-policies
```

```bash
kubectl get svc store-admin -n aks-store -w          # portal admin en http://<EXTERNAL-IP>
kubectl get networkpolicy -n aks-store
kubectl logs -n aks-store deploy/virtual-customer -f # pedidos simulados (Ctrl+C)
```

👀 makeline-service consume la cola (`orders` queda en 0) y guarda los pedidos en DocumentDB. Los simuladores generan pedidos continuamente.

✅ El portal admin muestra pedidos pendientes.

### Paso 6 · Personalización, rolling update y rollback

🎯 Construir una versión propia de la app y publicarla **sin downtime**, con posibilidad de volver atrás.

**6.1 Construir la imagen en Azure (ACR Tasks, sin Docker local)**

```powershell
# 🪟 PowerShell
./scripts/02-build-storefront.ps1
# personalizado:
./scripts/02-build-storefront.ps1 -StoreName "Mi Tienda" -BrandColor "#7a1fa2" -Tag "2.2.0-mitienda"
```

```bash
# 🐧 Bash
./scripts/02-build-storefront.sh
# personalizado:
STORE_NAME="Mi Tienda" BRAND_COLOR="#7a1fa2" TAG="2.2.0-mitienda" ./scripts/02-build-storefront.sh
```

📖 El script clona el código oficial (tag `2.2.0`), cambia el título, el nombre y el color en los archivos Vue y ejecuta
`az acr build`. El código se sube a Azure y el Dockerfile multi-stage (Node → nginx) se compila allá.
[Explicación paso a paso →](docs/03-scripts-explicados.md#02-build-storefront--construir-una-imagen-personalizada-en-azure)

✅ `Build: Succeeded` y el tag `2.2.0-smartdata` aparece en la lista.

**6.2 Medir disponibilidad mientras se actualiza** (deja esto corriendo en **otra terminal**, también desde la raíz):

```powershell
# 🪟 PowerShell
while ($true) { try { (Invoke-RestMethod http://<IP>/health).version } catch { 'ERROR' }; Start-Sleep -Milliseconds 200 }
```

```bash
# 🐧 Bash
while true; do curl -s -m 2 http://<IP>/health || echo ERROR; echo; sleep 0.2; done
```

**6.3 Rolling update:** abre [k8s/04-store-front/deployment.yaml](k8s/04-store-front/deployment.yaml) en tu editor y
cambia la línea de la imagen `store-front:2.2.0` → `store-front:2.2.0-smartdata`. Guarda y aplica:

```powershell
# 🪟 PowerShell
./scripts/k8s-apply.ps1 k8s/04-store-front/deployment.yaml
```

```bash
# 🐧 Bash
./scripts/k8s-apply.sh k8s/04-store-front/deployment.yaml
```

```bash
kubectl rollout status deployment/store-front -n aks-store
kubectl get rs -n aks-store -l app=store-front       # ReplicaSet viejo (0) y nuevo (2)
```

👀 La terminal de medición cambia de `2.2.0` a `2.2.0-smartdata` **sin mostrar ERROR**. Tres piezas lo garantizan:

| Pieza | Efecto |
|---|---|
| `maxSurge: 1` / `maxUnavailable: 0` | Primero sube un pod nuevo; no baja uno viejo hasta que el nuevo está listo |
| `readinessProbe` | El pod nuevo no recibe tráfico hasta responder `/health` |
| `preStop: sleep 10` | El pod viejo espera 10 s antes de apagarse, mientras el Load Balancer deja de enviarle peticiones |

> 📏 **Medido en el demo:** sin `preStop` falló 1 de 143 peticiones durante el rollout; con `preStop`,
> 0 errores en 516 peticiones (rollout + rollback).

**6.4 Rollback en un comando** (igual en todos los SO):

```bash
kubectl rollout history deployment/store-front -n aks-store
kubectl rollout undo deployment/store-front -n aks-store
```

✅ La tienda muestra "SmartData Pet Store" tras el update y vuelve a "Contoso Pet Store" tras el rollback.

> ⚠️ `rollout undo` cambia el cluster pero **no** el YAML del repo. Para que el repo siga siendo la fuente de verdad,
> devuelve también el tag en el archivo. Esa es la idea detrás de GitOps.

### Paso 7 · Validación punto a punto

🎯 Comprobar automáticamente que toda la cadena funciona.

```powershell
# 🪟 PowerShell
./scripts/04-validate.ps1
```

```bash
# 🐧 Bash
./scripts/04-validate.sh
```

| # | Verificación |
|---|---|
| 1 | Todos los pods `Ready` y ninguno en el pool `system` |
| 2 | Todas las imágenes provienen del ACR |
| 3 | IP pública, `/health` y página web del store-front |
| 4 | Catálogo: front → product-service |
| 5 | Pedido real: front → order-service → RabbitMQ (HTTP 201) |
| 6 | Backoffice: store-admin → makeline → DocumentDB |
| 7 | NetworkPolicy: un pod no autorizado **no** llega a RabbitMQ |

📖 Cada verificación tiene su comando manual equivalente. [Ver tabla →](docs/03-scripts-explicados.md#04-validate--prueba-punto-a-punto)

✅ Todas las líneas en `[OK]`; el script termina con código 0.

---

## 9. Experimentos para la clase

Todos se ejecutan desde la raíz del repo y son **iguales en todos los SO**. Reemplaza `<acr>` por el valor de
`terraform -chdir=infra output -raw acr_login_server`.

| Experimento | Comando | Concepto |
|---|---|---|
| Auto-sanación | `kubectl delete pod -n aks-store -l app=product-service` y `kubectl get pods -n aks-store -w` | El ReplicaSet recrea los pods |
| Escalado manual | `kubectl scale deploy/order-service --replicas=4 -n aks-store` | Réplicas; el Service balancea entre ellas |
| Cuota | `kubectl scale deploy/order-service --replicas=40 -n aks-store` y `kubectl get events -n aks-store` | ResourceQuota rechaza pods (luego vuelve a 2) |
| Imagen inexistente | `kubectl run test --image=<acr>/no/existe:1 -n aks-store` y `kubectl describe pod test -n aks-store` | `ImagePullBackOff`; leer eventos |
| Logs | `kubectl logs -n aks-store deploy/order-service -f` | Observabilidad básica |
| DNS interno | `kubectl run -it dns --rm --image=<acr>/library/busybox:1.37.0 -n aks-store -- nslookup order-service` | Service discovery con CoreDNS |
| Network Policy | `kubectl run -it np --rm --image=<acr>/library/busybox:1.37.0 -n aks-store -- nc -zv -w 3 rabbitmq 5672` | Conexión bloqueada (timeout) |
| Container Insights | Portal → AKS → Monitoring → Insights | Monitoreo gestionado |

**Autoescalado con HPA**

▶️ Generar carga:

```powershell
# 🪟 PowerShell
$acr = terraform -chdir=infra output -raw acr_login_server
kubectl run load -n aks-store --image="$acr/library/busybox:1.37.0" --restart=Never -- `
  sh -c "while true; do wget -q -O- http://store-front/ >/dev/null; done"
```

```bash
# 🐧 Bash
ACR=$(terraform -chdir=infra output -raw acr_login_server)
kubectl run load -n aks-store --image="$ACR/library/busybox:1.37.0" --restart=Never -- \
  sh -c "while true; do wget -q -O- http://store-front/ >/dev/null; done"
```

▶️ Observar y limpiar (igual en todos los SO):

```bash
kubectl get hpa store-front -n aks-store -w
kubectl delete pod load -n aks-store
```

En el demo, con 3 pods de carga la CPU pasó de 2% a 71-80% y el HPA escaló de 2 a 3 réplicas en ~1 minuto.
Al quitar la carga reduce tras **5 minutos** (ventana de estabilización, que evita oscilaciones).
Si el HPA muestra `cpu: <unknown>`, los pods son muy recientes: metrics-server tarda ~1 min en reportar.

---

## 10. Limpieza y costos

Se paga por las VMs de los nodos, los discos, las IPs públicas, el Load Balancer, Log Analytics (por GB) y el ACR.
El control plane es gratis en el tier Free.

Desde la raíz del repo, igual en todos los SO:

```bash
kubectl delete namespace aks-store                     # opcional: borra solo la app (libera las IPs públicas)

az aks stop  -g <resource-group> -n <aks>              # pausar (no cobra VMs)
az aks start -g <resource-group> -n <aks>              # reanudar

terraform -chdir=infra destroy                         # borrar todo al terminar el curso
```

> Los nombres reales los obtienes con `terraform -chdir=infra output resource_group_name` y `terraform -chdir=infra output aks_name`.

---

## 11. Troubleshooting

Problemas reales que aparecieron al preparar el demo:

| Síntoma | Causa | Solución |
|---|---|---|
| `InvalidAuthenticationTokenTenant ... wrong issuer` en `terraform plan` | Sesión en varios tenants; Terraform usó el token de otro | 🪟 `$env:ARM_TENANT_ID = "<tenant>"` · 🐧 `export ARM_TENANT_ID=<tenant>` |
| `AADSTS700016: Application ... was not found in the directory` | Hay variables `ARM_CLIENT_ID/ARM_CLIENT_SECRET` de un service principal en tu entorno y Terraform las prefiere sobre `az login` | 🪟 `Remove-Item env:ARM_CLIENT_ID, env:ARM_CLIENT_SECRET, env:ARM_SUBSCRIPTION_ID` · 🐧 `unset ARM_CLIENT_ID ARM_CLIENT_SECRET ARM_SUBSCRIPTION_ID` |
| `AADSTS50078 ... multi-factor authentication has expired` | Política de MFA del tenant | `az login --tenant <tenant-id>` |
| AKS falla por cuota insuficiente o SKU no disponible | Cuota 0 en esa familia de VM o SKU restringido en la suscripción | `az vm list-usage -l <region> -o table` y `az vm list-skus -l <region> --size Standard_D2 -o table`; cambia `*_vm_size` en `infra/terraform.tfvars`. Una restricción tipo **Zone** no afecta si no usas zonas |
| `az acr import` → `429 Too Many Requests` (Docker Hub) | Límite de descargas anónimas de Docker Hub | El script reintenta y verifica el tag (a veces el ACR completa la importación aunque az reporte error). Alternativa: `public.ecr.aws/docker/library/<imagen>` o `--username/--password` de Docker Hub |
| `az acr build` termina con `UnicodeEncodeError: 'charmap' codec` | Bug de az CLI al mostrar logs en consolas Windows (cp1252); **el build sí funciona** | Los scripts usan `--no-logs` y validan el estado del run |
| `kubectl rollout undo` → `preStop: Required value: must specify a handler type` | kubectl < 1.30 no conoce `preStop.sleep` y lo descarta | Usar `preStop.exec` (como en este repo) o actualizar kubectl |
| 🐧 `permission denied: ./scripts/xxx.sh` | El script no tiene permiso de ejecución | `chmod +x scripts/*.sh`, o ejecútalo con `bash scripts/xxx.sh` |
| 🐧 `bad interpreter` o `$'\r': command not found` | El `.sh` quedó con finales de línea de Windows (CRLF) | El repo fuerza LF con `.gitattributes`; si copiaste el archivo a mano: `sed -i.bak 's/\r$//' scripts/*.sh` |
| 🪟 `running scripts is disabled on this system` | Política de ejecución de PowerShell | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| `No se pudo leer el output ... de Terraform` | Ejecutaste el script fuera de la máquina o la carpeta donde corriste `terraform apply` | Ejecuta desde la raíz del repo donde está `infra/terraform.tfstate`, o define `ACR_LOGIN_SERVER` (🪟 `$env:ACR_LOGIN_SERVER="..."` · 🐧 `export ACR_LOGIN_SERVER=...`) |
| `MissingSubscriptionRegistration` | Resource providers sin registrar | `az provider register -n Microsoft.ContainerService` (y `Microsoft.OperationsManagement`) |
| Pod en `Pending` | No hay recursos en los nodos, o hay un taint | `kubectl describe pod <pod> -n aks-store` → sección *Events* |
| Pod en `CrashLoopBackOff` | La app arranca y falla | `kubectl logs <pod> -n aks-store --previous` |

## 12. Material de apoyo

- [01 · Mini intro a Kubernetes](docs/01-intro-kubernetes.md): arquitectura, objetos, labels, probes, chuleta de `kubectl`
- [02 · AKS para arquitectos](docs/02-aks-para-arquitectos.md): responsabilidades, node pools, red, identidad, operación y checklist demo → producción
- [03 · Los scripts, explicados](docs/03-scripts-explicados.md): qué hace cada script por dentro, su equivalente manual y un ejercicio propuesto
- Tutorial original de Microsoft: <https://learn.microsoft.com/en-us/azure/aks/tutorial-kubernetes-prepare-app>
- Código fuente de la app: <https://github.com/Azure-Samples/aks-store-demo>
- Buenas prácticas de AKS: <https://learn.microsoft.com/en-us/azure/aks/best-practices>
