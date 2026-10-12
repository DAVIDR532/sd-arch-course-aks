# Teoría · Parte 4 · Copiar las imágenes al registro privado (ACR)

[🏠 Índice de teoría](README.md) · [📋 Ir a la Parte 4 de la guía](../../GUIA-LABORATORIO.md#parte-4--copiar-las-imágenes-al-registro-privado-acr) · [⬅️ Parte 3](parte-03-kubectl.md) · [Parte 5 ➡️](parte-05-tienda.md)

Antes de desplegar la aplicación necesitamos que sus **imágenes de contenedor** estén en un lugar confiable. Esta parte
introduce qué es una imagen, qué es un registro y por qué un arquitecto exige un **registro privado** para las cargas de
producción.

---

## 4.1 Ejecutar la importación

[↩️ Volver al paso 4.1 de la guía](../../GUIA-LABORATORIO.md#41-ejecutar-la-importación)

**🎯 En una frase:** copiamos las 10 imágenes que usa la tienda desde registros públicos de internet a nuestro Azure
Container Registry.

**📚 Teoría**

- **Imagen de contenedor:** paquete inmutable con la aplicación y todo lo que necesita (sistema base, librerías,
  binarios). Se compone de **capas** reutilizables y un **manifiesto** que las describe. El estándar es **OCI**.
- **Registro:** servidor que almacena y distribuye imágenes, como Docker Hub, GitHub Container Registry (`ghcr.io`) o
  **Azure Container Registry**.
  - Las imágenes se organizan en **repositorios** (`aks-store-demo/order-service`) y **tags** (`2.2.0`).
- **Tag vs. digest:**
  - El **tag** es una etiqueta legible que *puede moverse* a otra imagen.
  - El **digest** (`sha256:...`) identifica una imagen de forma única e inmutable.
- **`az acr import`:** copia la imagen **de registro a registro dentro de Azure**.
  - No necesita Docker ni pasa por tu equipo.
  - Copia todas las arquitecturas de la imagen (amd64, arm64…) del *manifest list*.
- **Límites de Docker Hub:** limita las descargas anónimas por IP. Por eso vimos `429 Too Many Requests` al preparar
  este laboratorio.

**⚙️ Qué hiciste y qué pasó:** el script recorrió la lista de imágenes (7 de la tienda, RabbitMQ, BusyBox y DocumentDB).
Por cada una, el ACR descargó la imagen del registro de origen y la guardó con el mismo tag. Si Docker Hub respondía
429, el script reintentó. 📖 [Detalle del script](../03-scripts-explicados.md#01-import-images--llevar-las-imágenes-al-acr).

**☁️ Conceptos core:** imágenes OCI · repositorios y tags · Azure Container Registry · importación de contenido.

**🏗️ Mirada de arquitecto: ¿por qué no usar directamente las imágenes públicas?**

| Riesgo de depender de un registro público | Cómo lo resuelve el ACR |
|---|---|
| Caída o límite de descargas (el 429 que vimos) | Las imágenes están en tu región, sin límites de terceros |
| El autor borra o cambia la imagen | Tu copia no cambia |
| Imágenes con vulnerabilidades | Escaneo con **Microsoft Defender for Containers** |
| Cualquiera puede desplegar cualquier imagen | **Azure Policy**: "solo imágenes de registros aprobados" |
| Latencia y costo de salida a internet | El ACR está junto al cluster (y con Premium: Private Link y geo-replicación) |

A este proceso de "traer y curar contenido público" se le llama *gestionar contenido de terceros*. Es una práctica de
**seguridad de la cadena de suministro**.

**🔗 Para aprender más**
- [Introducción a Azure Container Registry](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-intro)
- [Importar imágenes a un ACR](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-import-images)
- [Gestionar contenido público en un registro privado](https://learn.microsoft.com/en-us/azure/container-registry/buffer-gate-public-content)
- [SKUs de ACR (Basic, Standard, Premium)](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-skus)

---

## 4.2 Verificar

[↩️ Volver al paso 4.2 de la guía](../../GUIA-LABORATORIO.md#42-verificar)

**🎯 En una frase:** confirmamos que las 10 imágenes quedaron en el registro.

**📚 Teoría**

- El **login server** del ACR (`acrsdaksdemoxxxxx.azurecr.io`) es el prefijo de todas las imágenes. En los YAML del
  laboratorio aparece como `__ACR_LOGIN_SERVER__/aks-store-demo/order-service:2.2.0`.
- **Cómo descarga AKS sin contraseña:**
  1. el **kubelet** de cada nodo usa la identidad administrada del node pool (*kubelet identity*);
  2. pide un token a Entra ID;
  3. el ACR verifica que esa identidad tiene el rol **AcrPull** que creó Terraform.
  - Es la combinación **managed identity + RBAC**.

**⚙️ Qué hiciste y qué pasó:** `az acr repository list` mostró los 10 repositorios.

**☁️ Conceptos core:** login server · kubelet identity · AcrPull · autenticación sin secretos.

**🏗️ Mirada de arquitecto:** buenas prácticas de etiquetado:
- Tags inmutables por versión (`2.2.0`, `2.2.0-smartdata`) y **nunca** `latest` en producción.
- Con ACR Premium puedes **bloquear** tags para que no se sobrescriban.

Lo aplicarás en la Parte 8.

**🔗 Para aprender más**
- [Recomendaciones de tags y versiones de imágenes](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-image-tag-version)
- [Autenticación con ACR desde AKS](https://learn.microsoft.com/en-us/azure/aks/cluster-container-registry-integration)
- [Imágenes en Kubernetes (pull policy, digests)](https://kubernetes.io/docs/concepts/containers/images/)

---

[⬅️ Parte 3 · kubectl](parte-03-kubectl.md) · [🏠 Índice](README.md) · [Parte 5 · La tienda ➡️](parte-05-tienda.md)
