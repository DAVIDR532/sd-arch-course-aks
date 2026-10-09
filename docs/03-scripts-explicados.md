# 03 · Los scripts, explicados

Los scripts de [scripts/](../scripts/) **no hacen magia**: solo encadenan comandos de `az`, `kubectl` y `git`
que tú mismo podrías escribir. Este documento abre cada uno, explica qué servicio de Azure o qué concepto de
Kubernetes usa y muestra **cómo hacer lo mismo a mano**, sin el script.

> Cada script existe en dos versiones con el mismo comportamiento:
> `.ps1` (PowerShell 7: Windows, y también macOS/Linux si instalas `pwsh`) y `.sh` (Bash: macOS, Linux, WSL, Git Bash).
> Se ejecutan **desde la raíz del repositorio**, aunque internamente resuelven las rutas desde su propia ubicación.

| Script | Para qué | Servicio / concepto | Paso de la guía |
|---|---|---|---|
| [`_common`](#_common--utilidades-compartidas) | Funciones compartidas | Outputs de Terraform | (lo usan todos) |
| [`k8s-apply`](#k8s-apply--aplicar-yamls-con-el-acr-correcto) | Aplicar YAMLs | `kubectl apply`, modelo declarativo | 4, 5, 6 |
| [`01-import-images`](#01-import-images--llevar-las-imágenes-al-acr) | Copiar imágenes al ACR | ACR Import | 3 |
| [`02-build-storefront`](#02-build-storefront--construir-una-imagen-personalizada-en-azure) | Construir imagen propia | ACR Tasks (build en la nube) | 6 |
| [`03-deploy-app`](#03-deploy-app--desplegar-todo-en-orden) | Desplegar todo de una vez | Orden de dependencias, `rollout status` | atajo de 4-5 |
| [`04-validate`](#04-validate--prueba-punto-a-punto) | Prueba punto a punto | Services, DNS, colas, NetworkPolicy | 7 |

---

## `_common` · utilidades compartidas

Archivos: [_common.ps1](../scripts/_common.ps1) · [_common.sh](../scripts/_common.sh)

Lo importan todos los scripts. Hace tres cosas:

1. **Calcula las rutas** del repo (`infra/`, `k8s/`) a partir de la ubicación del script.
2. **Lee los outputs de Terraform**, que son la "fuente de verdad" de los nombres generados (el ACR lleva un sufijo aleatorio):

   ```bash
   terraform -chdir=infra output -raw acr_name           # acrsdaksdemoxxxxx
   terraform -chdir=infra output -raw acr_login_server   # acrsdaksdemoxxxxx.azurecr.io
   ```

3. Permite **sobrescribir** el ACR con la variable `ACR_LOGIN_SERVER`, por si alguien no tiene el estado de Terraform en su máquina.

> 🧠 **Concepto:** los *outputs* de Terraform conectan la infraestructura con lo que se despliega encima.
> Así ningún nombre queda "quemado" en los scripts.

---

## `k8s-apply` · aplicar YAMLs con el ACR correcto

Archivos: [k8s-apply.ps1](../scripts/k8s-apply.ps1) · [k8s-apply.sh](../scripts/k8s-apply.sh)

**Problema que resuelve:** los YAML no pueden llevar el nombre real del ACR porque cambia en cada despliegue.
Por eso usan un marcador:

```yaml
image: __ACR_LOGIN_SERVER__/aks-store-demo/order-service:2.2.0
```

**Qué hace, paso a paso:**

1. Obtiene el login server del ACR (desde Terraform).
2. Si le pasas una **carpeta**, ordena los archivos: `namespace` → `quota/limitrange` → `secret` → `configmap` → el resto.
   Así un Deployment no arranca antes de que exista el Secret que necesita. Con `--delete`/`-Delete` usa el orden inverso.
3. Por cada archivo, **reemplaza el marcador en memoria** (el archivo del repo no cambia) y lo envía a `kubectl apply -f -`
   (el `-` significa "leer el YAML desde la entrada estándar").

**A mano, sin el script:**

```bash
# Bash
ACR=$(terraform -chdir=infra output -raw acr_login_server)
sed "s|__ACR_LOGIN_SERVER__|$ACR|g" k8s/03-order-service/deployment.yaml | kubectl apply -f -
```

```powershell
# PowerShell
$acr = terraform -chdir=infra output -raw acr_login_server
(Get-Content k8s/03-order-service/deployment.yaml -Raw).Replace('__ACR_LOGIN_SERVER__', $acr) | kubectl apply -f -
```

Los YAML que no tienen imágenes (namespace, service, configmap, secret, hpa, networkpolicy) se pueden aplicar directo:
`kubectl apply -f k8s/01-rabbitmq/service.yaml`.

> 🧠 **Concepto: `kubectl apply` es declarativo e idempotente.** Lo puedes ejecutar 10 veces y el resultado es el mismo.
> Kubernetes compara el YAML con lo que existe y solo cambia las diferencias:
> `created` la primera vez, `unchanged` si nada cambió y `configured` si algo cambió.
>
> 🏗️ **En producción** esto lo resuelven herramientas como **Kustomize** (`images:` override), **Helm** (`values.yaml`)
> o **GitOps** (Flux / Argo CD). El `sed` es la versión mínima del mismo patrón: *una plantilla + valores por ambiente*.

---

## `01-import-images` · llevar las imágenes al ACR

Archivos: [01-import-images.ps1](../scripts/01-import-images.ps1) · [01-import-images.sh](../scripts/01-import-images.sh)

**Qué hace:** recorre una lista de 10 imágenes públicas (7 de la tienda en GitHub Container Registry, 2 de Docker Hub
y 1 de DocumentDB) y por cada una ejecuta:

```bash
az acr import \
  --name <acr> \
  --source ghcr.io/azure-samples/aks-store-demo/order-service:2.2.0 \
  --image  aks-store-demo/order-service:2.2.0 \
  --force
```

| Parámetro | Significado |
|---|---|
| `--source` | Imagen de origen en un registro público |
| `--image` | Repositorio y tag de destino dentro de **tu** ACR |
| `--force` | Sobrescribe si ya existe (hace el script repetible) |

**Cómo funciona por dentro:** la copia ocurre **de registro a registro dentro de Azure**. La imagen no pasa por tu
computador y no necesitas Docker instalado. Se copian todas las arquitecturas (amd64, arm64…) del *manifest list*.

**Manejo de errores:** si Docker Hub responde `429 Too Many Requests` (límite de descargas anónimas), el script
espera 60 s y reintenta hasta 3 veces. Además verifica si el tag ya llegó al ACR, porque a veces Azure completa
la importación aunque `az` reporte error.

**Verificar a mano:**

```bash
az acr repository list --name <acr> -o table
az acr repository show-tags --name <acr> --repository aks-store-demo/store-front -o table
```

> 🧠 **¿Por qué no usar directamente las imágenes públicas?** Como arquitecto quieres:
> - **Disponibilidad:** un registro público caído o con límite (el 429 que vimos) no puede detener tus despliegues ni el autoescalado.
> - **Seguridad:** escanear las imágenes (Defender for Containers) y permitir solo registros aprobados (Azure Policy).
> - **Rendimiento:** el ACR está en la misma región que el cluster.
> - **Control de versiones:** la imagen no cambia aunque el autor la borre o la reemplace en el registro público.
>
> **¿Y cómo descarga AKS del ACR sin contraseña?** Terraform le dio el rol **AcrPull** a la identidad *kubelet*
> del cluster ([infra/main.tf](../infra/main.tf), `azurerm_role_assignment.aks_acr_pull`).

---

## `02-build-storefront` · construir una imagen personalizada en Azure

Archivos: [02-build-storefront.ps1](../scripts/02-build-storefront.ps1) · [02-build-storefront.sh](../scripts/02-build-storefront.sh)

Es el script más interesante: simula lo que haría un **pipeline de CI** (descargar código, modificarlo, compilarlo y
publicar la imagen) usando **ACR Tasks**.

**Parámetros:**

| PowerShell | Bash (variable de entorno) | Valor por defecto |
|---|---|---|
| `-StoreName` | `STORE_NAME` | `SmartData Pet Store` |
| `-BrandColor` | `BRAND_COLOR` | `#0b3d91` |
| `-Tag` | `TAG` | `2.2.0-smartdata` |

```bash
STORE_NAME="Mi Tienda" BRAND_COLOR="#7a1fa2" TAG="2.2.0-mitienda" ./scripts/02-build-storefront.sh
```

```powershell
./scripts/02-build-storefront.ps1 -StoreName "Mi Tienda" -BrandColor "#7a1fa2" -Tag "2.2.0-mitienda"
```

### Paso a paso

**1. Descarga el código fuente oficial, fijado en una versión**

```bash
git clone --depth 1 --branch 2.2.0 https://github.com/Azure-Samples/aks-store-demo.git
```

`--branch 2.2.0` asegura que el código coincide con las imágenes `2.2.0` que ya usamos. `--depth 1` descarga solo
la última versión, sin el historial. Se clona en una **carpeta temporal** que se borra al final.

**2. Aplica la personalización** (reemplazos de texto en el código Vue)

| Archivo | Cambio |
|---|---|
| `src/store-front/index.html` | `<title>Contoso Pet Store</title>` → `<title>SmartData Pet Store</title>` |
| `src/store-front/src/components/TopNav.vue` | Agrega `<span class="brand-name">SmartData Pet Store</span>` junto al logo |
| `src/store-front/src/components/TopNav.vue` | `background-color: #333` → color corporativo |

Si el texto original no aparece (por ejemplo, porque cambió la versión del código), el script **falla a propósito**
en lugar de construir una imagen sin personalizar.

**3. Compila la imagen EN AZURE con ACR Tasks**

```bash
az acr build \
  --registry <acr> \
  --image aks-store-demo/store-front:2.2.0-smartdata \
  --build-arg APP_VERSION=2.2.0-smartdata \
  --no-logs \
  src/store-front
```

Qué ocurre:

```
 tu equipo                          Azure (ACR Tasks)
 ─────────                          ──────────────────────────────────────────────
 src/store-front  ── sube .tar ──►  agente de build ejecuta el Dockerfile:
 (código fuente)                     1. FROM node  → npm install → npm run build (Vue)
                                     2. FROM nginx → copia /dist + nginx.conf
                                     3. push → acr/aks-store-demo/store-front:2.2.0-smartdata
```

- El [Dockerfile](https://github.com/Azure-Samples/aks-store-demo/blob/2.2.0/src/store-front/Dockerfile) es **multi-stage**:
  la etapa `node` compila y la imagen final solo lleva `nginx` con los archivos estáticos. Resultado: una imagen pequeña
  sin Node ni código fuente.
- `--build-arg APP_VERSION=...` queda grabado en la imagen y lo devuelve `/health`. Así comprobamos qué versión está corriendo.
- `--no-logs`: en consolas Windows el streaming de logs de `az` falla con un error de codificación aunque el build funcione.
  El script espera a que termine y valida que el estado sea `Succeeded`. Los logs se ven en el portal: ACR → Tasks → Runs,
  o con `az acr task logs -r <acr> --run-id <id>`.

**4. Lista los tags** para confirmar que la nueva imagen existe junto a la original.

### Verificar sin desplegar

```bash
az acr task list-runs -r <acr> -o table                                      # historial de builds
az acr repository show-tags -n <acr> --repository aks-store-demo/store-front # 2.2.0 y 2.2.0-smartdata
```

> 🧠 **Conceptos:**
> - **Imagen inmutable + tag nuevo:** no se modifica la imagen `2.2.0`; se crea `2.2.0-smartdata`. Por eso el rollback
>   es trivial: la versión anterior sigue en el registro.
> - **Build en la nube:** el estudiante no necesita Docker. En una empresa, esto mismo lo ejecuta un pipeline
>   (GitHub Actions / Azure DevOps) en cada commit, o una **ACR Task con trigger** cuando cambia el repositorio
>   o la imagen base (`az acr task create --context <repo-git> --commit-trigger-enabled true`).
> - **Separación build / deploy:** este script **solo construye**. Desplegar es otro paso (cambiar el tag en el YAML
>   y aplicarlo), igual que en CI/CD.

---

## `03-deploy-app` · desplegar todo en orden

Archivos: [03-deploy-app.ps1](../scripts/03-deploy-app.ps1) · [03-deploy-app.sh](../scripts/03-deploy-app.sh)

**Qué hace:** llama a `k8s-apply` con cada carpeta en orden numérico y luego **espera** a que cada workload esté listo:

```bash
./scripts/k8s-apply.sh k8s/00-namespace
./scripts/k8s-apply.sh k8s/01-rabbitmq
# ... 02, 03, 04, (05, 06 si no usas --core)

kubectl rollout status statefulset/rabbitmq        -n aks-store --timeout=600s
kubectl rollout status deployment/order-service    -n aks-store --timeout=600s
# ...
```

| Opción | Despliega |
|---|---|
| (sin opciones) | Carpetas 00 a 06: la tienda completa |
| `--core` / `-Core` | Carpetas 00 a 04: el escenario del tutorial de Microsoft |

> 🧠 **Concepto: `kubectl apply` no espera.** Solo registra el estado deseado en el API server y regresa de inmediato.
> `kubectl rollout status` es lo que **espera** a que los pods nuevos estén *Ready*. Un pipeline de CD siempre necesita
> ese segundo paso para saber si el despliegue realmente funcionó.
>
> El orden de carpetas importa poco gracias a los *init containers* y los reintentos de Kubernetes: si `order-service`
> arranca antes que RabbitMQ, espera. Aun así, respetar el orden evita errores transitorios y hace la demo más legible.

---

## `04-validate` · prueba punto a punto

Archivos: [04-validate.ps1](../scripts/04-validate.ps1) · [04-validate.sh](../scripts/04-validate.sh)

Cada verificación prueba un concepto distinto. Estos son los comandos equivalentes para hacerla a mano:

| # | Verificación | Comando equivalente | Qué demuestra |
|---|---|---|---|
| 1 | Pods listos | `kubectl get pods -n aks-store` | Probes de readiness OK |
| 1 | Apps fuera del pool `system` | `kubectl get pods -n aks-store -o wide` (columna NODE) | Taint `CriticalAddonsOnly` funcionando |
| 2 | Imágenes desde el ACR | `kubectl get pods -n aks-store -o jsonpath='{..image}'` | Ninguna dependencia de registros públicos |
| 3 | IP pública | `kubectl get svc store-front -n aks-store` | Service LoadBalancer → Azure LB |
| 3 | `/health` y página | `curl http://<IP>/health` | Versión desplegada (`APP_VERSION` del build) |
| 4 | Catálogo | `curl http://<IP>/api/products` | nginx → **DNS interno** → product-service |
| 5 | Pedido | `curl -X POST -H "Content-Type: application/json" -d '{"customerId":"1","items":[{"productId":1,"quantity":1,"price":10}]}' http://<IP>/api/orders` | Front → order-service (HTTP 201) |
| 5 | Cola | `kubectl exec -n aks-store rabbitmq-0 -- rabbitmqctl list_queues name messages` | Mensajería asíncrona |
| 6 | Backoffice | `curl http://<IP-admin>/api/makeline/order/fetch` | makeline consume la cola y lee DocumentDB |
| 7 | Network Policy | `kubectl run np --rm -i --restart=Never -n aks-store --image=<acr>/library/busybox:1.37.0 -- nc -zv -w 3 rabbitmq 5672` | Un pod sin la etiqueta autorizada recibe *timeout* |

Al final imprime un resumen `OK`/`FAIL` y devuelve **código de salida 0** si todo pasa (1 si algo falla).
Por eso sirve como *smoke test* en un pipeline: `./scripts/04-validate.sh && echo "Despliegue OK"`.

> 🧠 **Detalle de la prueba 7:** el pod `netpol-test` vive en el mismo namespace, pero **no** tiene la etiqueta
> `app=order-service` ni `app=makeline-service`. La NetworkPolicy solo permite el tráfico a RabbitMQ desde esas
> etiquetas, así que Cilium descarta los paquetes y `nc` termina por *timeout*. Las políticas filtran por
> **identidad (labels)**, no por IP.

---

## Ejercicio propuesto para los estudiantes

1. Construye tu propia versión: `STORE_NAME="Tienda <tu-nombre>" TAG="2.2.0-<tu-nombre>" ./scripts/02-build-storefront.sh`
2. Despliégala **sin el script `k8s-apply`**, solo con `sed`/`Replace` y `kubectl apply -f -`.
3. Observa el rolling update con `kubectl get pods -n aks-store -w` en otra terminal.
4. Verifica con `curl http://<IP>/health` que `version` sea tu tag.
5. Haz rollback con `kubectl rollout undo deployment/store-front -n aks-store` y explica qué ReplicaSet quedó activo (`kubectl get rs -n aks-store`).
