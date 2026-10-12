# Teoría · Parte 9 · Rolling update sin downtime y rollback

[🏠 Índice de teoría](README.md) · [📋 Ir a la Parte 9 de la guía](../../GUIA-LABORATORIO.md#parte-9--rolling-update-sin-downtime-y-rollback) · [⬅️ Parte 8](parte-08-build.md) · [Parte 10 ➡️](parte-10-validacion.md)

Es uno de los momentos más importantes del laboratorio: **publicar una versión nueva mientras los usuarios compran**, y
demostrarlo con datos. Aquí se juntan varios conceptos anteriores: Deployments, ReplicaSets, probes, Services y el
Load Balancer.

---

## 9.1 Preparar el medidor de disponibilidad (segunda terminal)

[↩️ Volver al paso 9.1 de la guía](../../GUIA-LABORATORIO.md#91-preparar-el-medidor-de-disponibilidad-segunda-terminal)

**🎯 En una frase:** medimos la disponibilidad real de la tienda, desde fuera, mientras hacemos el cambio.

**📚 Teoría**

- **SLI** (*Service Level Indicator*) es una medida objetiva de la calidad del servicio; por ejemplo, el **% de
  peticiones exitosas**. El **SLO** es el objetivo, por ejemplo 99,9%.
- El bucle consulta `/health` 5 veces por segundo desde **fuera** del cluster, como un usuario. Cada `ERROR` es una
  petición fallida que un cliente habría visto.
- Medir desde fuera es una forma básica de **monitoreo sintético**.

**⚙️ Qué hiciste y qué pasó:** quedó corriendo un medidor que imprime la versión que responde la tienda en cada petición.

**☁️ Conceptos core:** SLI/SLO · monitoreo sintético · disponibilidad medida desde el usuario.

**🏗️ Mirada de arquitecto:** "sin downtime" es una afirmación que hay que **medir**, no suponer. En producción se usan
pruebas de disponibilidad de **Application Insights** o Azure Monitor desde varias regiones, con alertas.

**🔗 Para aprender más**
- [Pruebas de disponibilidad en Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/availability)
- [Objetivos de confiabilidad: SLO y SLA (Well-Architected)](https://learn.microsoft.com/en-us/azure/well-architected/reliability/metrics)

---

## 9.2 Cambiar la imagen en el YAML

[↩️ Volver al paso 9.2 de la guía](../../GUIA-LABORATORIO.md#92-cambiar-la-imagen-en-el-yaml)

**🎯 En una frase:** cambiamos el **estado deseado** en el archivo: la versión de la imagen del store-front.

**📚 Teoría**

- En el modelo declarativo, **desplegar = cambiar el estado deseado**. No se le dice a Kubernetes "actualiza los pods";
  se cambia el campo `image:` de la plantilla del Deployment y Kubernetes calcula el resto.
- El archivo del repositorio es la **fuente de verdad**. Por eso el cambio se hace en el YAML y no con un comando
  imperativo como `kubectl set image`, que cambiaría el cluster sin dejar rastro en Git.

**⚙️ Qué hiciste y qué pasó:** un comando de reemplazo de texto cambió solo la línea `image:` del archivo. El cluster
todavía no sabe nada del cambio.

**☁️ Conceptos core:** configuración declarativa · fuente de verdad en Git · cambio imperativo vs. declarativo.

**🔗 Para aprender más**
- [Gestión declarativa de objetos con kubectl](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/)

---

## 9.3 Aplicar el cambio (rolling update)

[↩️ Volver al paso 9.3 de la guía](../../GUIA-LABORATORIO.md#93-aplicar-el-cambio-rolling-update)

**🎯 En una frase:** Kubernetes reemplaza los pods viejos por nuevos **de a uno**, sin dejar de atender peticiones.

**📚 Teoría**

**1. Cómo funciona un rolling update**

Al cambiar la plantilla, el Deployment crea un **ReplicaSet nuevo** y va moviendo réplicas del viejo al nuevo según
la estrategia de [deployment.yaml](../../k8s/04-store-front/deployment.yaml):

```
maxSurge: 1        → puede haber 1 pod EXTRA durante el cambio (2 + 1 = 3)
maxUnavailable: 0  → nunca puede haber MENOS de 2 pods listos

  Viejo: ●● ──► ●● + nuevo ○ (arrancando) ──► ○ Ready ──► baja 1 viejo ──► ● + ○○ ... ──► ○○
```

**2. Las tres piezas que evitan errores**

| Pieza | Problema que evita |
|---|---|
| `maxUnavailable: 0` | Quedarse sin capacidad durante el cambio |
| `readinessProbe` | Que el pod nuevo reciba tráfico antes de estar listo |
| `preStop: sleep 10` | Que el pod viejo se apague mientras todavía le llega tráfico |

**3. Por qué hace falta el `preStop`**

Cuando Kubernetes decide eliminar un pod, **en paralelo**:
- (a) lo saca de los Endpoints del Service;
- (b) envía la señal de apagado (SIGTERM) al contenedor.

La actualización de (a) tarda un poco en llegar a todos los nodos y al Load Balancer. Si nginx se apaga antes (b),
llegan peticiones a un pod que ya no existe. El `preStop` retrasa el apagado 10 segundos para que (a) termine primero.

**4. Dato real de este laboratorio**

Sin `preStop` falló **1 de 143** peticiones durante el cambio; con `preStop`, **0 de 516**.

**⚙️ Qué hiciste y qué pasó:**
- `kubectl apply` actualizó la plantilla y el Deployment creó el ReplicaSet nuevo.
- Durante unos segundos convivieron ambas versiones (el medidor alternaba entre ellas).
- El ReplicaSet viejo quedó en 0 réplicas, pero **no se borró**: es el historial que permite el rollback.

**☁️ Conceptos core:** estrategia RollingUpdate · ReplicaSets y revisiones · readiness · ciclo de terminación del pod · hooks de ciclo de vida.

**🏗️ Mirada de arquitecto:** el rolling update es la estrategia por defecto. Existen otras para reducir riesgo:

| Estrategia | Cómo funciona | Cuándo |
|---|---|---|
| **Rolling update** | Reemplazo gradual de pods | La mayoría de los servicios sin estado |
| **Blue/green** | Dos versiones completas; se cambia el tráfico de golpe | Cambios grandes con rollback inmediato |
| **Canary** | Un % pequeño del tráfico va a la versión nueva y se observa | Cambios riesgosos; requiere ingress o service mesh |

Además: los **PodDisruptionBudgets** protegen la disponibilidad durante mantenimientos del cluster (por ejemplo,
actualizaciones de nodos).

**🔗 Para aprender más**
- [Actualizar un Deployment (rolling update)](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)
- [Terminación de pods](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination)
- [Hooks del ciclo de vida del contenedor (preStop)](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/)
- [Buenas prácticas de confiabilidad de aplicaciones en AKS](https://learn.microsoft.com/en-us/azure/aks/best-practices-app-cluster-reliability)

---

## 9.4 Rollback

[↩️ Volver al paso 9.4 de la guía](../../GUIA-LABORATORIO.md#94-rollback)

**🎯 En una frase:** volvemos a la versión anterior con un solo comando, también sin downtime.

**📚 Teoría**

- Cada cambio de plantilla genera una **revisión** (`kubectl rollout history`). `rollout undo` toma la plantilla de la
  revisión anterior (guardada en el ReplicaSet viejo) y hace un rolling update hacia ella.
- Es rápido porque la imagen anterior sigue en el ACR y, casi siempre, ya está en caché en el nodo.
- `revisionHistoryLimit` (por defecto 10) define cuántos ReplicaSets viejos se conservan.
- **Detalle real de este laboratorio:** con un `kubectl` 1.28 contra un cluster 1.35, `rollout undo` falló con
  `preStop: Required value`. El cliente viejo no conocía el campo nuevo `preStop.sleep` y lo descartaba. Se cambió a
  `preStop.exec`. Por eso conviene mantener `kubectl` dentro de ±1 versión del cluster.

**⚙️ Qué hiciste y qué pasó:** el Deployment volvió a la plantilla con la imagen `2.2.0`. El medidor mostró el cambio de
versión sin errores y la tienda volvió a "Contoso Pet Store".

**☁️ Conceptos core:** revisiones · rollback · compatibilidad de versiones cliente/servidor.

**🏗️ Mirada de arquitecto:** un rollback rápido reduce el **MTTR** (tiempo medio de recuperación), uno de los
indicadores clave de DORA. Diseñar para poder volver atrás (imágenes inmutables, cambios de base de datos compatibles
hacia atrás) es tan importante como diseñar para avanzar.

**🔗 Para aprender más**
- [Hacer rollback de un Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
- [Política de versiones de kubectl](https://kubernetes.io/releases/version-skew-policy/)

---

## 9.5 Volver a tu versión y dejar el repositorio consistente

[↩️ Volver al paso 9.5 de la guía](../../GUIA-LABORATORIO.md#95-volver-a-tu-versión-y-dejar-el-repositorio-consistente)

**🎯 En una frase:** hacemos que el cluster vuelva a coincidir con lo que dice el repositorio.

**📚 Teoría**

- **Drift (deriva):** diferencia entre el estado declarado (Git) y el real (cluster).
  - Después del `rollout undo`, el cluster corría `2.2.0` pero el YAML decía tu tag. Eso es *drift*.
  - Un `kubectl apply` posterior del YAML habría "deshecho el rollback" sin que nadie lo notara.
- **GitOps** resuelve esto automáticamente:
  - un agente dentro del cluster (**Flux**, disponible como extensión de AKS, o **Argo CD**) observa el repositorio y
    aplica cualquier cambio;
  - un rollback se hace con un **revert en Git**, no con `kubectl`.
  - Git queda como única fuente de verdad, con auditoría de quién cambió qué y cuándo.

**⚙️ Qué hiciste y qué pasó:** volviste a aplicar el YAML. El cluster quedó otra vez con tu versión, consistente con el archivo.

**☁️ Conceptos core:** drift · fuente de verdad · GitOps (Flux / Argo CD).

**🏗️ Mirada de arquitecto:** en producción nadie debería tener que ejecutar `kubectl apply` a mano. Las personas
proponen cambios con *pull requests*, un pipeline o un agente GitOps los aplica, y el acceso de escritura directo al
cluster se reserva para emergencias.

**🔗 Para aprender más**
- [GitOps con Flux v2 en AKS](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/conceptual-gitops-flux2)
- [Tutorial: desplegar aplicaciones con GitOps (Flux) en AKS](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/tutorial-use-gitops-flux2)

---

[⬅️ Parte 8 · Build personalizado](parte-08-build.md) · [🏠 Índice](README.md) · [Parte 10 · Validación ➡️](parte-10-validacion.md)
