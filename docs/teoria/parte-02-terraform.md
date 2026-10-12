# Teoría · Parte 2 · Crear la infraestructura con Terraform

[🏠 Índice de teoría](README.md) · [📋 Ir a la Parte 2 de la guía](../../GUIA-LABORATORIO.md#parte-2--crear-la-infraestructura-con-terraform) · [⬅️ Parte 1](parte-01-conectarse-azure.md) · [Parte 3 ➡️](parte-03-kubectl.md)

Esta es la parte de **Infraestructura como Código**. Con un solo comando se crean siete recursos de Azure que
forman la plataforma: un grupo de recursos, un espacio de trabajo de Log Analytics, un Azure Container Registry, un
cluster AKS con su node pool de sistema, un node pool de aplicaciones y un permiso (role assignment). El código está
en [infra/main.tf](../../infra/main.tf).

---

## 2.1 Crear el archivo de variables

[↩️ Volver al paso 2.1 de la guía](../../GUIA-LABORATORIO.md#21-crear-el-archivo-de-variables)

**🎯 En una frase:** separamos **el código** (qué infraestructura) de **los valores** (en qué suscripción, región y con
qué tamaños).

**📚 Teoría**

- **Infraestructura como Código (IaC):** describir la infraestructura en archivos de texto versionables en vez de
  crearla con clics. Ganamos repetibilidad, revisión por pares, historial y la posibilidad de recrear ambientes idénticos.
- Terraform es **declarativo**: describes el **estado final deseado** ("quiero un AKS con estas características") y
  Terraform calcula los pasos para llegar ahí.
- **Variables de entrada** ([infra/variables.tf](../../infra/variables.tf)): parámetros con tipo, descripción, valor por
  defecto y **validaciones**. Por ejemplo, `prefix` solo acepta minúsculas y números porque el ACR no admite guiones.
- **`terraform.tfvars`**: archivo con los valores concretos. Terraform lo lee automáticamente.
  - Está en `.gitignore` porque contiene datos de **tu** entorno, como el Id de tu suscripción.
  - En el repositorio solo va la plantilla `terraform.tfvars.example`.

**⚙️ Qué hiciste y qué pasó:** generaste `infra/terraform.tfvars` a partir de la plantilla reemplazando el Id de
suscripción y, si hizo falta, el tamaño de VM.

**☁️ Conceptos core:** IaC declarativa · parametrización por ambiente · separar configuración y código.

**🏗️ Mirada de arquitecto:** el mismo código con distintos `.tfvars` produce dev, QA y producción. Esa es la base para
que los ambientes sean **consistentes**: lo que se probó en QA es exactamente lo que llega a producción. Los secretos
nunca van en `.tfvars` versionados: van en Key Vault o en variables protegidas del pipeline.

**🔗 Para aprender más**
- [Terraform en Azure: visión general](https://learn.microsoft.com/en-us/azure/developer/terraform/overview)
- [Variables de entrada en Terraform](https://developer.hashicorp.com/terraform/language/values/variables)
- [Qué es la Infraestructura como Código](https://learn.microsoft.com/en-us/devops/deliver/what-is-infrastructure-as-code)

---

## 2.2 Indicarle a Terraform con qué cuenta trabajar

[↩️ Volver al paso 2.2 de la guía](../../GUIA-LABORATORIO.md#22-indicarle-a-terraform-con-qué-cuenta-trabajar)

**🎯 En una frase:** nos aseguramos de que Terraform use la identidad y el tenant correctos para hablar con Azure.

**📚 Teoría**

- El provider `azurerm` puede autenticarse de varias formas:

| Método | Típico para | Cómo se activa |
|---|---|---|
| **Azure CLI** | Personas en su equipo | Usa la sesión de `az login` |
| **Service principal + secreto** | Pipelines (legado) | Variables `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID` |
| **OIDC / federación** | Pipelines modernos (GitHub Actions) | Sin secretos: confianza entre el proveedor del pipeline y Entra ID |
| **Managed identity** | Agentes que corren en Azure | La identidad del recurso donde corre Terraform |

- Si existen variables `ARM_CLIENT_ID`/`ARM_CLIENT_SECRET`, Terraform **las prefiere** sobre la sesión de la CLI.
- `ARM_TENANT_ID` fija el tenant cuando tu usuario pertenece a varios.
- Las variables de entorno que defines en una terminal **solo existen en ese proceso**. Por eso hay que repetirlas si
  abres otra terminal.

**⚙️ Qué hiciste y qué pasó:** fijaste el tenant de tu sesión actual y eliminaste (solo en esta terminal) cualquier
credencial de service principal que pudiera "ganarle" a tu `az login`.

**☁️ Conceptos core:** service principal · managed identity · federación OIDC · precedencia de credenciales.

**🏗️ Mirada de arquitecto:**
- En producción, Terraform corre en un **pipeline** con identidad federada (OIDC), sin secretos guardados, y con
  permisos limitados a las suscripciones que administra.
- Las personas no hacen `apply` desde su laptop.
- Este paso existe porque, al preparar el laboratorio, una variable de service principal olvidada en el perfil del
  usuario provocó el error `AADSTS700016`.

**🔗 Para aprender más**
- [Autenticar Terraform con Azure CLI](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/azure_cli)
- [Autenticación de Terraform en Azure (todas las opciones)](https://learn.microsoft.com/en-us/azure/developer/terraform/authenticate-to-azure)
- [Qué son las managed identities](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview)

---

## 2.3 Inicializar Terraform

[↩️ Volver al paso 2.3 de la guía](../../GUIA-LABORATORIO.md#23-inicializar-terraform)

**🎯 En una frase:** preparamos la carpeta de trabajo descargando los *plugins* que saben hablar con Azure.

**📚 Teoría**

- Terraform no sabe nada de Azure por sí mismo. Los **providers** son plugins que traducen el código HCL a llamadas de
  API. Este proyecto usa `azurerm` (Azure Resource Manager) y `random` (para el sufijo aleatorio). Están declarados en
  [infra/providers.tf](../../infra/providers.tf).
- `terraform init`:
  1. descarga los providers a `infra/.terraform/`;
  2. crea o respeta **`.terraform.lock.hcl`**, que fija las versiones exactas y sus *hashes*. Así todos usan los mismos
     binarios. Este archivo **sí** se versiona;
  3. inicializa el **backend**, el lugar donde se guarda el estado. Aquí es local; en producción, un Storage Account.
- `-chdir=infra` le indica a Terraform que trabaje en esa carpeta sin cambiar de directorio.

**⚙️ Qué hiciste y qué pasó:** Terraform descargó los providers indicados por el archivo de lock y quedó listo para planear.

**☁️ Conceptos core:** providers · *lock file* (reproducibilidad) · backend de estado.

**🔗 Para aprender más**
- [Comando terraform init](https://developer.hashicorp.com/terraform/cli/commands/init)
- [Provider azurerm (documentación)](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Dependency lock file](https://developer.hashicorp.com/terraform/language/files/dependency-lock)

---

## 2.4 Revisar el plan

[↩️ Volver al paso 2.4 de la guía](../../GUIA-LABORATORIO.md#24-revisar-el-plan)

**🎯 En una frase:** antes de cambiar nada, Terraform nos muestra **exactamente** qué va a crear, modificar o destruir.

**📚 Teoría**

- Terraform mantiene un **estado** (`terraform.tfstate`): un registro de qué recursos reales corresponden a cada bloque
  del código.
- `terraform plan` compara tres cosas: el **código**, el **estado** y la **realidad** en Azure. Luego calcula las diferencias:

| Símbolo | Significado |
|---|---|
| `+` | Crear |
| `~` | Modificar en sitio |
| `-/+` | Destruir y volver a crear (¡cuidado en producción!) |
| `-` | Destruir |

- Terraform construye un **grafo de dependencias**. Ejemplos: el role assignment necesita la identidad del AKS y el
  ACR; el AKS necesita el resource group y el Log Analytics. Lo que no depende entre sí se crea **en paralelo**.
- `-out tfplan` guarda el plan. Así, `apply` ejecuta **exactamente** lo que revisaste y no un plan recalculado.

**⚙️ Qué hiciste y qué pasó:** el plan mostró 7 recursos a crear (`Plan: 7 to add`). Todavía no existe nada en Azure.

**☁️ Conceptos core:** estado · *diff* entre lo deseado y lo real · grafo de dependencias · plan como control de cambios.

**🏗️ Mirada de arquitecto:**
- En equipos, el `plan` se publica en el *pull request* y alguien lo revisa antes del `apply`. Es el equivalente IaC de
  un **control de cambios**.
- Las líneas `-/+` (recrear) en recursos con datos o con IPs públicas son la principal causa de incidentes con IaC.
- Un plan sin cambios (`No changes`) demuestra que no hay *drift* (diferencias hechas a mano).

**🔗 Para aprender más**
- [Comando terraform plan](https://developer.hashicorp.com/terraform/cli/commands/plan)
- [El estado de Terraform](https://developer.hashicorp.com/terraform/language/state)

---

## 2.5 Crear la infraestructura

[↩️ Volver al paso 2.5 de la guía](../../GUIA-LABORATORIO.md#25-crear-la-infraestructura)

**🎯 En una frase:** Terraform ejecuta el plan y Azure crea la plataforma completa.

**📚 Teoría: qué es cada recurso**

| Recurso (código) | Qué es | Por qué está |
|---|---|---|
| `azurerm_resource_group` | Contenedor lógico | Ciclo de vida común: se borra todo junto |
| `azurerm_log_analytics_workspace` | Base de datos de logs y métricas | Destino de **Container Insights** |
| `azurerm_container_registry` | Registro privado de imágenes (ACR) | El cluster no depende de registros públicos (Parte 4) |
| `azurerm_kubernetes_cluster` | AKS: control plane gestionado + node pool `system` | La plataforma de contenedores |
| `azurerm_kubernetes_cluster_node_pool` | Node pool `apps` con autoscaler | Dónde corren las aplicaciones |
| `azurerm_role_assignment` | Permiso **AcrPull** sobre el ACR | El cluster descarga imágenes sin contraseña |

- **Qué pasa al crear un AKS:**
  - Azure aprovisiona un **control plane gestionado** (API server, etcd, scheduler). No ves sus VMs y en el tier Free
    no lo pagas.
  - Crea un **VM Scale Set** por node pool.
  - Configura la red, el Load Balancer y las identidades, e instala los add-ons.
  - Por eso tarda varios minutos.
- **Decisiones de diseño visibles en el código:**
  - **Red:** Azure CNI Overlay + Cilium.
  - **Identidad:** Managed Identity.
  - **Actualizaciones:** auto-upgrade de parches.
  - **Workload Identity** habilitado.
  - **Tier Free.**
  - El detalle de cada una está en [docs/02-aks-para-arquitectos.md](../02-aks-para-arquitectos.md).
- **El archivo `terraform.tfstate` queda en tu equipo y contiene datos sensibles**, entre ellos las credenciales del
  cluster. Por eso nunca se sube al repositorio.

**⚙️ Qué hiciste y qué pasó:**
- Terraform llamó a la API de ARM en el orden del grafo, esperó a que cada operación terminara y registró todo en el estado.
- En la ejecución de referencia: AKS ~4 min, node pool `apps` ~2 min, total ~7 min.

**☁️ Conceptos core:** AKS (control plane gestionado) · VM Scale Sets · Log Analytics · ACR · Azure RBAC.

**🏗️ Mirada de arquitecto:**
- **Estado remoto en producción:** el estado se guarda en un **Storage Account con bloqueo** (backend `azurerm`), para
  que dos personas no hagan `apply` a la vez y el estado no se pierda con una laptop.
- **Comparar con la arquitectura de referencia:** la *AKS baseline architecture* de Microsoft muestra cómo se ve este
  diseño en producción (red privada, firewall de egreso, zonas, etc.).

**🔗 Para aprender más**
- [Conceptos core de AKS](https://learn.microsoft.com/en-us/azure/aks/core-aks-concepts)
- [Arquitectura de referencia: AKS baseline](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/containers/aks/baseline-aks)
- [Tiers de precio de AKS (Free, Standard, Premium)](https://learn.microsoft.com/en-us/azure/aks/free-standard-pricing-tiers)
- [Backend azurerm para el estado de Terraform](https://developer.hashicorp.com/terraform/language/backend/azurerm)

---

## 2.6 Guardar los nombres generados en variables

[↩️ Volver al paso 2.6 de la guía](../../GUIA-LABORATORIO.md#26-guardar-los-nombres-generados-en-variables)

**🎯 En una frase:** leemos de Terraform los nombres reales de lo que se creó, para usarlos en los siguientes pasos.

**📚 Teoría**

- **Outputs** ([infra/outputs.tf](../../infra/outputs.tf)): valores que Terraform expone después del `apply`, como el
  nombre del ACR, el resource group o el comando de credenciales. Son el **contrato** entre la capa de infraestructura y
  lo que se despliega encima.
- **Sufijo aleatorio:** algunos nombres en Azure son **globales** porque forman parte de un DNS público. El ACR, por
  ejemplo, es `<nombre>.azurecr.io`. El recurso `random_string` agrega un sufijo para que dos estudiantes no choquen.
- **Convenciones de nombres:** se usan prefijos por tipo de recurso, siguiendo las recomendaciones del Cloud Adoption
  Framework: `rg-` (resource group), `aks-`, `acr`, `log-`.

**⚙️ Qué hiciste y qué pasó:** guardaste `ACR`, `ACR_NAME`, `RG` y `AKS` en variables del shell. Los scripts del
laboratorio leen estos mismos outputs automáticamente.

**☁️ Conceptos core:** outputs de Terraform · nombres globales vs. locales · convención de nombres.

**🏗️ Mirada de arquitecto:** evitar nombres "quemados" en scripts y manifiestos permite crear N ambientes con el mismo
código. Es el mismo problema que resuelve el marcador `__ACR_LOGIN_SERVER__` en los YAML (ver
[docs/03](../03-scripts-explicados.md#k8s-apply--aplicar-yamls-con-el-acr-correcto)).

**🔗 Para aprender más**
- [Output values en Terraform](https://developer.hashicorp.com/terraform/language/values/outputs)
- [Convención de nombres de recursos (CAF)](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming)
- [Abreviaturas recomendadas por tipo de recurso](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations)

---

## 2.7 Recorrido por el portal

[↩️ Volver al paso 2.7 de la guía](../../GUIA-LABORATORIO.md#27-recorrido-por-el-portal)

**🎯 En una frase:** vemos en el portal lo que Terraform creó y descubrimos lo que **AKS** creó por su cuenta.

**📚 Teoría**

- **Node resource group** (`rg-...-nodes`, por defecto `MC_...`): AKS crea un segundo grupo de recursos donde
  administra la infraestructura de los nodos:
  - los **VM Scale Sets** (uno por node pool),
  - los discos y la red virtual,
  - el **Standard Load Balancer** (`kubernetes`) y las IPs públicas,
  - las identidades de los agentes.
  - **No se modifica a mano:** AKS lo reconcilia y un cambio manual puede romper el cluster.
- **Node pools:**
  - `system` (modo *System*): aloja componentes críticos como CoreDNS y metrics-server.
  - `apps` (modo *User*): aloja tus aplicaciones y tiene **cluster autoscaler** (1 a 3 nodos).
- **Azure RBAC: role assignment = quién + qué rol + sobre qué alcance.** Aquí:
  - quién: la identidad *kubelet* del cluster (`...-agentpool`);
  - qué rol: **AcrPull** (solo descargar imágenes);
  - sobre qué: el ACR.
  - Es el **principio de mínimo privilegio**: el cluster puede leer imágenes, pero no publicarlas ni borrarlas.
- **Managed identities:** identidades administradas por Azure, sin contraseñas que rotar ni guardar.

**⚙️ Qué hiciste y qué pasó:** identificaste los dos resource groups, los node pools y el permiso AcrPull en el IAM del ACR.

**☁️ Conceptos core:** node resource group · VM Scale Sets · node pools system/user · managed identity · Azure RBAC (mínimo privilegio).

**🏗️ Mirada de arquitecto:**
- **Por qué separar los pools.** Separar *system* y *user* evita que una aplicación hambrienta de recursos tumbe el DNS
  del cluster. Además permite pools especializados: GPU, Spot, Windows, alta memoria.
- **Zonas en producción.** El pool *system* debería tener 3 nodos repartidos en zonas de disponibilidad.
- **Identidades.** Para que AKS acceda a Azure no hay que crear service principals con secretos: las managed
  identities son la opción recomendada.

**🔗 Para aprender más**
- [Node resource group (FAQ de AKS)](https://learn.microsoft.com/en-us/azure/aks/faq)
- [Node pools de sistema y de usuario](https://learn.microsoft.com/en-us/azure/aks/use-system-pools)
- [Usar managed identities en AKS](https://learn.microsoft.com/en-us/azure/aks/use-managed-identity)
- [Integrar ACR con AKS (AcrPull)](https://learn.microsoft.com/en-us/azure/aks/cluster-container-registry-integration)
- [Qué es Azure RBAC](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview)

---

[⬅️ Parte 1 · Conectarte a Azure](parte-01-conectarse-azure.md) · [🏠 Índice](README.md) · [Parte 3 · kubectl ➡️](parte-03-kubectl.md)
