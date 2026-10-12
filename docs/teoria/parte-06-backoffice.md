# Teoría · Parte 6 · Desplegar el backoffice

[🏠 Índice de teoría](README.md) · [📋 Ir a la Parte 6 de la guía](../../GUIA-LABORATORIO.md#parte-6--desplegar-el-backoffice) · [⬅️ Parte 5](parte-05-tienda.md) · [Parte 7 ➡️](parte-07-network-policies.md)

**🎯 En una frase:** completamos el sistema de negocio: un worker consume la cola de pedidos, los guarda en una base de
datos y un portal administrativo permite gestionarlos. Además, dos simuladores generan actividad continua.

---

## Qué se desplegó

| Componente | Tipo de objeto | Rol en el negocio |
|---|---|---|
| `documentdb` | StatefulSet + Service ClusterIP | Base de datos de pedidos (compatible con la API de MongoDB) |
| `makeline-service` | Deployment + Service ClusterIP | **Worker:** saca pedidos de la cola y los guarda en la base de datos |
| `store-admin` | Deployment + Service **LoadBalancer** | Portal interno para ver y completar pedidos |
| `virtual-customer` | Deployment | Simula clientes que hacen pedidos (100 por hora) |
| `virtual-worker` | Deployment | Simula empleados que completan pedidos |

Archivos: [k8s/05-backoffice/](../../k8s/05-backoffice).

---

## 📚 Teoría

**1. Arquitectura orientada a eventos (productor → cola → consumidor)**

```
virtual-customer ─┐
navegador ────────┴─► order-service ──publica──► [ cola "orders" ] ──consume──► makeline-service ──► documentdb
                                                                                     ▲
                                                 store-admin / virtual-worker ───────┘ (consultan y completan)
```

- **Productores** (order-service) y **consumidores** (makeline-service) no se conocen: solo comparten la cola.
- Cada lado **escala de forma independiente**. Si llegan muchos pedidos, la cola crece y se pueden agregar
  consumidores, sin tocar el front.
- Por eso, tras desplegar el backoffice, la cola `orders` vuelve a 0: makeline la está vaciando.

**2. Dos formas de consumir un Secret**

- En la Parte 5 se usó `envFrom` (todas las claves del Secret como variables).
- Aquí, [makeline-deployment.yaml](../../k8s/05-backoffice/makeline-deployment.yaml) usa **`secretKeyRef`**: toma claves
  puntuales del Secret `rabbitmq-secrets` y les pone otro nombre de variable.
- Así, varios servicios pueden **reutilizar** un mismo Secret sin duplicar credenciales.

**3. Una base de datos dentro del cluster**

- DocumentDB corre como **StatefulSet** sin volumen persistente. Es suficiente para el demo, pero si el pod se reinicia
  **los datos se pierden**.
- Para datos en Kubernetes existen **PersistentVolumes**: con una *StorageClass* de Azure Disk, AKS crea un disco
  administrado por réplica y lo vuelve a conectar si el pod se mueve de nodo.

**4. Un segundo Service LoadBalancer**

- `store-admin` crea **otra** IP pública en el mismo Azure Load Balancer.
- La ResourceQuota del namespace permite máximo 2 LoadBalancers (`services.loadbalancers: "2"`). Ejemplo de cómo una
  cuota también controla **costo y exposición**.

**5. Deployments sin Service**

- Los simuladores no reciben tráfico: solo lo generan. Por eso no tienen Service.
- No todo pod necesita un Service: los *workers* y los *jobs* suelen no tenerlo.

---

## ⚙️ Qué hiciste y qué pasó

- Se crearon 5 workloads nuevos (12 pods en total en el namespace).
- DocumentDB tardó alrededor de un minuto en aceptar conexiones: su *startup probe* le da hasta 5 minutos.
- makeline-service empezó a consumir la cola.
- El portal admin obtuvo su IP pública y muestra los pedidos pendientes.

## ☁️ Conceptos core

Arquitectura orientada a eventos · productor/consumidor · `secretKeyRef` · StatefulSet para bases de datos ·
PersistentVolumes · cuotas de LoadBalancer.

## 🏗️ Mirada de arquitecto

Cómo llevaríamos este backoffice a producción en Azure:

| En el demo | En producción | Por qué |
|---|---|---|
| RabbitMQ en un pod | **Azure Service Bus** | Durabilidad, alta disponibilidad, SLA y colas de mensajes fallidos (*dead-letter*) sin operar el broker |
| DocumentDB en un pod sin disco | **Azure Cosmos DB for MongoDB** (o el PaaS que corresponda) | Backups, réplicas, escalado y SLA gestionados |
| store-admin con IP pública | IP **interna** (LoadBalancer interno), acceso por VPN/Private Link o protegido con **Entra ID** | Un portal administrativo no debe estar expuesto a internet |
| makeline-service con 1 réplica fija | Escalado por longitud de cola con **KEDA** | Más consumidores cuando la cola crece; cero cuando está vacía |
| Credenciales en Secrets | **Workload Identity** (sin contraseñas) hacia Service Bus y Cosmos DB | Elimina secretos que rotar |

Regla general para el arquitecto: **dejar el estado (bases de datos, colas) en servicios PaaS** y usar Kubernetes para
lo que mejor hace, que es ejecutar y escalar cómputo sin estado.

## 🔗 Para aprender más

- [Estilo de arquitectura orientada a eventos](https://learn.microsoft.com/en-us/azure/architecture/guide/architecture-styles/event-driven)
- [Patrón Competing Consumers](https://learn.microsoft.com/en-us/azure/architecture/patterns/competing-consumers)
- [Opciones de almacenamiento en AKS](https://learn.microsoft.com/en-us/azure/aks/concepts-storage)
- [KEDA en AKS (escalado por eventos)](https://learn.microsoft.com/en-us/azure/aks/keda-about)
- [Workload Identity en AKS](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)
- [LoadBalancer interno en AKS](https://learn.microsoft.com/en-us/azure/aks/internal-lb)

---

[⬅️ Parte 5 · La tienda](parte-05-tienda.md) · [🏠 Índice](README.md) · [Parte 7 · Network Policies ➡️](parte-07-network-policies.md)
