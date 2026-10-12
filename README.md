# sd-arch-course-aks

Demo de **Azure Kubernetes Service (AKS)** para el curso de Arquitectos Azure (SmartData · AZ-305).

Desplegamos con Terraform un **ACR + AKS** y, sobre él, la tienda de ejemplo de Microsoft
([AKS Store Demo](https://learn.microsoft.com/en-us/azure/aks/tutorial-kubernetes-deploy-application)),
pieza por pieza con YAMLs independientes. Luego la personalizamos, la actualizamos sin downtime
y la validamos de punto a punto.

> ## ▶️ ¿Vas a hacer el laboratorio? Empieza aquí: **[GUIA-LABORATORIO.md](GUIA-LABORATORIO.md)**
> Guía paso a paso para copiar y pegar, con comandos para Windows, macOS y Linux, salida esperada y checkpoints.
> Este README es la visión general: objetivos, arquitectura y conceptos.

---

## Contenido

1. [Objetivos de aprendizaje](#1-objetivos-de-aprendizaje)
2. [Agenda sugerida](#2-agenda-sugerida)
3. [Arquitectura de la solución](#3-arquitectura-de-la-solución)
4. [Recorrido de una petición](#4-recorrido-de-una-petición)
5. [Mapa de conceptos → archivos](#5-mapa-de-conceptos--archivos)
6. [Estructura del repositorio](#6-estructura-del-repositorio)
7. [Cómo hacer el laboratorio](#7-cómo-hacer-el-laboratorio)
8. [Troubleshooting](#8-troubleshooting)
9. [Material de apoyo](#9-material-de-apoyo)

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

| Bloque | Tiempo | Contenido | En la guía |
|---|---|---|---|
| Teoría | 20 min | Mini intro a Kubernetes y AKS para arquitectos | [docs/](docs/) |
| Infraestructura | 15 min | Terraform: ACR + AKS. Recorrido por el portal mientras se crea | [Partes 1-3](GUIA-LABORATORIO.md#parte-1--conectarte-a-azure) |
| Registro privado | 5 min | Importar imágenes al ACR | [Parte 4](GUIA-LABORATORIO.md#parte-4--copiar-las-imágenes-al-registro-privado-acr) |
| Aplicación core | 20 min | Namespace → RabbitMQ → APIs → Frontend | [Parte 5](GUIA-LABORATORIO.md#parte-5--desplegar-la-tienda-pieza-por-pieza) |
| Backoffice y seguridad | 10 min | Base de datos, workers, Network Policies | [Partes 6-7](GUIA-LABORATORIO.md#parte-6--desplegar-el-backoffice) |
| Operación | 20 min | Imagen personalizada, rolling update, rollback | [Partes 8-9](GUIA-LABORATORIO.md#parte-8--construir-tu-versión-personalizada-de-la-tienda) |
| Validación | 5 min | Prueba punto a punto automatizada | [Parte 10](GUIA-LABORATORIO.md#parte-10--validación-punto-a-punto) |
| Laboratorio | 15 min | Auto-sanación, HPA, cuotas, DNS | [Parte 11](GUIA-LABORATORIO.md#parte-11--experimentos-opcionales) |
| Limpieza | 10 min | Destruir todo | [Parte 12](GUIA-LABORATORIO.md#parte-12--limpieza-obligatorio) |

> ⏱️ Para ahorrar tiempo en clase, crea la infraestructura (Parte 2) **antes** de la sesión: tarda ~7-10 minutos.
> Preparar el equipo ([Parte 0](GUIA-LABORATORIO.md#parte-0--preparar-tu-equipo-una-sola-vez)) se hace antes de clase.

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
├── README.md                      visión general (este archivo)
├── GUIA-LABORATORIO.md            ◄── guía paso a paso del laboratorio
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

## 7. Cómo hacer el laboratorio

Todo el paso a paso está en **[GUIA-LABORATORIO.md](GUIA-LABORATORIO.md)**: comandos listos para copiar y pegar en
🪟 **Windows (PowerShell 7)** y 🐧 **macOS / Linux (Bash)**, con la salida esperada y un checkpoint al final de cada parte.

| Parte | Qué haces | Comandos principales |
|---|---|---|
| [0](GUIA-LABORATORIO.md#parte-0--preparar-tu-equipo-una-sola-vez) | Instalar herramientas y clonar el repo | `winget` / `brew` / `apt`, `git clone` |
| [1](GUIA-LABORATORIO.md#parte-1--conectarte-a-azure) | Login, suscripción, providers, cuota | `az login`, `az account set`, `az provider register` |
| [2](GUIA-LABORATORIO.md#parte-2--crear-la-infraestructura-con-terraform) | Crear ACR + AKS | `terraform -chdir=infra init / plan / apply` |
| [3](GUIA-LABORATORIO.md#parte-3--conectar-kubectl-al-cluster) | Conectar kubectl | `az aks get-credentials`, `kubectl get nodes` |
| [4](GUIA-LABORATORIO.md#parte-4--copiar-las-imágenes-al-registro-privado-acr) | Imágenes al ACR | `scripts/01-import-images` |
| [5](GUIA-LABORATORIO.md#parte-5--desplegar-la-tienda-pieza-por-pieza) | Tienda pieza por pieza | `scripts/k8s-apply k8s/00…04` |
| [6](GUIA-LABORATORIO.md#parte-6--desplegar-el-backoffice) | Backoffice | `scripts/k8s-apply k8s/05-backoffice` |
| [7](GUIA-LABORATORIO.md#parte-7--aplicar-network-policies) | Network Policies (prueba antes/después) | `scripts/k8s-apply k8s/06-network-policies` |
| [8](GUIA-LABORATORIO.md#parte-8--construir-tu-versión-personalizada-de-la-tienda) | Imagen personalizada en ACR Tasks | `scripts/02-build-storefront` |
| [9](GUIA-LABORATORIO.md#parte-9--rolling-update-sin-downtime-y-rollback) | Rolling update y rollback | `kubectl rollout status / undo` |
| [10](GUIA-LABORATORIO.md#parte-10--validación-punto-a-punto) | Validación punto a punto | `scripts/04-validate` |
| [11](GUIA-LABORATORIO.md#parte-11--experimentos-opcionales) | Experimentos | `kubectl delete pod`, `scale`, HPA… |
| [12](GUIA-LABORATORIO.md#parte-12--limpieza-obligatorio) | **Limpieza** | `terraform -chdir=infra destroy` |

**Requisitos:** Azure CLI, Terraform ≥ 1.9, kubectl y git (instalación por SO en la
[Parte 0](GUIA-LABORATORIO.md#parte-0--preparar-tu-equipo-una-sola-vez)); rol **Owner** en la suscripción; cuota de 8-10 vCPU en la región.

**Costos:** se paga por las VMs de los nodos, discos, IPs públicas, Load Balancer, Log Analytics y ACR mientras existan.
El control plane es gratis en el tier Free. Al terminar, ejecuta siempre la [Parte 12](GUIA-LABORATORIO.md#parte-12--limpieza-obligatorio).

---

## 8. Troubleshooting

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

## 9. Material de apoyo

- [01 · Mini intro a Kubernetes](docs/01-intro-kubernetes.md): arquitectura, objetos, labels, probes, chuleta de `kubectl`
- [02 · AKS para arquitectos](docs/02-aks-para-arquitectos.md): responsabilidades, node pools, red, identidad, operación y checklist demo → producción
- [Guía del laboratorio](GUIA-LABORATORIO.md): paso a paso para copiar y pegar
- [03 · Los scripts, explicados](docs/03-scripts-explicados.md): qué hace cada script por dentro, su equivalente manual y un ejercicio propuesto
- Tutorial original de Microsoft: <https://learn.microsoft.com/en-us/azure/aks/tutorial-kubernetes-prepare-app>
- Código fuente de la app: <https://github.com/Azure-Samples/aks-store-demo>
- Buenas prácticas de AKS: <https://learn.microsoft.com/en-us/azure/aks/best-practices>
