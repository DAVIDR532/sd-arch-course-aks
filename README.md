# sd-arch-course-aks

Demo de **Azure Kubernetes Service (AKS)** para el curso de Arquitectos Azure (SmartData · AZ-305).

Desplegamos con Terraform un **ACR + AKS** y sobre él la tienda de ejemplo de Microsoft
([AKS Store Demo](https://learn.microsoft.com/en-us/azure/aks/tutorial-kubernetes-deploy-application)),
pieza por pieza con YAMLs independientes, la personalizamos y la validamos de punto a punto.

## Arquitectura

```
                    Internet
                       │
          ┌────────────┴─────────────┐
          ▼                          ▼
   IP pública :80             IP pública :80            Azure Standard Load Balancer
          │                          │
┌─────────┼──────────── AKS · namespace aks-store ──────┼──────────────────────────┐
│         ▼                          ▼                                              │
│   store-front (Vue/nginx)    store-admin (Vue/nginx)                             │
│     │          │                │        │                                        │
│     │          ▼                ▼        ▼                                        │
│     │    product-service ◄──────┘   makeline-service ──► documentdb (MongoDB API) │
│     ▼          (Rust)                (Go)   ▲                                     │
│  order-service ──────► rabbitmq ────────────┘                                     │
│   (Node.js)    publica  cola "orders"  consume                                    │
│     ▲                                       ▲                                     │
│  virtual-customer (simula clientes)    virtual-worker (simula despachos)          │
└───────────────────────────────────────────────────────────────────────────────────┘
        ▲ imágenes (AcrPull con Managed Identity)
   Azure Container Registry          Log Analytics (Container Insights)
```

| Fase | Componentes | Carpeta |
|---|---|---|
| Base | Namespace, cuota, límites | [k8s/00-namespace](k8s/00-namespace) |
| Core (= tutorial de Microsoft) | rabbitmq, product-service, order-service, store-front + HPA | [k8s/01](k8s/01-rabbitmq) … [k8s/04](k8s/04-store-front) |
| Backoffice | documentdb, makeline-service, store-admin, simuladores | [k8s/05-backoffice](k8s/05-backoffice) |
| Seguridad | Network Policies | [k8s/06-network-policies](k8s/06-network-policies) |

## Estructura del repo

```
infra/          Terraform: RG, Log Analytics, ACR, AKS (pools system + apps), rol AcrPull
k8s/            Un YAML por objeto de Kubernetes, una carpeta por componente
scripts/        PowerShell: importar imágenes, build personalizado, aplicar YAMLs, validar
docs/           01 · Intro a Kubernetes   02 · AKS para arquitectos
```

> Los YAML usan el marcador `__ACR_LOGIN_SERVER__` en las imágenes. `scripts/k8s-apply.ps1`
> lo reemplaza por el login server del ACR (lo lee de `terraform output`).

## Prerrequisitos

- Azure CLI (`az`), Terraform ≥ 1.9, kubectl, PowerShell 7, git
- Permisos **Owner** (o Contributor + User Access Administrator) en la suscripción: Terraform crea un *role assignment*
- Cuota de al menos 4 vCPU (ideal 8) para el tamaño de VM elegido en la región (`az vm list-usage -l eastus2 -o table`)
- Resource providers registrados: `Microsoft.ContainerService`, `Microsoft.ContainerRegistry`, `Microsoft.OperationalInsights`, `Microsoft.OperationsManagement`

---

## Guía paso a paso

### Paso 0 · Login

```powershell
az login
az account set --subscription "<nombre o id>"
az account show -o table
```

### Paso 1 · Infraestructura con Terraform (~8-10 min)

```powershell
cd infra
cp terraform.tfvars.example terraform.tfvars   # edita subscription_id y, si hace falta, el tamaño de VM
$env:ARM_TENANT_ID = (az account show --query tenantId -o tsv)   # evita usar el token de otro tenant
terraform init
terraform plan -out tfplan
terraform apply tfplan
terraform output
cd ..
```

👀 **Para mostrar en el portal:** los dos resource groups (el tuyo y el `-nodes` que crea AKS), los node pools, el rol *AcrPull* en el IAM del ACR.

### Paso 2 · Conectar kubectl al cluster

```powershell
Invoke-Expression (terraform -chdir=infra output -raw get_credentials_command)
kubectl get nodes -L agentpool,workload
kubectl get pods -n kube-system          # los add-ons del sistema
kubectl describe node <nodo-system> | Select-String Taints
```

### Paso 3 · Llevar las imágenes al ACR privado

```powershell
./scripts/01-import-images.ps1
```

`az acr import` copia las imágenes de GHCR/Docker Hub al ACR **dentro de Azure** (sin Docker local).

### Paso 4 · Desplegar la tienda, pieza por pieza

Cada comando aplica una carpeta; entre pasos observa qué se creó.

```powershell
./scripts/k8s-apply.ps1 k8s/00-namespace
kubectl get ns; kubectl describe resourcequota -n aks-store

./scripts/k8s-apply.ps1 k8s/01-rabbitmq
kubectl get statefulset,pods,svc -n aks-store

./scripts/k8s-apply.ps1 k8s/02-product-service
./scripts/k8s-apply.ps1 k8s/03-order-service
kubectl get pods -n aks-store -w          # observa Init:0/1 → Running (Ctrl+C)

./scripts/k8s-apply.ps1 k8s/04-store-front
kubectl get svc store-front -n aks-store -w   # espera la EXTERNAL-IP
```

Abre `http://<EXTERNAL-IP>`, agrega productos al carrito y envía un pedido. 🎉

Ver los pedidos en la cola de RabbitMQ:

```powershell
kubectl exec -n aks-store rabbitmq-0 -- rabbitmqctl list_queues name messages
kubectl port-forward -n aks-store svc/rabbitmq 15672:15672   # http://localhost:15672  (username/password)
```

### Paso 5 · Backoffice y Network Policies

```powershell
./scripts/k8s-apply.ps1 k8s/05-backoffice
kubectl get svc store-admin -n aks-store -w    # portal admin en http://<EXTERNAL-IP>

./scripts/k8s-apply.ps1 k8s/06-network-policies
```

Ahora makeline-service consume la cola y guarda los pedidos en DocumentDB; los simuladores generan tráfico continuo.

> Atajo: `./scripts/03-deploy-app.ps1` aplica todas las carpetas en orden y espera a que todo esté listo
> (`-Core` para solo la parte del tutorial).

### Paso 6 · Personalización + rolling update + rollback

1. Construir la imagen personalizada **en Azure** con ACR Tasks:

   ```powershell
   ./scripts/02-build-storefront.ps1                 # "SmartData Pet Store", barra azul
   # o: ./scripts/02-build-storefront.ps1 -StoreName "Mi Tienda" -BrandColor "#7a1fa2"
   ```

2. En [k8s/04-store-front/deployment.yaml](k8s/04-store-front/deployment.yaml) cambia la etiqueta de la imagen
   `store-front:2.2.0` → `store-front:2.2.0-smartdata` y aplica:

   ```powershell
   ./scripts/k8s-apply.ps1 k8s/04-store-front/deployment.yaml
   kubectl rollout status deployment/store-front -n aks-store
   kubectl get rs -n aks-store -l app=store-front    # ReplicaSet viejo (0) y nuevo (2)
   ```

   Recarga la tienda: nuevo nombre y color, **sin downtime** (`maxUnavailable: 0`).

3. Rollback en un comando:

   ```powershell
   kubectl rollout history deployment/store-front -n aks-store
   kubectl rollout undo deployment/store-front -n aks-store
   ```

### Paso 7 · Validación punto a punto

```powershell
./scripts/04-validate.ps1
```

Comprueba: pods listos, apps fuera del pool *system*, todas las imágenes desde el ACR, IP pública,
`/health`, catálogo (front → product-service), pedido (front → order-service → RabbitMQ),
backoffice (admin → makeline → DocumentDB) y que la Network Policy bloquee un pod no autorizado.

### Paso 8 · Experimentos para la clase

| Experimento | Comando | Concepto |
|---|---|---|
| Auto-sanación | `kubectl delete pod -n aks-store -l app=product-service` y `kubectl get pods -w` | ReplicaSet recrea los pods |
| Escalado manual | `kubectl scale deploy/order-service --replicas=4 -n aks-store` | Réplicas, Service balancea |
| HPA | ver abajo | Autoescalado de pods |
| Cuota | `kubectl scale deploy/order-service --replicas=40 -n aks-store` y `kubectl get events -n aks-store` | ResourceQuota rechaza pods |
| Imagen inexistente | `kubectl run test --image=<acr>/no/existe:1 -n aks-store` y `kubectl describe pod test -n aks-store` | `ImagePullBackOff`, leer eventos |
| Logs | `kubectl logs -n aks-store deploy/order-service -f` | Observabilidad básica |
| DNS interno | `kubectl run -it dns --rm --image=<acr>/library/busybox:1.37.0 -n aks-store -- nslookup order-service` | Service discovery |
| Container Insights | Portal → AKS → Insights | Monitoreo gestionado |

Generar carga para el HPA:

```powershell
$acr = terraform -chdir=infra output -raw acr_login_server
kubectl run load -n aks-store --image="$acr/library/busybox:1.37.0" --restart=Never -- `
  sh -c "while true; do wget -q -O- http://store-front/ >/dev/null; done"
kubectl get hpa store-front -n aks-store -w
kubectl delete pod load -n aks-store
```

### Paso 9 · Limpieza (¡importante, para no pagar!)

```powershell
kubectl delete namespace aks-store      # opcional: borra solo la app
cd infra; terraform destroy
```

Para pausar sin destruir: `az aks stop -g <rg> -n <aks>` / `az aks start ...`

---

## Troubleshooting (problemas reales que aparecieron al preparar el demo)

| Síntoma | Causa | Solución |
|---|---|---|
| `InvalidAuthenticationTokenTenant ... wrong issuer` en `terraform plan` | Tienes sesión en varios tenants y Terraform usó el token de otro | `$env:ARM_TENANT_ID = "<tenant de la suscripción>"` |
| `AADSTS700016: Application ... was not found in the directory` | Hay variables `ARM_CLIENT_ID/ARM_CLIENT_SECRET` de un service principal en tu perfil y Terraform las prefiere sobre `az login` | En la sesión: `Remove-Item env:ARM_CLIENT_ID, env:ARM_CLIENT_SECRET, env:ARM_SUBSCRIPTION_ID` |
| `AADSTS50078 ... multi-factor authentication has expired` | Política de MFA del tenant | `az login --tenant <tenant-id>` |
| AKS falla con cuota insuficiente / SKU no disponible | Cuota 0 en esa familia de VM o SKU restringido en la suscripción | `az vm list-usage -l <region> -o table` y `az vm list-skus -l <region> --size Standard_D2 -o table`; cambia `*_vm_size` en `terraform.tfvars`. Una restricción tipo **Zone** no afecta si no usas zonas |
| `MissingSubscriptionRegistration` | Resource providers sin registrar | `az provider register -n Microsoft.ContainerService` (y `Microsoft.OperationsManagement`) |

## Documentación

- [01 · Mini intro a Kubernetes](docs/01-intro-kubernetes.md)
- [02 · AKS para arquitectos](docs/02-aks-para-arquitectos.md)
- Tutorial original de Microsoft: <https://learn.microsoft.com/en-us/azure/aks/tutorial-kubernetes-prepare-app>
- Código de la app: <https://github.com/Azure-Samples/aks-store-demo>
