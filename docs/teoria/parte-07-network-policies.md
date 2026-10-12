# Teoría · Parte 7 · Aplicar Network Policies

[🏠 Índice de teoría](README.md) · [📋 Ir a la Parte 7 de la guía](../../GUIA-LABORATORIO.md#parte-7--aplicar-network-policies) · [⬅️ Parte 6](parte-06-backoffice.md) · [Parte 8 ➡️](parte-08-build.md)

Esta parte introduce la **segmentación de red dentro del cluster**: el equivalente a los NSG o firewalls, pero entre
pods. Es la base de un enfoque **Zero Trust** en Kubernetes.

---

## 7.1 Probar ANTES de aplicar las políticas

[↩️ Volver al paso 7.1 de la guía](../../GUIA-LABORATORIO.md#71-probar-antes-de-aplicar-las-políticas)

**🎯 En una frase:** comprobamos que, por defecto, cualquier pod del cluster puede conectarse a cualquier otro.

**📚 Teoría**

- El modelo de red de Kubernetes es **plano** y **permisivo por defecto**:
  - cada pod tiene su propia IP;
  - cualquier pod puede comunicarse con cualquier otro, en cualquier namespace, sin NAT.
  - Es cómodo para empezar, pero significa que un pod comprometido puede llegar a la base de datos o a la cola.
- `kubectl run ... --rm -i --restart=Never` crea un **pod efímero**: corre un comando, muestra la salida y se borra.
  Es una herramienta clásica de diagnóstico.
- `nc -zv rabbitmq 5672` (*netcat*) intenta abrir una conexión TCP y dice si el puerto está abierto.

**⚙️ Qué hiciste y qué pasó:** un pod "intruso", sin relación con la tienda, abrió una conexión al puerto de RabbitMQ.
Respuesta: `open`.

**☁️ Conceptos core:** modelo de red plano de Kubernetes · pods efímeros de diagnóstico · movimiento lateral.

**🔗 Para aprender más**
- [El modelo de red de Kubernetes](https://kubernetes.io/docs/concepts/services-networking/)

---

## 7.2 Aplicar las políticas

[↩️ Volver al paso 7.2 de la guía](../../GUIA-LABORATORIO.md#72-aplicar-las-políticas)

**🎯 En una frase:** declaramos quién puede hablar con RabbitMQ, con la base de datos y con el catálogo.

**📚 Teoría**

- Una **NetworkPolicy** selecciona pods (`podSelector`) y define qué tráfico **entrante** (`Ingress`) o **saliente**
  (`Egress`) se permite. La de RabbitMQ ([rabbitmq-allow-producers-consumers.yaml](../../k8s/06-network-policies/rabbitmq-allow-producers-consumers.yaml)) dice:

  > A los pods con `app=rabbitmq` solo pueden entrar conexiones TCP al puerto 5672 desde pods con
  > `app=order-service` o `app=makeline-service`.

- **Reglas clave:**
  - En cuanto un pod queda seleccionado por una política de Ingress, **todo lo que no esté permitido explícitamente
    se bloquea**.
  - Las políticas son **aditivas**: listas de permitidos, nunca de denegados.
  - Los pods que ninguna política selecciona siguen abiertos.
- **¿Quién las aplica?** Kubernetes solo guarda la política; la **aplica el plugin de red**. En este cluster es
  **Cilium**, que usa **eBPF** en el kernel de cada nodo (`network_policy = "cilium"` en Terraform).
  - Sin un motor de políticas, los objetos NetworkPolicy existen pero **no tienen efecto**.
  - En AKS el motor se elige al crear el cluster: Azure NPM, Calico o Cilium.

| Política | Protege | Permite desde |
|---|---|---|
| `rabbitmq-allow-producers-consumers` | RabbitMQ :5672 | order-service, makeline-service |
| `documentdb-allow-makeline` | DocumentDB :10260 | makeline-service |
| `product-service-allow-frontends` | product-service :3002 | store-front, store-admin |

**⚙️ Qué hiciste y qué pasó:** se crearon las 3 políticas y Cilium las programó en los nodos en segundos.

**☁️ Conceptos core:** NetworkPolicy · selección por etiquetas · listas de permitidos · motor de políticas (Cilium/eBPF).

**🏗️ Mirada de arquitecto:**
- **Denegar por defecto.** La práctica recomendada es una política **default-deny** por namespace (todo bloqueado) más
  permisos explícitos por flujo, también para **egress**. Así un pod comprometido no puede sacar datos a internet.
- **Políticas de capa 7.** Cilium permite además políticas de L7 (por ruta HTTP o FQDN) y observabilidad de flujos con
  *Advanced Container Networking Services*.
- **Capas de red.** Las NetworkPolicies complementan, no reemplazan, a los **NSG** de la subred y al **Azure Firewall**
  para el egreso del cluster.

**🔗 Para aprender más**
- [Network Policies en Kubernetes](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Network Policies en AKS (motores disponibles)](https://learn.microsoft.com/en-us/azure/aks/use-network-policies)
- [Azure CNI con Cilium](https://learn.microsoft.com/en-us/azure/aks/azure-cni-powered-by-cilium)
- [Buenas prácticas de seguridad de red en AKS](https://learn.microsoft.com/en-us/azure/aks/operator-best-practices-network)

---

## 7.3 Probar DESPUÉS de aplicar las políticas

[↩️ Volver al paso 7.3 de la guía](../../GUIA-LABORATORIO.md#73-probar-después-de-aplicar-las-políticas)

**🎯 En una frase:** comprobamos que el intruso ya no llega a RabbitMQ y que la tienda sigue funcionando.

**📚 Teoría**

- **¿Por qué *timeout* y no "conexión rechazada"?** Cilium **descarta** los paquetes en silencio (*drop*); no responde
  con un rechazo. El cliente espera hasta agotar el tiempo (3 segundos con `-w 3`).
- **Identidad, no IP.** Las políticas filtran por **etiquetas**, no por direcciones. Aunque el pod de order-service
  cambie de IP mil veces, la política sigue aplicando. Es seguridad basada en **identidad de la carga de trabajo**,
  uno de los principios de **Zero Trust**.
- La tienda sigue funcionando porque el tráfico legítimo (order-service → RabbitMQ) está explícitamente permitido.

**⚙️ Qué hiciste y qué pasó:** el mismo comando del 7.1 terminó en `Connection timed out`, y un pedido desde el
navegador siguió funcionando. La validación automática ([Parte 10](parte-10-validacion.md)) repite esta prueba.

**☁️ Conceptos core:** drop vs. reject · seguridad basada en identidad · Zero Trust · microsegmentación.

**🏗️ Mirada de arquitecto:** en auditorías de seguridad (PCI, ISO 27001), la **microsegmentación** entre componentes
es un control habitual. Con NetworkPolicies versionadas en Git puedes demostrar qué flujos están permitidos y probarlo
automáticamente.

**🔗 Para aprender más**
- [Zero Trust: visión general](https://learn.microsoft.com/en-us/security/zero-trust/zero-trust-overview)
- [Conceptos de seguridad en AKS](https://learn.microsoft.com/en-us/azure/aks/concepts-security)

---

[⬅️ Parte 6 · Backoffice](parte-06-backoffice.md) · [🏠 Índice](README.md) · [Parte 8 · Build personalizado ➡️](parte-08-build.md)
