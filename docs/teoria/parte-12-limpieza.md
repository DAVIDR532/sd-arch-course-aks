# Teoría · Parte 12 · Limpieza

[🏠 Índice de teoría](README.md) · [📋 Ir a la Parte 12 de la guía](../../GUIA-LABORATORIO.md#parte-12--limpieza-obligatorio) · [⬅️ Parte 11](parte-11-experimentos.md)

Destruir también es parte del ciclo de vida. Con IaC, eliminar un ambiente es tan repetible y seguro como crearlo, y
es la principal herramienta para **controlar costos** en ambientes temporales.

---

## 12.1 Borrar la aplicación

[↩️ Volver al paso 12.1 de la guía](../../GUIA-LABORATORIO.md#121-borrar-la-aplicación)

**🎯 En una frase:** eliminamos la tienda completa con un solo comando.

**📚 Teoría**

- Borrar un **namespace** elimina **en cascada** todo lo que contiene: Deployments, pods, Services, Secrets, políticas.
- Al borrar los Services de tipo LoadBalancer, AKS **libera las IPs públicas** y las reglas del Azure Load Balancer.
  Hacerlo antes de destruir el cluster permite que esa limpieza ocurra de forma ordenada.
- Los **finalizers** hacen que el borrado espere a que terminen ciertas tareas de limpieza, como liberar recursos en la
  nube. Por eso el comando puede tardar un minuto.

**⚙️ Qué hiciste y qué pasó:** se borró el namespace `aks-store` con los 12 pods, los Services y las IPs públicas asociadas.

**☁️ Conceptos core:** borrado en cascada · finalizers · limpieza de recursos de nube creados por Kubernetes.

**🔗 Para aprender más**
- [Namespaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)
- [Finalizers](https://kubernetes.io/docs/concepts/overview/working-with-objects/finalizers/)

---

## 12.2 Destruir la infraestructura

[↩️ Volver al paso 12.2 de la guía](../../GUIA-LABORATORIO.md#122-destruir-la-infraestructura)

**🎯 En una frase:** Terraform elimina todo lo que creó, en el orden correcto.

**📚 Teoría**

- `terraform destroy` usa el **estado** para saber qué recursos existen y los elimina en **orden inverso de
  dependencias**: primero el role assignment y el node pool, luego el cluster y el ACR, y al final el resource group.
- Al eliminar el AKS, Azure borra también su **node resource group** (`rg-...-nodes`) con las VMs, discos, red y Load
  Balancer.
- Terraform pide confirmación escribiendo `yes`. En automatización se usa `-auto-approve`, con mucho cuidado.
- **Alternativas para no destruir:**

| Opción | Qué hace | Costo mientras está detenido |
|---|---|---|
| `az aks stop` / `start` | Apaga el control plane y los nodos, conservando la configuración | Se dejan de pagar las VMs; discos e IPs siguen costando |
| Escalar el pool `apps` a 0 | Quita los nodos de aplicaciones | Se sigue pagando el pool `system` |
| `terraform destroy` | Elimina todo | Nada |

**⚙️ Qué hiciste y qué pasó:** Terraform eliminó los 7 recursos (~10 minutos en la ejecución de referencia) y dejó el
estado vacío.

**☁️ Conceptos core:** ciclo de vida con IaC · orden de dependencias · node resource group · optimización de costos.

**🏗️ Mirada de arquitecto:**
- **Ambientes efímeros.** Los ambientes de desarrollo o prueba deberían crearse y destruirse bajo demanda, por ejemplo
  uno por *pull request*.
- **Gobierno de costos.** Para producción: **presupuestos y alertas** en Cost Management, **etiquetas** (`owner`,
  `project`, `environment`, como las de este laboratorio) para saber quién paga qué, y **bloqueos de recursos**
  (*resource locks*) para evitar borrados accidentales.

**🔗 Para aprender más**
- [Comando terraform destroy](https://developer.hashicorp.com/terraform/cli/commands/destroy)
- [Detener e iniciar un cluster AKS](https://learn.microsoft.com/en-us/azure/aks/start-stop-cluster)
- [Buenas prácticas de costos en AKS](https://learn.microsoft.com/en-us/azure/aks/best-practices-cost)
- [Bloquear recursos para evitar cambios inesperados](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/lock-resources)

---

## 12.3 Verificar que no quedó nada

[↩️ Volver al paso 12.3 de la guía](../../GUIA-LABORATORIO.md#123-verificar-que-no-quedó-nada)

**🎯 En una frase:** confirmamos que en la suscripción no quedó ningún recurso del laboratorio y limpiamos la
configuración local.

**📚 Teoría**

- **Verificar en Azure, no solo en Terraform.** Que Terraform diga "destroyed" no garantiza que Azure no tenga
  recursos creados **fuera** de Terraform, por ejemplo el node resource group que crea AKS. La consulta
  `az group list` con un filtro por prefijo lo comprueba en la fuente real.
- **Borrado asíncrono.** Algunas eliminaciones continúan en segundo plano. Si aparece un grupo, se espera unos minutos.
- **Limpiar el kubeconfig.** `kubectl config delete-context` quita el contexto de un cluster que ya no existe, para no
  apuntar por error a algo inexistente o, peor, a otro cluster con el mismo nombre en el futuro.
- **Cost Management.** Los costos aparecen en *Cost analysis* con unas horas de retraso. Allí se confirma cuánto costó
  el laboratorio, filtrando por las etiquetas.

**⚙️ Qué hiciste y qué pasó:** la consulta no devolvió ningún grupo `rg-sdaks-*` y tu `kubectl` dejó de tener el
contexto del cluster eliminado.

**☁️ Conceptos core:** verificación en la fuente de verdad · operaciones asíncronas · higiene de credenciales locales ·
Cost Management.

**🔗 Para aprender más**
- [Analizar costos con Cost Management](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/quick-acm-cost-analysis)
- [Usar etiquetas para organizar recursos](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/tag-resources)
- [Organizar el acceso con kubeconfig (contextos)](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)

---

## 🎓 Cierre del laboratorio

Recorrido completo, de la identidad a la operación:

| Capa | Lo que se usó | Parte |
|---|---|---|
| Identidad y gobierno | Entra ID, suscripciones, RBAC, resource providers, cuotas | 1 |
| Infraestructura como código | Terraform: variables, plan, estado, outputs | 2 |
| Plataforma | AKS: control plane gestionado, node pools, taints, add-ons | 2-3 |
| Cadena de suministro | ACR, importación, ACR Tasks, imágenes inmutables | 4, 8 |
| Aplicación | Namespaces, Deployments, StatefulSets, Services, ConfigMaps, Secrets, probes | 5-6 |
| Seguridad de red | Network Policies con Cilium | 7 |
| Operación | Rolling update, rollback, GitOps, smoke tests, HPA, monitoreo | 9-11 |
| Costos | Cuotas, autoscaling, destroy, Cost Management | 12 |

Para profundizar en el diseño de producción, revisa
[docs/02-aks-para-arquitectos.md](../02-aks-para-arquitectos.md) y la
[ruta de aprendizaje de AKS en Microsoft Learn](https://learn.microsoft.com/en-us/training/paths/intro-to-kubernetes-on-azure/).

---

[⬅️ Parte 11 · Experimentos](parte-11-experimentos.md) · [🏠 Índice](README.md)
