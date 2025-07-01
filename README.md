# 🗳️ Veritas: Verificador de Noticias Electorales en Internet Computer con IA

## Resumen del Proyecto

**Veritas** es un **Verificador de Noticias Electorales** especializado en las próximas elecciones de Ecuador 2025. Su misión principal es combatir la desinformación al permitir a los usuarios analizar la veracidad de textos de noticias. El proyecto proporciona un análisis detallado que incluye un resumen conciso, un nivel de confianza, las fuentes consultadas, el razonamiento detrás de la verificación, el contexto relevante, la consistencia de la información y recomendaciones para el lector.

Una característica clave de Veritas es su capacidad para integrar un **motor de Inteligencia Artificial externo (Perplexity AI)** para realizar análisis profundos y contextualizados. Además, cuenta con un **mecanismo de fallback local** robusto, asegurando que la funcionalidad básica de verificación esté siempre disponible, incluso si la API externa no es accesible o falla.

## Arquitectura del Proyecto

Este proyecto está construido sobre la **Internet Computer (ICP)**, operando como una **Aplicación Descentralizada (dApp)** con una clara y eficiente separación entre el backend y el frontend.

### 1. Backend (Canister `project_backend`)

El cerebro del verificador de noticias, implementado como un canister en Motoko.

* **Tecnología:** Desarrollado en **Motoko**, el lenguaje de programación nativo de ICP optimizado para canisters.
* **Propósito:** Contiene la lógica central para la verificación de noticias:
    * **Validación de Entrada:** Gestiona la validación del texto de la noticia recibido (ej. longitud máxima de 4000 caracteres, no vacío).
    * **Integración con Perplexity AI:** Realiza **HTTP Outcalls** (llamadas HTTP salientes) para interactuar con la API externa de Perplexity AI. Envía un "prompt" cuidadosamente estructurado que instruye a la IA a actuar como un verificador de noticias especializado en las elecciones de Ecuador 2025, solicitando una respuesta en un formato JSON predefinido.
    * **Parsing de Respuesta:** Procesa y parsea la respuesta JSON de Perplexity AI, extrayendo campos como `resultado`, `confianza`, `resumen`, `fuentes_consultadas`, `evidencia`, `contexto`, `consistencia` y `recomendaciones`.
    * **Mecanismo de Fallback:** En caso de que la llamada a la API de Perplexity falle (por errores de red, autenticación, límites de tasa, etc.), el canister ejecuta una función `performLocalAnalysis` que realiza una verificación básica basada en palabras clave predefinidas. Esto garantiza que siempre se proporcione un resultado preliminar, aunque la IA externa no esté disponible.
    * **Persistencia de Estado:** Los canisters de Motoko ofrecen persistencia de estado por defecto, lo que significa que el estado interno del actor `NewsFactChecker` se mantiene de forma segura en la blockchain sin necesidad de una base de datos externa.
    * **Funciones de Utilidad:** Incluye funciones auxiliares para el manejo de cadenas (escape/unescape de JSON) y la conversión de tipos.
    * **Funciones Públicas (`Canister Methods`):**
        * `analyzeNews(newsText)`: La función principal para iniciar el proceso de verificación.
        * `greet(name)`: Una función de ejemplo para una interacción básica.
        * `getSystemInfo()`: Proporciona metadatos sobre la versión del verificador, idiomas soportados, longitud máxima de texto y el proveedor de la API.
        * `testApiConnection()`: Permite verificar la conectividad con la API de Perplexity.

### 2. Frontend (Canister `project_frontend`)

La interfaz de usuario interactiva que permite a los usuarios interactuar con el sistema.

* **Tecnología:** Desarrollado como una **Aplicación de Página Única (SPA)** utilizando **React** para la construcción de la UI dinámica, **Vite** como un bundler rápido para el desarrollo y optimización de producción, y **TypeScript** para un desarrollo robusto y escalable. Los estilos se gestionan con **SCSS**.
* **Propósito:** Ofrece una experiencia de usuario intuitiva donde los usuarios pueden ingresar el texto de una noticia y recibir un análisis visualmente atractivo y detallado. La interfaz muestra el estado de verificación, el nivel de confianza, un resumen, la evidencia, el contexto, la consistencia, las recomendaciones y enlaces a fuentes de referencia.
* **Comunicación con Backend:** Se comunica con el `project_backend` en ICP utilizando las bibliotecas `@dfinity/agent` y `@dfinity/candid`. La carpeta `declarations` contiene las interfaces Candid generadas automáticamente por DFX, facilitando esta interacción.
* **Despliegue:** La aplicación web es compilada y desplegada como un *canister de assets* en la red ICP, lo que significa que el frontend se aloja directamente en la blockchain, inherente a la descentralización y resistencia a la censura.

### 3. Herramientas y Configuraciones Clave

* **DFX (`dfx.json`):** La herramienta de línea de comandos oficial del Internet Computer SDK. Gestiona el ciclo de vida de los canisters (creación, despliegue, llamadas a funciones) y automatiza la generación de las interfaces Candid. El archivo `dfx.json` define los dos canisters del proyecto y sus configuraciones específicas para el entorno local.
* **NPM (`package.json`, `package-lock.json`):** Utilizado para la gestión de dependencias de Node.js en el proyecto raíz y en el subproyecto `project_frontend`. Define scripts para construcción (`build`), inicio (`start`), y otras tareas.
* **Vite (`vite.config.js`):** Configuración para Vite, optimizando el proceso de desarrollo y la compilación final del frontend.


CANISTER ID
Created a wallet canister on the "local" network for user "icp_hub" with ID "uqqxf-5h777-77774-qaaaa-cai" project_backend canister created with canister id: uxrrr-q7777-77774-qaaaq-cai project_frontend canister created with canister id: u6s2n-gx777-77774-qaaba-cai

## Diagrama Conceptual de Arquitectura

```mermaid
+-------------------+       +-------------------+
|                   |       |                   |
|   Usuario Final   |<----->|     Frontend      |
|                   |       |  (React/Vite/TS)  |
+-------------------+       +-------------------+
                                     |
                                     | (Candid Interface / @dfinity/agent)
                                     V
+-------------------------------------------------+
|             Internet Computer (ICP)             |
|-------------------------------------------------|
|   +-------------------+     +-----------------+ |
|   |                   |<--->|                 | |
|   |  Canister Backend |     |   Canister de   | |
|   |  (Motoko: NewsFactChecker) |   Assets (Frontend)| |
|   |                   |     |                 | |
|   +-------------------+     +-----------------+ |
|            |                                    |
|            | (HTTP Outcalls)                    |
|            V                                    |
|   +-----------------------+                    |
|   |                       |                    |
|   |  Perplexity AI API    |                    |
|   |  (Servicio externo de IA) |                    |
|   |                       |                    |
|   +-----------------------+                    |
+-------------------------------------------------+