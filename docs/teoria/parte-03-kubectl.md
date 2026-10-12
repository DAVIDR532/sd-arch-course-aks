# Teoría · Parte 3 · Conectar kubectl al cluster

[🏠 Índice de teoría](README.md) · [📋 Ir a la Parte 3 de la guía](../../GUIA-LABORATORIO.md#parte-3--conectar-kubectl-al-cluster) · [⬅️ Parte 2](parte-02-terraform.md) · [Parte 4 ➡️](parte-04-acr.md)

Hasta ahora hablamos con **Azure** (ARM). Desde aquí hablamos con **Kubernetes** (su API server). Son dos planos de
control distintos y es clave que el estudiante los distinga:

| Plano | Cliente | Gestiona | Ejemplo |
|---|---|---|---|
| Azure Resource Manager | `az`, Terraform, portal | Recursos de Azure | Crear el cluster, escalar un node pool |
| API de Kubernetes | `kubectl` | Objetos dentro del cluster | Crear un Deployment, un Service |

---

## 3.1 Descargar las credenciales

[↩️ Volver al paso 3.1 de la guía](../../GUIA-LABORATORIO.md#31-descargar-las-credenciales)

**🎯 En una frase:** obtenemos la dirección del cluster y una credencial para que `kubectl` pueda hablar con él.

**📚 Teoría**

- **`kubeconfig`** (`~/.kube/config`) es el archivo que usa `kubectl`. Tiene tres secciones:
  - **clusters:** URL del API server y certificado de la autoridad del cluster;
  - **users:** credenciales (certificado, token o plugin de login);
  - **contexts:** combinación de *cluster + usuario + namespace*. El *current-context* indica a qué cluster apuntas.
- `az aks get-credentials` le pide a **Azure** (ARM) las credenciales del cluster y las agrega a tu kubeconfig. Necesitas
  permiso en Azure sobre el recurso AKS para obtenerlas.
- Opciones de autenticación en AKS:

| Opción | Uso |
|---|---|
| **Cuentas locales** (este laboratorio) | Simple. Quien obtiene el kubeconfig tiene acceso |
| **Entra ID + Kubernetes RBAC** | Login con la cuenta corporativa (MFA). Los permisos se definen con Roles/RoleBindings de Kubernetes |
| **Entra ID + Azure RBAC** | Login corporativo y permisos administrados como roles de Azure |

**⚙️ Qué hiciste y qué pasó:** se agregó un contexto `aks-sdaks-demo-xxxxx` a tu kubeconfig y quedó como contexto actual.

**☁️ Conceptos core:** kubeconfig y contextos · API server · autenticación del cluster (cuentas locales vs. Entra ID).

**🏗️ Mirada de arquitecto:**
- En producción: integración con **Entra ID**, `local_account_disabled = true` y permisos por grupos.
- El API server se publica de forma **privada** o se restringe a rangos de IP autorizados.
- Un kubeconfig con cuentas locales es una llave maestra: no se comparte ni se sube a repositorios.

**🔗 Para aprender más**
- [Organizar el acceso con kubeconfig](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)
- [Controlar el acceso al kubeconfig en AKS](https://learn.microsoft.com/en-us/azure/aks/control-kubeconfig-access)
- [Autenticación de AKS con Microsoft Entra ID](https://learn.microsoft.com/en-us/azure/aks/enable-authentication-microsoft-entra-id)
- [Conceptos de identidad y acceso en AKS](https://learn.microsoft.com/en-us/azure/aks/concepts-identity)

---

## 3.2 Ver los nodos

[↩️ Volver al paso 3.2 de la guía](../../GUIA-LABORATORIO.md#32-ver-los-nodos)

**🎯 En una frase:** vemos las máquinas donde Kubernetes ejecutará los contenedores.

**📚 Teoría**

- Un **nodo** es una máquina (aquí, una VM del VM Scale Set) que ejecuta tres componentes clave:
  - **kubelet:** el agente que recibe órdenes del API server y arranca los contenedores;
  - **container runtime** (`containerd`): descarga imágenes y ejecuta contenedores;
  - **red del nodo:** en este cluster, Cilium (eBPF) se encarga de la conectividad y de las políticas de red.
- **`STATUS Ready`** significa que el kubelet reporta que el nodo está sano y puede recibir pods.
- **Labels (etiquetas):** pares clave=valor en cualquier objeto de Kubernetes.
  - AKS agrega `agentpool=<pool>`; nosotros agregamos `workload=apps` desde Terraform.
  - `-L` muestra etiquetas como columnas.
  - Las etiquetas son la base de cómo Kubernetes **selecciona** cosas: nodos, pods, servicios.

**⚙️ Qué hiciste y qué pasó:** `kubectl` pidió al API server la lista de nodos: uno del pool `system` y uno del pool `apps`,
ambos `Ready` y con la versión de Kubernetes del cluster.

**☁️ Conceptos core:** nodo · kubelet · container runtime · labels · VM Scale Set como infraestructura del node pool.

**🏗️ Mirada de arquitecto:** los nodos son **ganado, no mascotas**. Si uno falla, AKS lo repara o reemplaza. Las
actualizaciones de imagen (`node_os_upgrade_channel = "NodeImage"`) crean nodos nuevos y drenan los viejos. Por eso las
aplicaciones nunca deben depender de un nodo específico.

**🔗 Para aprender más**
- [Nodos en Kubernetes](https://kubernetes.io/docs/concepts/architecture/nodes/)
- [Labels y selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
- [Actualizar la imagen de los nodos en AKS](https://learn.microsoft.com/en-us/azure/aks/node-image-upgrade)

---

## 3.3 Ver por qué las apps no caen en el nodo "system"

[↩️ Volver al paso 3.3 de la guía](../../GUIA-LABORATORIO.md#33-ver-por-qué-las-apps-no-caen-en-el-nodo-system)

**🎯 En una frase:** descubrimos el mecanismo que mantiene las aplicaciones fuera del pool del sistema.

**📚 Teoría**

- El **scheduler** decide en qué nodo corre cada pod. Tres herramientas lo influyen:

| Mecanismo | Dirección | Ejemplo |
|---|---|---|
| **Taint** (en el nodo) + **toleration** (en el pod) | El nodo **repele** pods | `CriticalAddonsOnly=true:NoSchedule` |
| **nodeSelector** | El pod **pide** nodos con cierta etiqueta | `kubernetes.io/os: linux` en nuestros YAML |
| **Affinity / anti-affinity** | Reglas más expresivas (preferencias, reparto) | "No pongas dos réplicas en el mismo nodo" |

- Un taint `NoSchedule` impide que se programen pods que **no** lo toleran. Los componentes del sistema de AKS sí lo
  toleran; nuestros pods no. Resultado: las apps van al pool `apps`.
- Lo activó Terraform con `only_critical_addons_enabled = true` en el pool `system`.

**⚙️ Qué hiciste y qué pasó:** `kubectl describe` mostró el taint del nodo del sistema. Más adelante (Parte 5)
comprobarás que todos los pods de la tienda caen en `aks-apps-...`.

**☁️ Conceptos core:** scheduler · taints y tolerations · nodeSelector · aislamiento de cargas.

**🏗️ Mirada de arquitecto:** con taints se construyen pools dedicados:
- GPU solo para cargas de IA;
- **Spot** (más baratos, interrumpibles) solo para trabajos tolerantes a fallos;
- pools aislados por cumplimiento normativo.

Es una herramienta de **costos y de confiabilidad** al mismo tiempo.

**🔗 Para aprender más**
- [Taints y tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [Asignar pods a nodos (nodeSelector, affinity)](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
- [Buenas prácticas del scheduler en AKS](https://learn.microsoft.com/en-us/azure/aks/operator-best-practices-advanced-scheduler)

---

## 3.4 Ver los componentes del sistema

[↩️ Volver al paso 3.4 de la guía](../../GUIA-LABORATORIO.md#34-ver-los-componentes-del-sistema)

**🎯 En una frase:** vemos los "servicios internos" que AKS instala para que el cluster funcione.

**📚 Teoría**

- Un cluster de Kubernetes tiene dos partes:

```
CONTROL PLANE (gestionado por Azure; no lo ves)     NODOS (tus VMs)
  kube-apiserver  ← puerta de entrada               kubelet + containerd
  etcd            ← base de datos del estado        pods del sistema (kube-system)
  scheduler       ← decide dónde corre cada pod     tus pods
  controller-manager ← bucles de reconciliación
```

- En el namespace **`kube-system`** verás, entre otros:

| Componente | Función |
|---|---|
| `coredns` | DNS interno: traduce `order-service` a una IP |
| `metrics-server` | Métricas de CPU/memoria para `kubectl top` y el HPA |
| `cilium` / `cilium-operator` | Red de pods y Network Policies (eBPF) |
| `konnectivity-agent` | Túnel seguro entre el control plane gestionado y los nodos |
| `ama-logs` | Agente de Azure Monitor (Container Insights) |
| `csi-azuredisk` / `csi-azurefile` | Drivers para montar discos y file shares de Azure |

**⚙️ Qué hiciste y qué pasó:** listaste los pods del sistema. Todos corren en el pool `system` (toleran el taint).

**☁️ Conceptos core:** control plane vs. nodos · add-ons gestionados · DNS interno · pipeline de métricas.

**🏗️ Mirada de arquitecto:** con AKS, Microsoft opera el control plane: escalado, alta disponibilidad, parches y
respaldo de etcd. El tier **Standard** agrega un SLA financiero sobre el API server. Tu responsabilidad empieza en los
nodos y en lo que despliegas.

**🔗 Para aprender más**
- [Componentes de un cluster de Kubernetes](https://kubernetes.io/docs/concepts/overview/components/)
- [Conceptos core de AKS (control plane y nodos)](https://learn.microsoft.com/en-us/azure/aks/core-aks-concepts)
- [Pipeline de métricas de recursos (metrics-server)](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)

---

[⬅️ Parte 2 · Terraform](parte-02-terraform.md) · [🏠 Índice](README.md) · [Parte 4 · ACR ➡️](parte-04-acr.md)
