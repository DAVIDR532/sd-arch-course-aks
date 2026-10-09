# 01 · Mini intro a Kubernetes

## ¿Qué problema resuelve?

Un contenedor (Docker) empaqueta una app con todas sus dependencias. Pero en producción tenemos **decenas de contenedores** repartidos en **varias máquinas**, y alguien tiene que:

- decidir en qué máquina corre cada contenedor,
- reiniciarlo si se cae,
- escalarlo cuando sube la carga,
- darle una dirección estable para que otros lo encuentren,
- actualizarlo sin cortar el servicio.

Ese "alguien" es un **orquestador**. Kubernetes (K8s) es el estándar de facto.

> **Idea central: modelo declarativo.** Tú no dices "arranca 3 contenedores"; declaras en un YAML *"quiero que existan 3 réplicas"*. Kubernetes compara continuamente el **estado deseado** con el **estado real** y corrige las diferencias (bucle de reconciliación).

## Arquitectura de un cluster

```
                         ┌──────────────── CONTROL PLANE ────────────────┐
  kubectl / CI/CD ─────► │  kube-apiserver   ← única puerta de entrada    │
                         │  etcd             ← base de datos del estado   │
                         │  kube-scheduler   ← decide en qué nodo va c/pod│
                         │  controller-mgr   ← bucles de reconciliación   │
                         └───────────────────────┬───────────────────────┘
                                                 │
            ┌────────────────────────────────────┼───────────────────────────┐
            ▼                                    ▼                           ▼
   ┌─── NODO (VM) ────┐                ┌─── NODO (VM) ────┐        ┌─── NODO (VM) ────┐
   │ kubelet          │                │ kubelet          │        │ kubelet          │
   │ container runtime│                │ container runtime│        │ container runtime│
   │ kube-proxy / CNI │                │ kube-proxy / CNI │        │ kube-proxy / CNI │
   │  [pod] [pod]     │                │  [pod] [pod]     │        │  [pod]           │
   └──────────────────┘                └──────────────────┘        └──────────────────┘
```

| Componente | Rol |
|---|---|
| **kube-apiserver** | API REST. Todo (kubectl, nodos, controladores) habla con él. |
| **etcd** | Almacén clave-valor con el estado del cluster. |
| **scheduler** | Asigna pods a nodos según recursos, afinidades, taints. |
| **controller-manager** | Ejecuta los controladores (ReplicaSet, Deployment, Node...). |
| **kubelet** | Agente en cada nodo: arranca los contenedores que le asignan y reporta su salud. |
| **CNI** | Plugin de red: da IP a cada pod y conecta pods entre nodos. |

> En **AKS el control plane lo administra Microsoft** (no ves esas VMs ni pagas por ellas en el tier Free). Tú administras los nodos (node pools).

## Objetos que usamos en el demo

| Objeto | Qué es | Archivo del demo |
|---|---|---|
| **Namespace** | Partición lógica del cluster (equipo/app/ambiente). | `k8s/00-namespace/namespace.yaml` |
| **ResourceQuota** | Tope de CPU/memoria/pods por namespace. | `k8s/00-namespace/resourcequota.yaml` |
| **LimitRange** | Requests/limits por defecto para contenedores. | `k8s/00-namespace/limitrange.yaml` |
| **Pod** | Unidad mínima: 1+ contenedores que comparten IP y ciclo de vida. Nunca lo creamos directo. | (los crean los Deployments) |
| **Deployment** | Mantiene N réplicas de un pod *sin estado* y hace rolling updates. | `*/deployment.yaml` |
| **ReplicaSet** | Lo crea el Deployment; garantiza el número de réplicas. Una versión = un ReplicaSet. | (automático) |
| **StatefulSet** | Como Deployment pero con identidad estable (`rabbitmq-0`) para bases de datos/brokers. | `01-rabbitmq/statefulset.yaml` |
| **Service** | IP virtual + nombre DNS estable delante de un grupo de pods (por *labels*). | `*/service.yaml` |
| **ConfigMap** | Configuración no sensible inyectada como variables o archivos. | `03-order-service/configmap.yaml` |
| **Secret** | Datos sensibles (base64, **no** cifrado). | `*/secret.yaml` |
| **HorizontalPodAutoscaler** | Escala réplicas según CPU/memoria. | `04-store-front/hpa.yaml` |
| **NetworkPolicy** | Firewall entre pods. | `06-network-policies/` |

### Labels y selectors: el "pegamento"

```yaml
# Deployment: los pods que crea llevan esta etiqueta
template:
  metadata:
    labels:
      app: store-front

# Service: envía tráfico a TODOS los pods con esa etiqueta
selector:
  app: store-front
```

No hay referencias por nombre ni por IP: el Service encuentra a los pods por etiqueta. Si un pod muere y nace otro con nueva IP, el Service lo incluye automáticamente.

### Tipos de Service

| Tipo | Alcance | En el demo |
|---|---|---|
| `ClusterIP` | Solo dentro del cluster | rabbitmq, product-service, order-service |
| `NodePort` | Puerto abierto en cada nodo | — |
| `LoadBalancer` | IP pública vía el load balancer de la nube | store-front, store-admin |

### Requests vs Limits

- **requests**: lo que el pod *reserva*. El scheduler lo usa para decidir en qué nodo cabe.
- **limits**: el máximo. Si supera memoria → `OOMKilled`; si supera CPU → se le frena (throttling).

### Probes (sondas de salud)

| Probe | Pregunta | Si falla |
|---|---|---|
| `startupProbe` | ¿Ya terminó de arrancar? | Sigue esperando; las otras probes no corren todavía |
| `readinessProbe` | ¿Puede recibir tráfico? | Se saca del Service (no recibe peticiones) |
| `livenessProbe` | ¿Sigue vivo? | kubelet reinicia el contenedor |

## kubectl: chuleta mínima

```bash
kubectl get nodes                                  # nodos del cluster
kubectl get pods -n aks-store -o wide              # pods, IP y nodo
kubectl get all -n aks-store                       # todo lo del namespace
kubectl describe pod <pod> -n aks-store            # detalle + EVENTOS (¡clave para depurar!)
kubectl logs <pod> -n aks-store [-f]               # logs del contenedor
kubectl exec -it <pod> -n aks-store -- sh          # entrar al contenedor
kubectl apply -f archivo.yaml                      # crear/actualizar (declarativo)
kubectl delete -f archivo.yaml                     # borrar
kubectl rollout status deployment/<d> -n aks-store # seguir un despliegue
kubectl rollout history deployment/<d> -n aks-store
kubectl rollout undo deployment/<d> -n aks-store   # volver a la versión anterior
kubectl scale deployment/<d> --replicas=3 -n aks-store
kubectl port-forward svc/rabbitmq 15672:15672 -n aks-store
kubectl explain deployment.spec.strategy           # documentación de cualquier campo
```

## Estados de pod que verás (y qué significan)

| Estado | Causa típica |
|---|---|
| `Pending` | No hay nodo con recursos suficientes, o un taint lo impide → mira `describe` |
| `Init:0/1` | El init container aún no termina (p. ej. esperando a RabbitMQ) |
| `ContainerCreating` | Descargando imagen / montando volúmenes |
| `ImagePullBackOff` | No puede bajar la imagen (nombre mal escrito o **sin permiso AcrPull**) |
| `CrashLoopBackOff` | El contenedor arranca y muere una y otra vez → `kubectl logs --previous` |
| `CreateContainerConfigError` | Falta un Secret/ConfigMap referenciado |
| `OOMKilled` | Superó su límite de memoria |
