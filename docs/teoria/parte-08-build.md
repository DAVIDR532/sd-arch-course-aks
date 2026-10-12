# Teoría · Parte 8 · Construir tu versión personalizada de la tienda

[🏠 Índice de teoría](README.md) · [📋 Ir a la Parte 8 de la guía](../../GUIA-LABORATORIO.md#parte-8--construir-tu-versión-personalizada-de-la-tienda) · [⬅️ Parte 7](parte-07-network-policies.md) · [Parte 9 ➡️](parte-09-rolling-update.md)

Hasta aquí usamos imágenes construidas por otros. Ahora el estudiante hace lo que hace un equipo de desarrollo:
**cambia el código y produce una imagen nueva**, como lo haría la etapa de *build* de un pipeline de integración
continua (CI).

---

## 8.1 Compilar la imagen

[↩️ Volver al paso 8.1 de la guía](../../GUIA-LABORATORIO.md#81-compilar-la-imagen)

**🎯 En una frase:** modificamos el código de la tienda y compilamos una imagen nueva **en Azure**, sin Docker en el equipo.

**📚 Teoría**

**1. Dockerfile y build multi-etapa**

El [Dockerfile del store-front](https://github.com/Azure-Samples/aks-store-demo/blob/2.2.0/src/store-front/Dockerfile)
tiene dos etapas:

```
Etapa 1 "builder" (node:alpine)          Etapa 2 "runner" (nginx:alpine-slim)
  npm install                              copia SOLO /dist (archivos estáticos)
  npm run build  ──── genera /dist ────►   copia nginx.conf
                                           imagen final: pequeña, sin Node ni código fuente
```

El *multi-stage build* produce imágenes más **pequeñas** (descargas más rápidas) y más **seguras** (menos software =
menos vulnerabilidades).

**2. ACR Tasks: compilar en la nube**

`az acr build` ejecuta una *quick task*:

1. comprime y **sube el código fuente** (el *contexto*) al ACR;
2. un agente gestionado por Azure ejecuta el Dockerfile;
3. **publica** la imagen en el registro con el tag indicado.

No necesitas Docker instalado y el build ocurre cerca del registro. Las ACR Tasks también pueden dispararse solas ante
un *commit* en Git o cuando se actualiza la imagen base, por ejemplo con un parche de seguridad de `nginx`.

**3. Build arguments**

`--build-arg APP_VERSION=2.2.0-ana` pasa un valor al build. El Dockerfile lo graba en la configuración de nginx y el
endpoint `/health` lo devuelve. Así se puede comprobar **qué versión está corriendo** sin entrar al cluster.

**4. Imágenes inmutables y tags únicos**

No modificamos la imagen `2.2.0`: creamos **otra** (`2.2.0-ana`).
- Ambas versiones conviven en el registro.
- Por eso el **rollback** de la Parte 9 es instantáneo: la versión anterior sigue disponible.

**⚙️ Qué hiciste y qué pasó**

1. El script clonó el código oficial en la versión `2.2.0`.
2. Cambió tres cosas: el `<title>` de `index.html`, el nombre junto al logo y el color de la barra en `TopNav.vue`.
3. Envió el código al ACR.
4. El ACR ejecutó el build (~1 minuto) y publicó `aks-store-demo/store-front:<tu-tag>`.

📖 [Detalle del script, paso a paso](../03-scripts-explicados.md#02-build-storefront--construir-una-imagen-personalizada-en-azure).

**☁️ Conceptos core:** Dockerfile · build multi-etapa · ACR Tasks · build arguments · imágenes inmutables · CI.

**🏗️ Mirada de arquitecto**

- **Separar build y deploy.** Este paso **solo construye**. Desplegar es otro paso (Parte 9). En un pipeline real:

```
commit ─► CI: build + tests + escaneo de vulnerabilidades ─► imagen en ACR (tag = versión/commit)
                                                               │
                                       CD: actualizar el tag en el YAML ─► despliegue ─► smoke test
```

- **Cadena de suministro.** Escanear las imágenes (**Defender for Containers**), firmarlas (Notation) y permitir en el
  cluster solo imágenes de registros aprobados (**Azure Policy**).
- **Imágenes base.** Usar imágenes base pequeñas y mantenidas, y reconstruir automáticamente cuando reciben parches
  (triggers de imagen base de ACR Tasks).

**🔗 Para aprender más**
- [ACR Tasks: visión general](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-tasks-overview)
- [Tutorial: build en la nube con az acr build (quick task)](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-tutorial-quick-task)
- [Builds multi-etapa en Docker](https://docs.docker.com/build/building/multi-stage/)
- [Microsoft Defender for Containers](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-introduction)
- [CI/CD hacia AKS con GitHub Actions](https://learn.microsoft.com/en-us/azure/aks/kubernetes-action)

---

[⬅️ Parte 7 · Network Policies](parte-07-network-policies.md) · [🏠 Índice](README.md) · [Parte 9 · Rolling update ➡️](parte-09-rolling-update.md)
