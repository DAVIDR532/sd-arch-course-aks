# Teoría · Parte 11 · Experimentos

[🏠 Índice de teoría](README.md) · [📋 Ir a la Parte 11 de la guía](../../GUIA-LABORATORIO.md#parte-11--experimentos-opcionales) · [⬅️ Parte 10](parte-10-validacion.md) · [Parte 12 ➡️](parte-12-limpieza.md)

Los experimentos convierten la teoría en evidencia: el estudiante **provoca** situaciones (fallos, picos de carga,
errores) y observa cómo responde la plataforma. Cada uno es independiente.

---

## 11.1 Auto-sanación: borrar pods

[↩️ Volver al paso 11.1 de la guía](../../GUIA-LABORATORIO.md#111-auto-sanación-borrar-pods)

**🎯 En una frase:** borramos pods a propósito y Kubernetes los recrea solo.

**📚 Teoría**

- **Bucle de reconciliación:** el controlador del ReplicaSet compara continuamente cuántos pods *debería* haber
  (`replicas: 2`) con cuántos *hay*. Al borrar los pods la diferencia es 2, y crea dos nuevos.
- Los pods nuevos tienen **otro nombre y otra IP**. Nadie lo nota porque los clientes usan el **Service**, que actualiza
  sus Endpoints automáticamente.
- El mismo mecanismo actúa si un contenedor falla (*liveness probe*) o si un nodo completo se cae. En ese caso, los pods
  se reprograman en otro nodo.

**⚙️ Qué hiciste y qué pasó:** `kubectl delete pod` eliminó las 2 réplicas de product-service; en segundos aparecieron
2 nuevas y la tienda siguió mostrando el catálogo.

**☁️ Conceptos core:** reconciliación · ReplicaSet · pods efímeros · desacople mediante Services.

**🏗️ Mirada de arquitecto:** la auto-sanación solo funciona si hay **más de una réplica** y si están en **nodos
distintos**, idealmente en **zonas** distintas. Con 1 réplica, borrar el pod significa unos segundos de caída.

**🔗 Para aprender más**
- [ReplicaSet](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)
- [Controladores y el patrón de reconciliación](https://kubernetes.io/docs/concepts/architecture/controller/)

---

## 11.2 Escalado manual

[↩️ Volver al paso 11.2 de la guía](../../GUIA-LABORATORIO.md#112-escalado-manual)

**🎯 En una frase:** cambiamos el número de réplicas y vemos cómo el Service reparte el tráfico entre todas.

**📚 Teoría**

- **Escalado horizontal:** agregar réplicas (más pods). **Escalado vertical:** dar más CPU/memoria a cada pod. Las apps
  sin estado escalan horizontalmente de forma natural.
- `kubectl scale` es un cambio **imperativo**: modifica el cluster pero no el YAML. Si alguien aplica el YAML después,
  vuelve a 2 réplicas. Es otro ejemplo de *drift* ([teoría 9.5](parte-09-rolling-update.md#95-volver-a-tu-versión-y-dejar-el-repositorio-consistente)).
- El Service balancea entre **todos** los Endpoints *Ready*: los 4 pods reciben tráfico.

**⚙️ Qué hiciste y qué pasó:** order-service pasó a 4 réplicas, los Endpoints del Service mostraron 4 IPs y luego
volviste a 2.

**☁️ Conceptos core:** escalado horizontal vs. vertical · balanceo del Service · cambio imperativo.

**🔗 Para aprender más**
- [Escalar un Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#scaling-a-deployment)
- [Opciones de escalado de aplicaciones en AKS](https://learn.microsoft.com/en-us/azure/aks/concepts-scale)

---

## 11.3 La cuota en acción

[↩️ Volver al paso 11.3 de la guía](../../GUIA-LABORATORIO.md#113-la-cuota-en-acción)

**🎯 En una frase:** pedimos más réplicas de las que permite la cuota del namespace y vemos cómo Kubernetes las rechaza.

**📚 Teoría**

- **Control de admisión:** antes de guardar un objeto, el API server lo pasa por *admission controllers*. El de
  **ResourceQuota** calcula si el pod nuevo cabe en el presupuesto del namespace. Si no cabe, **rechaza la creación**.
- El Deployment acepta el cambio a 40 réplicas, pero su ReplicaSet no logra crear los pods que superan la cuota. El
  motivo queda en los **eventos** (`FailedCreate ... exceeded quota`).
- **Los eventos** (`kubectl get events`, `kubectl describe`) son el registro de lo que el cluster intentó hacer y por
  qué falló. Son la primera fuente de diagnóstico.

**⚙️ Qué hiciste y qué pasó:** el Deployment se quedó por debajo de 40 réplicas y los eventos explicaron el límite
alcanzado (pods o límites de memoria/CPU de la cuota).

**☁️ Conceptos core:** admission controllers · ResourceQuota · eventos de Kubernetes.

**🏗️ Mirada de arquitecto:** las cuotas protegen contra errores (un bug que escala sin control) y contra el **costo
descontrolado**: menos pods significa menos nodos creados por el autoscaler. Junto con **Azure Policy for AKS** forman
las barandas de gobierno del cluster.

**🔗 Para aprender más**
- [Resource quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [Controladores de admisión](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)
- [Azure Policy para AKS](https://learn.microsoft.com/en-us/azure/aks/use-azure-policy)

---

## 11.4 Autoescalado (HPA)

[↩️ Volver al paso 11.4 de la guía](../../GUIA-LABORATORIO.md#114-autoescalado-hpa)

**🎯 En una frase:** generamos carga y vemos cómo Kubernetes agrega réplicas automáticamente.

**📚 Teoría**

**1. Cómo calcula el HPA**

El **HorizontalPodAutoscaler** ([hpa.yaml](../../k8s/04-store-front/hpa.yaml)) consulta cada ~15 segundos el uso de CPU
(vía **metrics-server**) y aplica:

```
réplicas deseadas = ceil( réplicas actuales × uso actual / uso objetivo )
ejemplo:            ceil( 2 × 71% / 60% ) = ceil(2,37) = 3
```

**2. El uso se mide contra el *request***

Por eso subimos el request de CPU del store-front de 1m a 50m. Con 1m, cualquier actividad mínima daba porcentajes
enormes y el HPA escalaría sin sentido.

**3. Estabilización al bajar**

Para reducir réplicas el HPA espera **5 minutos** de uso bajo. Así evita oscilar (subir y bajar constantemente).

**4. Dos niveles de autoescalado en AKS**

```
carga ↑ → HPA agrega PODS → ¿no caben en los nodos? (pods Pending)
                              → Cluster Autoscaler agrega NODOS (VMs) al pool "apps" (1 → 3)
```

**⚙️ Qué hiciste y qué pasó:** 3 pods generaron peticiones sin parar. La CPU del store-front subió por encima del 60%
(71-80% en la ejecución de referencia) y el HPA pasó de 2 a 3 réplicas en ~1 minuto. Al quitar la carga, volvió a 2
pasados los 5 minutos.

**☁️ Conceptos core:** HPA · metrics-server · requests como base del % · estabilización · cluster autoscaler.

**🏗️ Mirada de arquitecto:**

| Herramienta | Escala | Según |
|---|---|---|
| **HPA** | Pods | CPU, memoria o métricas personalizadas |
| **KEDA** (add-on de AKS) | Pods, incluso a 0 | Eventos: longitud de cola, mensajes de Service Bus, cron… |
| **VPA** | Recursos de cada pod | Uso histórico (recomienda requests) |
| **Cluster Autoscaler** | Nodos de un pool | Pods pendientes por falta de capacidad |
| **Node Auto Provisioning** | Nodos de tamaños óptimos | Necesidades de los pods pendientes |

Recuerda la [teoría 1.4](parte-01-conectarse-azure.md#14-verificar-la-cuota-de-máquinas-virtuales): todo este
autoescalado choca con la **cuota de vCPU** de la suscripción si no se planifica.

**🔗 Para aprender más**
- [Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Cluster autoscaler en AKS](https://learn.microsoft.com/en-us/azure/aks/cluster-autoscaler)
- [KEDA en AKS](https://learn.microsoft.com/en-us/azure/aks/keda-about)
- [Opciones de escalado en AKS](https://learn.microsoft.com/en-us/azure/aks/concepts-scale)

---

## 11.5 DNS interno (service discovery)

[↩️ Volver al paso 11.5 de la guía](../../GUIA-LABORATORIO.md#115-dns-interno-service-discovery)

**🎯 En una frase:** comprobamos cómo un pod encuentra a otro servicio solo por su nombre.

**📚 Teoría**

- **CoreDNS** crea automáticamente un registro DNS por cada Service: `<servicio>.<namespace>.svc.cluster.local`.
- Desde un pod del mismo namespace basta con el nombre corto (`order-service`), gracias a los *search domains*
  configurados en el `/etc/resolv.conf` de cada pod.
- El nombre resuelve a la **ClusterIP** del Service (`10.0.x.x`, del `service_cidr` definido en Terraform), no a la IP
  de un pod. El Service es una IP **virtual** que Cilium traduce a la IP de algún pod *Ready*.

**⚙️ Qué hiciste y qué pasó:** `nslookup order-service` devolvió el nombre completo y la ClusterIP del Service.

**☁️ Conceptos core:** service discovery · CoreDNS · FQDN de Services · ClusterIP virtual.

**🏗️ Mirada de arquitecto:** el service discovery por DNS elimina la configuración de IPs entre microservicios. Para
resolver nombres **fuera** del cluster (bases de datos con Private Endpoint, servicios on-premises) se integran zonas
**Azure Private DNS** y reenviadores de DNS.

**🔗 Para aprender más**
- [DNS para Services y Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [Personalizar CoreDNS en AKS](https://learn.microsoft.com/en-us/azure/aks/coredns-custom)

---

## 11.6 Diagnóstico: una imagen que no existe

[↩️ Volver al paso 11.6 de la guía](../../GUIA-LABORATORIO.md#116-diagnóstico-una-imagen-que-no-existe)

**🎯 En una frase:** provocamos un error común y aprendemos el método para diagnosticarlo.

**📚 Teoría**

- `ErrImagePull` → `ImagePullBackOff`: el kubelet no pudo descargar la imagen y reintenta con **espera exponencial**
  (*backoff*). Causas típicas:
  - nombre o tag mal escritos;
  - falta de permiso **AcrPull**;
  - registro inalcanzable;
  - límite de descargas (el 429 de Docker Hub).
- **Método de diagnóstico:**

| Paso | Comando | Responde |
|---|---|---|
| 1 | `kubectl get pods` | ¿En qué estado está? |
| 2 | `kubectl describe pod <pod>` → **Events** | ¿Qué intentó Kubernetes y qué falló? |
| 3 | `kubectl logs <pod>` (o `--previous`) | ¿Qué dijo la aplicación antes de fallar? |
| 4 | `kubectl get events -n <ns>` | ¿Qué más está pasando en el namespace? |

- Estados frecuentes y su significado: `Pending` (no hay nodo con recursos), `CrashLoopBackOff` (la app arranca y
  muere), `CreateContainerConfigError` (falta un Secret o ConfigMap), `OOMKilled` (superó el límite de memoria).

**⚙️ Qué hiciste y qué pasó:** el pod quedó en `ImagePullBackOff` y los eventos mostraron que la imagen no existe en el registro.

**☁️ Conceptos core:** estados de error del pod · eventos · método de diagnóstico.

**🔗 Para aprender más**
- [Depurar pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- [Solución de problemas en AKS](https://learn.microsoft.com/en-us/troubleshoot/azure/azure-kubernetes/welcome-azure-kubernetes)

---

## 11.7 Monitoreo con Container Insights

[↩️ Volver al paso 11.7 de la guía](../../GUIA-LABORATORIO.md#117-monitoreo-con-container-insights)

**🎯 En una frase:** vemos en Azure las métricas y los logs del cluster sin instalar nada adicional.

**📚 Teoría**

- **Container Insights** (habilitado en Terraform con el bloque `oms_agent`):
  - el agente `ama-logs` de cada nodo recolecta métricas de nodos, pods y contenedores, y los logs de los contenedores;
  - los envía al **Log Analytics workspace**;
  - el portal los muestra en vistas listas (Nodes, Controllers, Containers).
- Los datos se consultan con **KQL** (*Kusto Query Language*), por ejemplo los logs de un contenedor o los pods que se
  reiniciaron.
- Alternativa moderna para métricas: **Azure Monitor managed service for Prometheus** + **Azure Managed Grafana**.
- **Costo:** Log Analytics cobra por GB ingerido. Por eso conviene filtrar qué logs se recolectan.

**⚙️ Qué hiciste y qué pasó:** en el portal viste el consumo de CPU y memoria por controlador, incluido el pico del
store-front durante el experimento del HPA.

**☁️ Conceptos core:** Azure Monitor · Container Insights · Log Analytics · KQL · Prometheus gestionado.

**🏗️ Mirada de arquitecto:** monitorear es parte del diseño, no un agregado posterior. Se definen métricas clave,
alertas accionables (por ejemplo, pods en `CrashLoopBackOff` o nodos al 90% de CPU) y retención de logs según
requisitos regulatorios y de costo.

**🔗 Para aprender más**
- [Container Insights: visión general](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-overview)
- [Monitorear AKS](https://learn.microsoft.com/en-us/azure/aks/monitor-aks)
- [Log Analytics workspace](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-workspace-overview)
- [Managed Prometheus en Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/prometheus-metrics-overview)

---

[⬅️ Parte 10 · Validación](parte-10-validacion.md) · [🏠 Índice](README.md) · [Parte 12 · Limpieza ➡️](parte-12-limpieza.md)
