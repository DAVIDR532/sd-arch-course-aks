# Teoría · Parte 10 · Validación punto a punto

[🏠 Índice de teoría](README.md) · [📋 Ir a la Parte 10 de la guía](../../GUIA-LABORATORIO.md#parte-10--validación-punto-a-punto) · [⬅️ Parte 9](parte-09-rolling-update.md) · [Parte 11 ➡️](parte-11-experimentos.md)

**🎯 En una frase:** un solo script comprueba automáticamente que **cada eslabón** de la solución funciona, desde la
infraestructura hasta el flujo de negocio y la seguridad de red.

---

## 📚 Teoría

**1. Qué es un smoke test**

Es una prueba rápida, después de un despliegue, que responde *"¿lo esencial funciona?"*. No reemplaza las pruebas
unitarias ni de integración, pero detecta en segundos los fallos graves de un despliegue.

**2. Validar por capas**

Cada verificación prueba un concepto distinto del laboratorio:

| # | Verificación | Capa | Concepto que confirma | Teoría |
|---|---|---|---|---|
| 1 | Pods listos | Plataforma | Probes de readiness | [5.4](parte-05-tienda.md#54-product-service-y-order-service-apis) |
| 1 | Apps fuera del pool `system` | Plataforma | Taints y node pools | [3.3](parte-03-kubectl.md#33-ver-por-qué-las-apps-no-caen-en-el-nodo-system) |
| 2 | Imágenes desde el ACR | Cadena de suministro | Registro privado + AcrPull | [4.1](parte-04-acr.md#41-ejecutar-la-importación) |
| 3 | IP pública y `/health` | Red de entrada | Service LoadBalancer | [5.5](parte-05-tienda.md#55-store-front-la-tienda-web) |
| 4 | Catálogo | Servicios internos | DNS + Service ClusterIP | [5.6](parte-05-tienda.md#56-probar-la-tienda) |
| 5 | Pedido y cola | Flujo de negocio | Mensajería asíncrona | [5.6](parte-05-tienda.md#56-probar-la-tienda) |
| 6 | Backoffice | Flujo de negocio | Productor/consumidor + base de datos | [Parte 6](parte-06-backoffice.md) |
| 7 | Intruso bloqueado | Seguridad | NetworkPolicy | [7.3](parte-07-network-policies.md#73-probar-después-de-aplicar-las-políticas) |

**3. Pruebas positivas y negativas**

La mayoría de las verificaciones son **positivas** ("esto debe funcionar"). La 7 es **negativa** ("esto **no** debe
funcionar"). Los controles de seguridad se validan con pruebas negativas: un firewall que nunca se prueba bloqueando
algo no está demostrado.

**4. Código de salida**

El script termina con código **0** si todo pasa y **1** si algo falla. Así lo puede usar un pipeline como **puerta de
calidad**: si el smoke test falla, el pipeline se detiene o hace rollback automáticamente.

---

## ⚙️ Qué hiciste y qué pasó

El script hizo un recorrido completo:
- consultó la API de Kubernetes (pods, nodos, imágenes, servicios);
- hizo peticiones HTTP reales a la tienda y al portal admin;
- creó un **pedido real**;
- revisó la cola con `kubectl exec`;
- lanzó un pod intruso para probar la política de red.

📖 [Comando manual equivalente de cada verificación](../03-scripts-explicados.md#04-validate--prueba-punto-a-punto).

## ☁️ Conceptos core

Smoke test · validación por capas · pruebas positivas y negativas · códigos de salida como puertas de calidad.

## 🏗️ Mirada de arquitecto

- **Un despliegue no termina cuando el comando termina**, sino cuando se verifica que funciona. Por eso un pipeline de
  CD maduro tiene la secuencia *desplegar → validar → promover* (o *revertir*).
- **Además del smoke test puntual, producción necesita observabilidad continua:**
  - métricas y logs (Container Insights, Managed Prometheus);
  - trazas distribuidas (Application Insights / OpenTelemetry);
  - pruebas de disponibilidad sintéticas con alertas.
- **Pilar de Excelencia Operacional.** El *Azure Well-Architected Framework* agrupa estas prácticas en este pilar.

## 🔗 Para aprender más

- [Excelencia operacional (Well-Architected Framework)](https://learn.microsoft.com/en-us/azure/well-architected/operational-excellence/)
- [Monitorear AKS](https://learn.microsoft.com/en-us/azure/aks/monitor-aks)
- [Pruebas de disponibilidad en Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/availability)

---

[⬅️ Parte 9 · Rolling update](parte-09-rolling-update.md) · [🏠 Índice](README.md) · [Parte 11 · Experimentos ➡️](parte-11-experimentos.md)
