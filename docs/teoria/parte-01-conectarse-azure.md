# Teoría · Parte 1 · Conectarte a Azure

[🏠 Índice de teoría](README.md) · [📋 Ir a la Parte 1 de la guía](../../GUIA-LABORATORIO.md#parte-1--conectarte-a-azure) · [⬅️ Parte 0](parte-00-preparar-equipo.md) · [Parte 2 ➡️](parte-02-terraform.md)

En esta parte el estudiante conoce la **estructura de Azure**: identidad (Entra ID), jerarquía de recursos
(tenant → suscripción → grupo de recursos), el plano de control (Azure Resource Manager) y los límites de capacidad
(cuotas). Son decisiones que un arquitecto toma **antes** de crear el primer recurso.

---

## 1.1 Iniciar sesión

[↩️ Volver al paso 1.1 de la guía](../../GUIA-LABORATORIO.md#11-iniciar-sesión)

**🎯 En una frase:** demostramos a Azure quiénes somos para que cada comando posterior se ejecute con nuestra identidad
y permisos.

**📚 Teoría**

- **Microsoft Entra ID** (antes Azure Active Directory) es el servicio de identidad de Azure.
  - Cada organización tiene un **tenant**: un directorio con sus usuarios, grupos, aplicaciones e identidades.
- `az login` usa el protocolo **OAuth 2.0 / OpenID Connect**.
  - Te autenticas en el navegador, donde pueden aplicarse **MFA** y **Acceso Condicional**.
  - La CLI recibe **tokens de acceso** de corta duración y los guarda en tu perfil (`~/.azure`).
- Cada llamada posterior a Azure lleva ese token. Azure lo valida y luego decide **qué puedes hacer** con
  **Azure RBAC**.
- **Autenticación y autorización son dos pasos distintos:**
  - Autenticación: *¿quién eres?* (Entra ID).
  - Autorización: *¿qué puedes hacer?* (RBAC).

**⚙️ Qué hiciste y qué pasó:**
- Se abrió el navegador, iniciaste sesión y la CLI listó las suscripciones a las que tienes acceso.
- Si tu organización exige MFA y la sesión expira, verás el error `AADSTS50078`: es Acceso Condicional pidiéndote
  revalidar.

**☁️ Conceptos core:** Microsoft Entra ID · tenant · OAuth 2.0 · MFA y Acceso Condicional · token de acceso.

**🏗️ Mirada de arquitecto:**
- **Humanos y automatización usan identidades distintas.** Las personas usan su cuenta con MFA. Los pipelines y las
  aplicaciones usan **identidades de carga de trabajo**: service principals o, mejor aún, **managed identities**, sin
  contraseñas. Lo verás en la Parte 2, con la identidad del cluster.
- **Ojo con mezclar identidades.** En este laboratorio, una laptop con variables `ARM_CLIENT_ID` de un service
  principal hizo que Terraform usara esa identidad en lugar de la del usuario (ver
  [teoría 2.2](parte-02-terraform.md#22-indicarle-a-terraform-con-qué-cuenta-trabajar)).

**🔗 Para aprender más**
- [Iniciar sesión con Azure CLI](https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli)
- [Qué es Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/fundamentals/whatis)
- [Qué es el Acceso Condicional](https://learn.microsoft.com/en-us/entra/identity/conditional-access/overview)

---

## 1.2 Elegir la suscripción del laboratorio

[↩️ Volver al paso 1.2 de la guía](../../GUIA-LABORATORIO.md#12-elegir-la-suscripción-del-laboratorio)

**🎯 En una frase:** indicamos en qué **suscripción** (y, por lo tanto, en qué cuenta de facturación y con qué límites)
se crearán los recursos.

**📚 Teoría:** la jerarquía de organización de Azure:

```
Tenant (Entra ID)
└── Management groups      ← gobierno a escala: políticas y permisos heredados
    └── Subscriptions      ← límite de facturación, de cuotas y de acceso
        └── Resource groups   ← contenedor lógico con ciclo de vida común
            └── Resources     ← VMs, AKS, ACR, bases de datos...
```

- Una **suscripción** es a la vez:
  - **unidad de facturación:** los costos se agrupan por suscripción;
  - **límite de escala:** las cuotas son por suscripción y región;
  - **límite de acceso:** los permisos se asignan y heredan hacia abajo.
- Una misma persona puede tener acceso a suscripciones de **varios tenants**. Por eso un `az account list` puede
  mostrar suscripciones de distintas organizaciones.
- `az account set` cambia la **suscripción por defecto** de la CLI. Todos los comandos siguientes la usan.

**⚙️ Qué hiciste y qué pasó:** listaste tus suscripciones, elegiste la del laboratorio y la confirmaste con
`az account show`.

**☁️ Conceptos core:** jerarquía de recursos · suscripción como límite de facturación, escala y acceso · herencia de RBAC y Policy.

**🏗️ Mirada de arquitecto:** en el diseño de una **landing zone** (Cloud Adoption Framework), las suscripciones se usan
para separar ambientes (prod / no-prod), cargas de trabajo y equipos. Un error común es crear recursos en la
suscripción equivocada; por eso este paso siempre termina con una verificación explícita.

**🔗 Para aprender más**
- [Organizar recursos de Azure (management groups, suscripciones, resource groups)](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-setup-guide/organize-resources)
- [Qué es una landing zone de Azure](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/)
- [Administrar suscripciones con Azure CLI](https://learn.microsoft.com/en-us/cli/azure/manage-azure-subscriptions-azure-cli)

---

## 1.3 Registrar los proveedores de recursos

[↩️ Volver al paso 1.3 de la guía](../../GUIA-LABORATORIO.md#13-registrar-los-proveedores-de-recursos)

**🎯 En una frase:** habilitamos en la suscripción los servicios de Azure que vamos a usar.

**📚 Teoría**

- **Azure Resource Manager (ARM)** es el plano de control de Azure: toda petición (portal, CLI, Terraform) pasa por
  ARM, que la autentica, la autoriza, aplica Azure Policy y la envía al servicio correspondiente.
- Cada servicio se expone mediante un **resource provider**, identificado por un *namespace*:

| Namespace | Servicio | Para qué lo usamos |
|---|---|---|
| `Microsoft.ContainerService` | AKS | El cluster de Kubernetes |
| `Microsoft.ContainerRegistry` | ACR | El registro privado de imágenes |
| `Microsoft.OperationalInsights` | Log Analytics | Almacenar logs y métricas |
| `Microsoft.OperationsManagement` | Soluciones de monitoreo | Container Insights |

- Para usar un proveedor, la suscripción debe estar **registrada** en él. Muchas suscripciones nuevas no tienen todos
  registrados y el despliegue falla con `MissingSubscriptionRegistration`.

**⚙️ Qué hiciste y qué pasó:** `az provider register` pidió el registro (es una operación asíncrona) y `az provider list`
confirmó el estado `Registered`.

**☁️ Conceptos core:** Azure Resource Manager · resource providers y tipos de recurso · operaciones asíncronas.

**🏗️ Mirada de arquitecto:** el registro de proveedores también es una herramienta de **gobierno**: en ambientes
regulados se habilitan solo los servicios aprobados. Junto con **Azure Policy** ("solo estas regiones", "solo estos SKUs")
forma las barandas (*guardrails*) de una landing zone.

**🔗 Para aprender más**
- [Qué es Azure Resource Manager](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/overview)
- [Resource providers y tipos de recurso](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-providers-and-types)
- [Qué es Azure Policy](https://learn.microsoft.com/en-us/azure/governance/policy/overview)

---

## 1.4 Verificar la cuota de máquinas virtuales

[↩️ Volver al paso 1.4 de la guía](../../GUIA-LABORATORIO.md#14-verificar-la-cuota-de-máquinas-virtuales)

**🎯 En una frase:** confirmamos que la suscripción **puede** crear las máquinas virtuales que necesita el cluster.

**📚 Teoría**

- Los nodos de AKS son **máquinas virtuales**. Azure limita cuántas vCPU puedes usar con **cuotas** por suscripción
  y región, en dos niveles:
  - **Total Regional vCPUs:** todas las VMs de la región sumadas.
  - **Por familia de VM**, por ejemplo *Standard DSv5 Family vCPUs*.
- Cómo se lee un tamaño de VM, `Standard_D2s_v5`:

| Parte | Significado |
|---|---|
| `D` | Familia de propósito general |
| `2` | 2 vCPU |
| `s` | Soporta discos Premium SSD |
| `v5` | Generación del hardware |

- Además de la cuota, un tamaño puede tener **restricciones** en tu suscripción:
  - **Location:** el tamaño no se puede usar en toda la región.
  - **Zone:** solo algunas zonas de disponibilidad no lo permiten.

**⚙️ Qué hiciste y qué pasó:** consultaste el uso y el límite de vCPU en `eastus2`. El cluster necesita 4 vCPU al inicio
(2 nodos × 2) y hasta 8 si el autoscaler crece a 4 nodos.

**☁️ Conceptos core:** cuotas y límites de suscripción · familias y tamaños de VM · regiones y zonas de disponibilidad.

**🏗️ Mirada de arquitecto:**
- **Las cuotas son parte del diseño de capacidad.** Una solución con autoscaling que choca con la cuota deja de
  escalar justo cuando más se necesita.
- **Planifica y pide los aumentos con anticipación**, sobre todo en eventos de alta demanda.
- **Caso real de este laboratorio:** la suscripción tenía cuota 0 en DSv5. Por eso usamos DSv4, cuya restricción era
  solo **por zona** y no aplicaba porque no usamos zonas.

**🔗 Para aprender más**
- [Cuotas de Azure: visión general](https://learn.microsoft.com/en-us/azure/quotas/quotas-overview)
- [Convenciones de nombres de los tamaños de VM](https://learn.microsoft.com/en-us/azure/virtual-machines/vm-naming-conventions)
- [Regiones y zonas de disponibilidad](https://learn.microsoft.com/en-us/azure/reliability/availability-zones-overview)

---

[⬅️ Parte 0 · Preparar tu equipo](parte-00-preparar-equipo.md) · [🏠 Índice](README.md) · [Parte 2 · Terraform ➡️](parte-02-terraform.md)
