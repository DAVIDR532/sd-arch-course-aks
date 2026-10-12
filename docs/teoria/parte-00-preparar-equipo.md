# Teoría · Parte 0 · Preparar tu equipo

[🏠 Índice de teoría](README.md) · [📋 Ir a la Parte 0 de la guía](../../GUIA-LABORATORIO.md#parte-0--preparar-tu-equipo-una-sola-vez) · [Siguiente: Parte 1 ➡️](parte-01-conectarse-azure.md)

Antes de tocar Azure, el estudiante prepara su **estación de trabajo de ingeniería de nube**: una terminal, cuatro
herramientas de línea de comandos y el código del laboratorio. Parece trámite, pero aquí aparecen ideas que un
arquitecto usa todos los días: automatización por línea de comandos, gestores de paquetes, control de versiones y
políticas de ejecución.

---

## 0.1 Abrir la terminal correcta

[↩️ Volver al paso 0.1 de la guía](../../GUIA-LABORATORIO.md#01-abrir-la-terminal-correcta)

**🎯 En una frase:** la terminal es el lugar desde donde le daremos órdenes a Azure y a Kubernetes; usamos la misma
experiencia en Windows, macOS y Linux.

**📚 Teoría**

- Una **terminal** es la ventana; el **shell** es el programa que interpreta lo que escribes (PowerShell, Bash, zsh).
- **PowerShell 7** (`pwsh`) es la versión moderna y multiplataforma de PowerShell, basada en .NET. La que viene con
  Windows, **Windows PowerShell 5.1**, solo recibe mantenimiento y se comporta distinto en varios comandos web y de
  codificación de texto. Por eso la guía exige la 7.
- **Bash** es el shell estándar en Linux y existe en macOS (que usa zsh por defecto, compatible para estos comandos).
  En Windows se puede usar Bash con **WSL** (un Linux real dentro de Windows) o **Git Bash**.
- Todo lo que hacemos en el portal de Azure se puede hacer por línea de comandos. Eso permite **repetir, documentar y
  automatizar**, que es la base de DevOps.

**⚙️ Qué hiciste y qué pasó:** abriste el shell adecuado y verificaste con `$PSVersionTable` la versión de PowerShell.
Esa variable automática describe el motor que estás ejecutando.

**☁️ Conceptos core:** interfaz de línea de comandos (CLI) · automatización · paridad entre sistemas operativos.

**🏗️ Mirada de arquitecto:** en un equipo real, los mismos comandos que ejecutas a mano terminan dentro de un
**pipeline** (GitHub Actions, Azure DevOps). Si un procedimiento solo existe como "clics en el portal", no se puede
auditar ni repetir. Una regla útil: *si lo hiciste dos veces a mano, automatízalo*.

**🔗 Para aprender más**
- [¿Qué es PowerShell?](https://learn.microsoft.com/en-us/powershell/scripting/overview)
- [Diferencias entre Windows PowerShell 5.1 y PowerShell 7](https://learn.microsoft.com/en-us/powershell/scripting/whats-new/differences-from-windows-powershell)
- [¿Qué es WSL (Subsistema de Windows para Linux)?](https://learn.microsoft.com/en-us/windows/wsl/about)

---

## 0.2 Instalar las herramientas

[↩️ Volver al paso 0.2 de la guía](../../GUIA-LABORATORIO.md#02-instalar-las-herramientas)

**🎯 En una frase:** instalamos las cuatro herramientas con las que construiremos y operaremos la solución.

**📚 Teoría**

| Herramienta | Qué es | Con quién habla |
|---|---|---|
| **Azure CLI** (`az`) | Cliente de línea de comandos de Azure | La API de **Azure Resource Manager** (REST sobre HTTPS) |
| **Terraform** | Herramienta de **Infraestructura como Código** (IaC) de HashiCorp | Azure, a través del *provider* `azurerm` |
| **kubectl** | Cliente oficial de Kubernetes | El **API server** del cluster |
| **git** | Sistema de control de versiones distribuido | Repositorios como GitHub |

- Un **gestor de paquetes** (`winget` en Windows, Homebrew en macOS, `apt` en Ubuntu/Debian) descarga, instala y
  actualiza software desde un catálogo confiable, sin buscar instaladores a mano.
- Las tres primeras herramientas son, en el fondo, **clientes de APIs**: cada comando se traduce en llamadas HTTP
  autenticadas. El portal de Azure hace exactamente lo mismo, con una interfaz gráfica.

**⚙️ Qué hiciste y qué pasó:** el gestor de paquetes descargó los binarios y los registró en el `PATH` del sistema
(la lista de carpetas donde el shell busca programas).

**☁️ Conceptos core:** Azure Resource Manager como "puerta de entrada" a Azure · IaC · cliente de API de Kubernetes.

**🏗️ Mirada de arquitecto:** fija versiones. Una diferencia de versión de `kubectl` frente al cluster puede cambiar
comportamientos: en este laboratorio, un `kubectl` 1.28 no entendía un campo de Kubernetes 1.35 al hacer rollback
(ver [teoría 9.4](parte-09-rolling-update.md#94-rollback)). Kubernetes soporta una diferencia de ±1 versión menor
entre `kubectl` y el cluster.

**🔗 Para aprender más**
- [Instalar Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Instalar Terraform](https://developer.hashicorp.com/terraform/install)
- [Instalar kubectl y política de versiones](https://kubernetes.io/docs/tasks/tools/)
- [Qué es winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/)

---

## 0.3 Verificar las herramientas

[↩️ Volver al paso 0.3 de la guía](../../GUIA-LABORATORIO.md#03-verificar-las-herramientas)

**🎯 En una frase:** comprobamos que el sistema operativo encuentra cada herramienta y que su versión es la adecuada.

**📚 Teoría**

- Cuando escribes `terraform`, el shell recorre las carpetas del **`PATH`** buscando un ejecutable con ese nombre. Si
  acabas de instalar algo y "no se reconoce", casi siempre es porque la terminal se abrió **antes** de la instalación
  y tiene un `PATH` viejo. Por eso la guía pide cerrar y reabrir.
- `az version --query '"azure-cli"' -o tsv` ya usa dos ideas que verás todo el laboratorio: **`--query`** (filtra la
  respuesta JSON con el lenguaje **JMESPath**) y **`-o`** (formato de salida: `json`, `table`, `tsv`).

**⚙️ Qué hiciste y qué pasó:** cada herramienta respondió con su versión, lo que demuestra que está instalada y en el `PATH`.

**☁️ Conceptos core:** variables de entorno · consultas JMESPath y formatos de salida de Azure CLI.

**🏗️ Mirada de arquitecto:** en equipos grandes este paso se elimina con **entornos estandarizados**: Azure Cloud
Shell (navegador, herramientas ya instaladas), *dev containers* o GitHub Codespaces. Todos trabajan con las mismas
versiones y desaparece el "en mi máquina sí funciona".

**🔗 Para aprender más**
- [Consultar la salida de Azure CLI con JMESPath](https://learn.microsoft.com/en-us/cli/azure/query-azure-cli)
- [Formatos de salida de Azure CLI](https://learn.microsoft.com/en-us/cli/azure/format-output-azure-cli)
- [Azure Cloud Shell](https://learn.microsoft.com/en-us/azure/cloud-shell/overview)

---

## 0.4 Descargar el repositorio

[↩️ Volver al paso 0.4 de la guía](../../GUIA-LABORATORIO.md#04-descargar-el-repositorio)

**🎯 En una frase:** traemos a tu equipo una copia completa del código del laboratorio: infraestructura, manifiestos
de Kubernetes, scripts y documentación.

**📚 Teoría**

- **Git** guarda el historial de cambios de un proyecto. **GitHub** aloja repositorios Git en la nube.
- `git clone` descarga el repositorio **con todo su historial** y deja configurado el remoto `origin` para traer
  actualizaciones con `git pull`.
- Este repositorio sigue una idea central de la nube moderna: **todo como código**. La infraestructura (`infra/`), la
  aplicación (`k8s/`) y la operación (`scripts/`) viven versionadas en el mismo lugar.
- Los repositorios pueden ser **públicos** o **privados**. En uno privado necesitas permisos y autenticarte
  (por ejemplo, con el administrador de credenciales de Git o con `gh auth login`).

**⚙️ Qué hiciste y qué pasó:** se creó la carpeta `sd-arch-course-aks` con los archivos y una carpeta oculta `.git`
que contiene el historial. Desde ahí se ejecuta el resto del laboratorio.

**☁️ Conceptos core:** control de versiones · todo como código (IaC + manifiestos + scripts) · fuente de verdad.

**🏗️ Mirada de arquitecto:** el repositorio es la **fuente de verdad**. Más adelante (Parte 9) verás qué pasa cuando
el cluster y el repositorio no coinciden (*drift*), y cómo **GitOps** usa Git como fuente de verdad para desplegar.

**🔗 Para aprender más**
- [Qué es el control de versiones (libro Pro Git)](https://git-scm.com/book/en/v2/Getting-Started-About-Version-Control)
- [Clonar un repositorio en GitHub](https://docs.github.com/en/repositories/creating-and-managing-repositories/cloning-a-repository)
- [Qué es GitOps](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/conceptual-gitops-flux2)

---

## 0.5 Permitir la ejecución de los scripts

[↩️ Volver al paso 0.5 de la guía](../../GUIA-LABORATORIO.md#05-permitir-la-ejecución-de-los-scripts)

**🎯 En una frase:** le decimos al sistema operativo que los scripts del laboratorio se pueden ejecutar.

**📚 Teoría**

- **Windows: política de ejecución.** PowerShell trae una *execution policy* que limita qué scripts pueden correr.
  - `RemoteSigned` permite los scripts creados localmente.
  - Exige firma digital a los descargados de internet. Windows los marca con el "Mark of the Web".
  - **No es un límite de seguridad:** es una protección contra ejecuciones accidentales.
  - `-Scope CurrentUser` cambia la política solo para tu usuario, sin permisos de administrador.
- **macOS/Linux: permiso de ejecución.** Un archivo necesita el permiso de ejecución (`x`) para correr como programa.
  - `chmod +x` lo agrega.
  - La primera línea del script (`#!/usr/bin/env bash`, llamada *shebang*) indica qué intérprete usar.

**⚙️ Qué hiciste y qué pasó:** en Windows cambiaste la política para tu usuario; en macOS/Linux marcaste los `.sh`
como ejecutables.

**☁️ Conceptos core:** principio de mínimo privilegio aplicado a la estación de trabajo · scripts como automatización.

**🏗️ Mirada de arquitecto:** en una empresa, estas políticas se gestionan de forma centralizada (Intune, GPO). Los
scripts de operación se firman o se ejecutan solo desde pipelines controlados, no desde laptops personales.

**🔗 Para aprender más**
- [Políticas de ejecución de PowerShell](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies)
- [Manual de chmod (permisos de archivos en Linux/macOS)](https://man7.org/linux/man-pages/man1/chmod.1.html)

---

[🏠 Índice de teoría](README.md) · [Siguiente: Parte 1 · Conectarte a Azure ➡️](parte-01-conectarse-azure.md)
