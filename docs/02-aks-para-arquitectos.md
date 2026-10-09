# 02 · AKS para arquitectos

Cada decisión de este demo está en [infra/main.tf](../infra/main.tf). Aquí está el **por qué** y qué cambiaría en producción.

## 1. Modelo de responsabilidad

| | Lo administra Microsoft | Lo administras tú |
|---|---|---|
| Control plane (API server, etcd, scheduler) | ✅ | |
| SLA del control plane | ✅ (tier Standard/Premium) | eliges el tier |
| Nodos (VMs en VMSS) | parches de imagen disponibles | tamaño, cantidad, cuándo actualizar |
| Versión de Kubernetes | publica versiones | decides cuándo y cómo actualizar |
| Apps, red interna, seguridad de pods | | ✅ |

**Tiers** (`sku_tier`): `Free` (sin SLA, demos/dev) · `Standard` (SLA 99.95% con zonas) · `Premium` (+ soporte LTS de versiones).

## 2. Recursos que crea el demo

```
rg-sdaks-demo-xxxxx                    ← lo crea Terraform
├── aks-sdaks-demo-xxxxx               (Microsoft.ContainerService/managedClusters)
├── acrsdaksdemoxxxxx                  (Azure Container Registry)
└── log-sdaks-demo-xxxxx               (Log Analytics → Container Insights)

rg-sdaks-demo-xxxxx-nodes              ← lo crea y administra AKS ("node resource group")
├── aks-system-xxxx-vmss               (VM Scale Set del pool system)
├── aks-apps-xxxx-vmss                 (VM Scale Set del pool apps)
├── kubernetes                         (Standard Load Balancer)
├── kubernetes-xxxx                    (IP pública que crea el Service LoadBalancer)
├── aks-vnet-xxxx                      (VNet gestionada)
└── identidades administradas (kubelet, agentes)
```

> Nunca modifiques a mano el *node resource group*: AKS lo reconcilia y puedes romper el cluster.

## 3. Node pools: system vs user

| Pool | Modo | Qué corre | En el demo |
|---|---|---|---|
| `system` | System | CoreDNS, metrics-server, konnectivity, agentes de monitoreo | 1 nodo `Standard_D2s_v5`, con taint `CriticalAddonsOnly` |
| `apps` | User | **Tus aplicaciones** | autoscaler 1→3 nodos, label `workload=apps` |

**Por qué separarlos:** una app que consume toda la CPU no puede tumbar el DNS del cluster. Además puedes tener pools con distinto hardware (GPU, memoria alta, Spot, Windows) y llevar cada carga al suyo con `nodeSelector`/`taints`.

**Producción:** pool system con 3 nodos en 3 zonas de disponibilidad (`zones = ["1","2","3"]`).

## 4. Escalado: dos niveles

```
   carga ↑  →  HPA agrega PODS  →  ¿no caben en los nodos? (pods Pending)
                                      →  Cluster Autoscaler agrega NODOS (VMs)
```

- **HPA** ([hpa.yaml](../k8s/04-store-front/hpa.yaml)): réplicas según % de CPU sobre el *request*.
- **Cluster Autoscaler** (`auto_scaling_enabled` en el pool `apps`): nodos según pods pendientes.
- Otras opciones: **KEDA** (escala por eventos: longitud de cola RabbitMQ/Service Bus) y **Node Auto Provisioning**.

## 5. Red

Elegimos **Azure CNI Overlay + Cilium**:

| Modelo | IP de los pods | Pros | Contras |
|---|---|---|---|
| kubenet (legado) | rango privado + rutas | simple | se retira, límites de escala |
| Azure CNI (plano) | IP de la VNet | pods alcanzables directamente desde la VNet | consume muchísimas IPs de la subred |
| **Azure CNI Overlay** | rango privado `10.244.0.0/16` | no consume IPs de la VNet, escala alto | pods no direccionables desde fuera |
| + **Cilium dataplane** | — | eBPF, Network Policies, observabilidad | — |

**Rangos del demo:** `pod_cidr 10.244.0.0/16` · `service_cidr 10.0.0.0/16` · `dns_service_ip 10.0.0.10`. En producción no deben solaparse con tus VNets/on-premises.

**Exposición:** el demo usa `Service type: LoadBalancer` (IP pública L4). En producción: **Application Routing add-on** (nginx gestionado), **Application Gateway for Containers** (L7 + WAF) o cluster **privado** detrás de Azure Front Door.

## 6. Identidad y seguridad

| Identidad | Para qué | Demo |
|---|---|---|
| Control plane (SystemAssigned) | Que AKS cree LB, IPs, discos en tu nombre | `identity { type = "SystemAssigned" }` |
| **Kubelet** | Que los nodos bajen imágenes del ACR | rol **AcrPull** sobre el ACR (`azurerm_role_assignment`) |
| **Workload Identity** | Que un *pod* acceda a Key Vault/Storage/SQL sin secretos | habilitado (`oidc_issuer_enabled`, `workload_identity_enabled`) |

- **ACR sin usuario admin** (`admin_enabled = false`): el pull se autoriza por identidad, nunca por contraseña.
- **Imágenes solo desde ACR**: el script `01-import-images.ps1` copia todo al registro privado. En producción se refuerza con Azure Policy ("solo registros permitidos") y Defender for Containers (escaneo de vulnerabilidades).
- **Acceso al cluster:** el demo usa cuentas locales (`az aks get-credentials`). Producción: **Entra ID + Azure RBAC para Kubernetes**, `local_account_disabled = true`, API server privado o con rangos IP autorizados.
- **Secrets:** los del demo son Secrets de Kubernetes. Producción: **Key Vault + Secrets Store CSI Driver**.
- **Network Policies:** por defecto todos los pods se hablan entre sí; ver [06-network-policies](../k8s/06-network-policies/).

## 7. Operación

- **Upgrades:** `automatic_upgrade_channel = "patch"` (parches de K8s) + `node_os_upgrade_channel = "NodeImage"` (imagen del SO). Programarlos con *maintenance windows*. `max_surge` controla cuántos nodos extra se crean durante la actualización.
- **Observabilidad:** Container Insights → Log Analytics (logs, métricas de nodos/pods). Alternativa moderna: Managed Prometheus + Managed Grafana.
- **Costos:** pagas las VMs de los nodos, discos, IPs públicas, LB, Log Analytics (por GB ingerido) y ACR. El control plane es gratis en tier Free. Ahorro: autoscaler, Spot node pools para cargas tolerantes, `az aks stop` en dev.

## 8. Checklist "demo → producción"

| Tema | Demo | Producción |
|---|---|---|
| SLA | Free | Standard + zonas |
| Pool system | 1 nodo | 3 nodos, 3 zonas |
| Acceso API | público + cuenta local | privado / IPs autorizadas + Entra ID RBAC |
| Ingreso | LoadBalancer público | App Gateway for Containers / App Routing + TLS + WAF |
| Secrets | K8s Secret | Key Vault + CSI + Workload Identity |
| Datos | RabbitMQ/DocumentDB en pods sin volumen | Service Bus / Cosmos DB (PaaS) o PVC con Azure Disk |
| Estado Terraform | local | backend `azurerm` con bloqueo |
| Despliegue de apps | `kubectl apply` manual | GitOps (Flux/Argo CD) o pipelines |
| Imágenes | ACR Standard | ACR Premium + Private Link + Defender |
