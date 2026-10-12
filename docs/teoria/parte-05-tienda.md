# Teoría · Parte 5 · Desplegar la tienda pieza por pieza

[🏠 Índice de teoría](README.md) · [📋 Ir a la Parte 5 de la guía](../../GUIA-LABORATORIO.md#parte-5--desplegar-la-tienda-pieza-por-pieza) · [⬅️ Parte 4](parte-04-acr.md) · [Parte 6 ➡️](parte-06-backoffice.md)

El corazón del laboratorio. Desplegamos una aplicación de **microservicios** objeto por objeto, para entender cómo
Kubernetes convierte archivos YAML en contenedores que se comunican entre sí y reciben tráfico de internet.

**La idea central: el modelo declarativo.** Cada YAML describe un **estado deseado**. `kubectl apply` lo guarda en el
API server (en etcd). Los **controladores** de Kubernetes trabajan continuamente para que el estado real coincida con
el deseado. Tú no ordenas "arranca un contenedor"; declaras "quiero 2 réplicas", y Kubernetes se encarga de que existan
siempre.

```
 YAML ──kubectl apply──► API server ──► etcd (estado deseado)
                              ▲
                              │ observa y corrige (bucle de reconciliación)
                         controladores ──► scheduler ──► kubelet en el nodo ──► contenedor
```

---

## 5.1 Abrir una segunda terminal para observar (recomendado)

[↩️ Volver al paso 5.1 de la guía](../../GUIA-LABORATORIO.md#51-abrir-una-segunda-terminal-para-observar-recomendado)

**🎯 En una frase:** dejamos una ventana "mirando" el cluster en tiempo real mientras desplegamos.

**📚 Teoría**

- La API de Kubernetes permite **watch**: en lugar de preguntar una y otra vez, el cliente abre una conexión y el API
  server le **envía cada cambio** a medida que ocurre.
- Los propios controladores de Kubernetes funcionan así: observan los objetos y reaccionan a los cambios.
- El ciclo de vida de un pod que verás: `Pending` (esperando nodo o imagen) → `ContainerCreating` / `Init` → `Running`.
  Además, la columna `READY` indica si pasó su *readiness probe*.

**⚙️ Qué hiciste y qué pasó:** `kubectl get pods -w` quedó suscrito a los cambios de pods del namespace `aks-store`.

**☁️ Conceptos core:** API de watch · ciclo de vida del pod · estado deseado vs. real.

**🔗 Para aprender más**
- [Ciclo de vida de un pod](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- [Conceptos de la API de Kubernetes (watch)](https://kubernetes.io/docs/reference/using-api/api-concepts/)

---

## 5.2 Namespace, cuota y límites

[↩️ Volver al paso 5.2 de la guía](../../GUIA-LABORATORIO.md#52-namespace-cuota-y-límites)

**🎯 En una frase:** creamos un espacio aislado para la tienda, con un tope de recursos y valores por defecto.

**📚 Teoría**

- **Namespace:** partición lógica del cluster. Agrupa objetos de una aplicación, equipo o ambiente. Los nombres solo
  tienen que ser únicos dentro del namespace, y sobre él se aplican permisos (RBAC), cuotas y políticas de red.
- **Requests y limits** (por contenedor):
  - **request:** lo que el contenedor **reserva**. El scheduler lo usa para decidir en qué nodo cabe.
  - **limit:** lo máximo que puede usar.
    - Si supera la **memoria** límite, el contenedor muere (`OOMKilled`).
    - Si supera la **CPU** límite, se le frena (*throttling*).
- **ResourceQuota** ([resourcequota.yaml](../../k8s/00-namespace/resourcequota.yaml)): techo para **todo** el namespace,
  por ejemplo 2 CPU de requests, 30 pods o 2 LoadBalancers.
- **LimitRange** ([limitrange.yaml](../../k8s/00-namespace/limitrange.yaml)): asigna requests/limits por defecto a los
  contenedores que no los declaran. Con una cuota activa, un pod sin recursos sería rechazado; el LimitRange lo evita.

**⚙️ Qué hiciste y qué pasó:** se crearon el namespace `aks-store`, la cuota y el LimitRange. La cuota muestra todo en
0 porque aún no hay pods.

**☁️ Conceptos core:** namespace · multi-tenancy · requests/limits · ResourceQuota · LimitRange.

**🏗️ Mirada de arquitecto:**
- **Namespaces o clusters.** En un cluster compartido entre equipos, los namespaces con cuotas, RBAC y Network Policies
  son la base del *multi-tenancy blando*. Para un aislamiento fuerte (clientes distintos, regulación) se usan clusters
  separados.
- **Los requests son costo.** Lo que se reserva determina cuántos nodos (VMs) pagas.

**🔗 Para aprender más**
- [Namespaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)
- [Resource quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [Limit ranges](https://kubernetes.io/docs/concepts/policy/limit-range/)
- [Gestión de recursos de contenedores (requests/limits)](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Buenas prácticas de aislamiento multi-tenant en AKS](https://learn.microsoft.com/en-us/azure/aks/operator-best-practices-cluster-isolation)

---

## 5.3 RabbitMQ (mensajería)

[↩️ Volver al paso 5.3 de la guía](../../GUIA-LABORATORIO.md#53-rabbitmq-mensajería)

**🎯 En una frase:** desplegamos la cola de mensajes donde se publican los pedidos, usando los objetos pensados para
componentes con estado.

**📚 Teoría**

- **StatefulSet** ([statefulset.yaml](../../k8s/01-rabbitmq/statefulset.yaml)): como un Deployment, pero cada réplica
  tiene **identidad estable**. Eso significa:
  - nombre fijo y ordinal (`rabbitmq-0`, `rabbitmq-1`…);
  - arranque y apagado en orden;
  - un volumen persistente propio por réplica, si se define.
  - Se usa para bases de datos, colas y sistemas distribuidos con estado.
- **Secret** ([secret.yaml](../../k8s/01-rabbitmq/secret.yaml)): guarda datos sensibles y se inyecta al contenedor como
  variables de entorno (`envFrom`). **Importante:** un Secret está **codificado en base64, no cifrado** de cara a quien
  puede leerlo. AKS cifra etcd en reposo, pero cualquiera con permiso de lectura sobre Secrets ve el valor.
- **Service ClusterIP** ([service.yaml](../../k8s/01-rabbitmq/service.yaml)): IP virtual estable + nombre DNS interno
  (`rabbitmq`), solo accesible dentro del cluster. Los demás pods se conectan a `rabbitmq:5672` sin importar la IP del pod.
- **Probes de tipo TCP:** Kubernetes verifica que el puerto 5672 acepte conexiones para saber si RabbitMQ arrancó
  (*startup*), si puede recibir tráfico (*readiness*) y si sigue vivo (*liveness*).

**⚙️ Qué hiciste y qué pasó:**
- `kubectl apply` creó el Secret, el Service y el StatefulSet.
- El controlador del StatefulSet creó el pod `rabbitmq-0` y el scheduler lo puso en el nodo `apps`.
- El kubelet descargó la imagen desde el ACR y arrancó el contenedor.
- `rollout status` esperó a que pasara la readiness probe.

**☁️ Conceptos core:** StatefulSet · Secret · Service ClusterIP · probes TCP · mensajería.

**🏗️ Mirada de arquitecto:**
- **Sin persistencia.** En este demo RabbitMQ **no tiene volumen persistente**: si el pod se reinicia, los mensajes en
  cola se pierden.
- **Opciones para producción:**
  1. StatefulSet con **PersistentVolumeClaim** (Azure Disk);
  2. mejor aún, un servicio PaaS como **Azure Service Bus**, que te da durabilidad, alta disponibilidad y SLA sin
     operar el broker.
- **Secretos.** Las credenciales irían en **Azure Key Vault**, montadas con el *Secrets Store CSI Driver* y
  **Workload Identity**.

**🔗 Para aprender más**
- [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Almacenamiento en AKS (volúmenes persistentes)](https://learn.microsoft.com/en-us/azure/aks/concepts-storage)
- [Azure Key Vault con el Secrets Store CSI Driver en AKS](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver)
- [Qué es Azure Service Bus](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-messaging-overview)

---

## 5.4 Product service y order service (APIs)

[↩️ Volver al paso 5.4 de la guía](../../GUIA-LABORATORIO.md#54-product-service-y-order-service-apis)

**🎯 En una frase:** desplegamos las dos APIs sin estado de la tienda: el catálogo y el servicio de pedidos.

**📚 Teoría**

- **Deployment → ReplicaSet → Pods:**
  - el **Deployment** declara "quiero N réplicas de esta plantilla de pod";
  - crea un **ReplicaSet**, que mantiene ese número exacto de pods: si uno muere, crea otro;
  - cada cambio de plantilla (por ejemplo, la imagen) crea un ReplicaSet nuevo. Así funcionan los rolling updates (Parte 9).
- **Pod:** unidad mínima de Kubernetes. Uno o más contenedores que comparten IP y ciclo de vida. Los pods son
  **efímeros**: cambian de nombre e IP cada vez que se recrean.
- **ConfigMap** ([configmap.yaml](../../k8s/03-order-service/configmap.yaml)): configuración **no sensible**, como el host
  y la cola, separada de la imagen. Así, la misma imagen sirve para todos los ambientes.
- **Init container** ([deployment.yaml](../../k8s/03-order-service/deployment.yaml)): contenedor que corre **antes** del
  principal y debe terminar con éxito. Aquí espera a que RabbitMQ acepte conexiones (`nc -zv rabbitmq 5672`). Por eso
  viste `Init:0/1`.
- **Las tres probes** (HTTP `/health` en order-service):

| Probe | Pregunta | Si falla |
|---|---|---|
| `startupProbe` | ¿Ya terminó de arrancar? | Espera; las otras probes aún no corren |
| `readinessProbe` | ¿Puede recibir tráfico? | Se saca del Service (no recibe peticiones) |
| `livenessProbe` | ¿Sigue vivo? | El kubelet reinicia el contenedor |

- **Endpoints:** el Service selecciona pods **por etiqueta** (`app: product-service`) y mantiene la lista de IPs de los
  pods *Ready*. Esa lista es lo que viste con `kubectl get endpoints`.
- **IPs de pods (`10.244.x.x`):** con **Azure CNI Overlay**, los pods reciben IPs de un rango privado propio (`pod_cidr`)
  que **no consume** direcciones de la red virtual.

**⚙️ Qué hiciste y qué pasó:**
- Se crearon 2 réplicas de cada API.
- Los pods de `order-service` esperaron en el init container hasta que RabbitMQ respondió, y luego pasaron sus probes.
- Todos cayeron en el nodo `apps`, por el taint del sistema.

**☁️ Conceptos core:** Deployment/ReplicaSet/Pod · ConfigMap · init containers · probes · labels y selectors · Azure CNI Overlay.

**🏗️ Mirada de arquitecto:**
- **Sin estado = escalable.** Los servicios sin estado son los que mejor escalan horizontalmente: cualquier réplica
  atiende cualquier petición.
- **Las probes son contratos de confiabilidad.** Una readiness mal configurada envía tráfico a pods que no están listos.
  Una liveness demasiado agresiva reinicia pods sanos en momentos de carga.
- **La red se decide al crear el cluster.** Azure CNI Overlay vs. Azure CNI plano es una decisión de **planificación de
  IPs**: con CNI plano, cada pod consume una IP de la subred.

**🔗 Para aprender más**
- [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Init containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
- [Liveness, readiness y startup probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/)
- [Conceptos de red en AKS](https://learn.microsoft.com/en-us/azure/aks/concepts-network)
- [Azure CNI Overlay](https://learn.microsoft.com/en-us/azure/aks/azure-cni-overlay)

---

## 5.5 Store front (la tienda web)

[↩️ Volver al paso 5.5 de la guía](../../GUIA-LABORATORIO.md#55-store-front-la-tienda-web)

**🎯 En una frase:** publicamos la tienda en internet con una IP pública y le damos capacidad de autoescalar.

**📚 Teoría**

- **Tipos de Service:**

| Tipo | Alcance | En este laboratorio |
|---|---|---|
| `ClusterIP` | Solo dentro del cluster | rabbitmq, product-service, order-service |
| `NodePort` | Un puerto en cada nodo | (lo usa internamente el LoadBalancer: `80:32285`) |
| `LoadBalancer` | IP externa vía el balanceador de la nube | store-front, store-admin |

- **Qué pasa en Azure con `type: LoadBalancer`:**
  1. el componente de nube de AKS (*cloud controller manager*) detecta el Service;
  2. crea una **IP pública**;
  3. agrega una regla en el **Azure Standard Load Balancer** (`kubernetes`) del node resource group;
  4. el tráfico llega a los nodos y de ahí a los pods *Ready*.
- **HPA** ([hpa.yaml](../../k8s/04-store-front/hpa.yaml)): escala las réplicas según la CPU. Lo verás en acción en la
  [teoría 11.4](parte-11-experimentos.md#114-autoescalado-hpa).
- **`topologySpreadConstraints`:** intenta repartir las réplicas entre nodos distintos. Si un nodo cae, no se pierden
  todas.

**⚙️ Qué hiciste y qué pasó:**
- Se crearon el Deployment, el Service y el HPA.
- Azure tardó ~1 minuto en asignar la IP pública: el estado `<pending>` es el tiempo en que se configura el Load Balancer.

**☁️ Conceptos core:** Service LoadBalancer · Azure Standard Load Balancer · IP pública · HPA · reparto de réplicas.

**🏗️ Mirada de arquitecto:**
- **Por qué no en producción.** Un Service LoadBalancer público por aplicación es simple pero **no es lo recomendado**:
  - es L4 (sin TLS, rutas ni WAF);
  - cada servicio tiene su propia IP pública.
- **En producción se usa una capa de entrada L7:**
  - **Application Routing add-on** (NGINX gestionado);
  - **Application Gateway for Containers** (L7 + WAF);
  - o **Azure Front Door** delante de un cluster privado.

**🔗 Para aprender más**
- [Services en Kubernetes](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Standard Load Balancer en AKS](https://learn.microsoft.com/en-us/azure/aks/load-balancer-standard)
- [Opciones de ingreso (ingress) en AKS](https://learn.microsoft.com/en-us/azure/aks/concepts-network-ingress)
- [Application Routing add-on](https://learn.microsoft.com/en-us/azure/aks/app-routing)
- [Application Gateway for Containers](https://learn.microsoft.com/en-us/azure/application-gateway/for-containers/overview)

---

## 5.6 Probar la tienda

[↩️ Volver al paso 5.6 de la guía](../../GUIA-LABORATORIO.md#56-probar-la-tienda)

**🎯 En una frase:** comprobamos el flujo de negocio completo, desde el navegador hasta la cola de mensajes.

**📚 Teoría**

- **Recorrido de un pedido:**

```
Navegador ─► IP pública ─► Azure LB ─► pod store-front (nginx)
                                          │ /api/orders  → http://order-service:3000   (DNS interno)
                                          │ /api/products → http://product-service:3002
                                          ▼
                                     order-service ─► publica en la cola "orders" de RabbitMQ
```

- **nginx como reverse proxy:** el navegador solo habla con el store-front. nginx reenvía las llamadas `/api/...` a los
  servicios internos **por nombre**. El nombre se resuelve con **CoreDNS** al ClusterIP del Service.
- **Comunicación asíncrona:**
  - order-service **no** procesa el pedido: lo deja en una cola y responde `201` de inmediato.
  - Esto desacopla el front de quien procesa los pedidos, absorbe picos de tráfico y permite que el procesador falle
    sin perder pedidos.
  - Es el patrón **Queue-Based Load Leveling**.
- **`kubectl exec`:** ejecuta un comando dentro de un contenedor (aquí, `rabbitmqctl`).
- **`kubectl port-forward`:** crea un túnel de tu equipo al pod **a través del API server**. No expone nada a internet;
  sirve para administrar o depurar.

**⚙️ Qué hiciste y qué pasó:** hiciste un pedido real en el navegador y comprobaste que quedó un mensaje en la cola `orders`.

**☁️ Conceptos core:** service discovery por DNS · reverse proxy · mensajería asíncrona · `exec` y `port-forward` para operación.

**🏗️ Mirada de arquitecto:** el patrón cola + worker es la base de los sistemas de comercio electrónico resistentes a
picos (Black Friday): el front acepta pedidos aunque el procesamiento vaya lento. Lo completarás en la Parte 6 con el
worker que consume la cola.

**🔗 Para aprender más**
- [DNS para Services y Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [Patrón Queue-Based Load Leveling](https://learn.microsoft.com/en-us/azure/architecture/patterns/queue-based-load-leveling)
- [Usar port-forward para acceder a aplicaciones](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/)
- [Tutorial oficial de AKS con esta misma aplicación](https://learn.microsoft.com/en-us/azure/aks/tutorial-kubernetes-prepare-app)

---

[⬅️ Parte 4 · ACR](parte-04-acr.md) · [🏠 Índice](README.md) · [Parte 6 · Backoffice ➡️](parte-06-backoffice.md)
