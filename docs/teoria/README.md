# Teoría del laboratorio · Explicación paso a paso

Esta carpeta es el **compañero teórico** de la [Guía del laboratorio](../../GUIA-LABORATORIO.md). La guía dice **qué
ejecutar**; estas páginas explican **por qué**: la teoría detrás de cada paso, qué ocurrió por dentro al ejecutarlo,
qué conceptos core de Azure y Kubernetes se usaron y dónde profundizar.

Hay **una página por cada Parte** de la guía y, dentro de ella, **una sección por cada punto** (0.1, 0.2…). En la guía,
cada punto tiene un enlace **📘 Teoría del punto X.Y** que lleva directo a su explicación, y cada explicación tiene un
enlace **↩️ Volver** al paso correspondiente.

## Cómo está organizada cada explicación

| Bloque | Contenido |
|---|---|
| 🎯 **En una frase** | La idea del paso en una línea |
| 📚 **Teoría** | Los conceptos necesarios para entender el paso |
| ⚙️ **Qué hiciste y qué pasó** | Lo que ocurrió por dentro (Azure, Terraform, Kubernetes) al ejecutar los comandos |
| ☁️ **Conceptos core** | Lista de conceptos de Azure / Kubernetes que se usaron |
| 🏗️ **Mirada de arquitecto** | Cómo se aplica en un diseño real de producción y qué decisiones implica |
| 🔗 **Para aprender más** | Documentación oficial (Microsoft Learn, Kubernetes, HashiCorp) para profundizar |

## Índice

| Parte | Página | Puntos | Conceptos principales |
|---|---|---|---|
| 0 | [Preparar tu equipo](parte-00-preparar-equipo.md) | 0.1 – 0.5 | Shells, Azure CLI, Terraform, kubectl, Git, políticas de ejecución |
| 1 | [Conectarte a Azure](parte-01-conectarse-azure.md) | 1.1 – 1.4 | Entra ID, jerarquía de recursos, Azure Resource Manager, resource providers, cuotas |
| 2 | [Crear la infraestructura con Terraform](parte-02-terraform.md) | 2.1 – 2.7 | IaC, autenticación, providers, plan y estado, AKS, ACR, node resource group, RBAC |
| 3 | [Conectar kubectl al cluster](parte-03-kubectl.md) | 3.1 – 3.4 | kubeconfig, nodos, taints y tolerations, componentes del cluster |
| 4 | [Copiar las imágenes al ACR](parte-04-acr.md) | 4.1 – 4.2 | Imágenes OCI, registros, importación, AcrPull, cadena de suministro |
| 5 | [Desplegar la tienda pieza por pieza](parte-05-tienda.md) | 5.1 – 5.6 | Modelo declarativo, namespaces, cuotas, StatefulSet, Deployment, Services, probes, Load Balancer, DNS |
| 6 | [Desplegar el backoffice](parte-06-backoffice.md) | 6 | Arquitectura orientada a eventos, workers, bases de datos en Kubernetes vs. PaaS |
| 7 | [Aplicar Network Policies](parte-07-network-policies.md) | 7.1 – 7.3 | Modelo de red plano, NetworkPolicy, Cilium/eBPF, Zero Trust |
| 8 | [Construir tu versión personalizada](parte-08-build.md) | 8.1 | Dockerfile multi-etapa, ACR Tasks, imágenes inmutables, CI |
| 9 | [Rolling update y rollback](parte-09-rolling-update.md) | 9.1 – 9.5 | SLI/SLO, rolling update, terminación de pods, revisiones, drift, GitOps |
| 10 | [Validación punto a punto](parte-10-validacion.md) | 10 | Smoke tests, validación por capas, puertas de calidad |
| 11 | [Experimentos](parte-11-experimentos.md) | 11.1 – 11.7 | Reconciliación, escalado, admisión, HPA, DNS, diagnóstico, Container Insights |
| 12 | [Limpieza](parte-12-limpieza.md) | 12.1 – 12.3 | Borrado en cascada, destroy, costos, verificación |

## Otros documentos de apoyo

- [01 · Mini intro a Kubernetes](../01-intro-kubernetes.md): fundamentos y chuleta de `kubectl`.
- [02 · AKS para arquitectos](../02-aks-para-arquitectos.md): decisiones de diseño y checklist demo → producción.
- [03 · Los scripts, explicados](../03-scripts-explicados.md): qué hace cada script y su equivalente manual.
