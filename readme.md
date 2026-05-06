# Recopilador Masivo de Expedientes CONEX

Herramienta de recopilación masiva de expedientes y documentos urbanísticos del Ayuntamiento de Madrid a través de la API de CONEX (Consulta de Expedientes Online).

## 📋 Descripción

Este proyecto automatiza la descarga de expedientes urbanísticos del Ayuntamiento de Madrid, permitiendo obtener de forma masiva todos los documentos asociados a expedientes por calle. Utiliza procesamiento concurrente para optimizar el tiempo de descarga y proporciona una estructura de almacenamiento organizada.

**Características principales:**
- ✅ Descarga masiva de expedientes por calle
- ✅ Descarga automática de todos los documentos asociados (PDFs, imágenes, etc.)
- ✅ Procesamiento concurrente (multihilo)
- ✅ Reintentos automáticos ante fallos de conexión
- ✅ Estructura de carpetas organizada por calle y referencia
- ✅ Caché inteligente para evitar descargas duplicadas
- ✅ Logging detallado del proceso
- ✅ Gestión segura del token de autorización

## 📦 Estructura del Proyecto

```
.
├── src/
│   ├── main.py              # Script principal
│   ├── viewer.py            # Visor HTML
│   ├── viewer.html          # Interfaz web
│   ├── calles_in.txt        # Lista de calles a procesar
│   └── output/              # Carpeta con expedientes descargados
│       └── {TIPO}_{CALLE}/
│           └── {REFERENCIA}/
│               ├── expediente.json
│               └── [documentos descargados]
├── postman/
│   └── CONEX_API.postman_collection.json
├── LICENSE.txt
└── readme.md
```

## 🔧 Requisitos

- Python 3.8+
- Conexión a Internet
- Token de autorización de CONEX (sesión activa en el navegador)

## 📥 Instalación

1. Clonar o descargar el repositorio
2. No hay dependencias externas adicionales más allá de la librería `requests` (incluida en Python)

```bash
# Opcionalmente, crear un entorno virtual
python3 -m venv venv
source venv/bin/activate  # En macOS/Linux
# venv\Scripts\activate  # En Windows
```

## ⚙️ Configuración

### 1. Obtener el Bearer Token

El token se obtiene de tu navegador mientras usas CONEX:

1. Abre el navegador y accede a CONEX: https://servayto.madrid.es/CONEX_FTCONSULTAEXP/#/
2. Inicia sesión con tus credenciales
3. Abre las herramientas de desarrollador (F12 o Click derecho → Inspeccionar)
4. Ve a la pestaña **Network**
5. Realiza una búsqueda cualquiera
6. Busca una solicitud a `expedientes/query`
7. En los Headers, copia el valor de `Authorization` (sin la palabra "Bearer ")

### 2. Configurar el Token

**Opción A: Variable de entorno (recomendado)**
```bash
export CONEX_TOKEN="tu_token_aqui"
python3 src/main.py
```

**Opción B: Editar directamente en el código**
Modifica en `src/main.py`:
```python
CTE_BEARER_TOKEN = "tu_token_aqui"
```

### 3. Lista de Calles

Edita el archivo `src/calles_in.txt` con el formato:
```
CL|NOMBRE_CALLE
AV|NOMBRE_AVENIDA
```

Puedes obtener el callejero del Ayuntamiento: https://www.madrid.es/portales/munimadrid/es/Inicio/Vivienda-urbanismo-y-obras/Callejero-Municipal/

### 4. Ajustar Paralelismo (opcional)

En `src/main.py`, modifica según los límites de la API:
```python
CTE_WORKERS_CALLES = 4      # Calles procesadas en paralelo
CTE_WORKERS_DOCS = 6         # Documentos por expediente en paralelo
```

## 🚀 Cómo Usar

1. Configura el token y la lista de calles (ver sección **Configuración**)
2. Ejecuta el script:

```bash
cd src
python3 main.py
```

3. El script creará la estructura de carpetas en `output/` con los expedientes descargados
4. Opcionalmente, visualiza los resultados con el visor:

```bash
python3 viewer.py
```

Luego abre http://localhost:8000 en tu navegador.

## 📊 Estructura de Salida

Los expedientes se descargan en esta estructura:

```
output/
├── CL_NOMBRE_CALLE/
│   ├── 350-2024-12345/
│   │   ├── expediente.json      # Metadatos del expediente
│   │   ├── Documento_1.pdf
│   │   ├── Documento_2.pdf
│   │   └── ...
│   └── 350-2024-12346/
│       └── ...
└── AV_NOMBRE_AVENIDA/
    └── ...
```

- **expediente.json**: Contiene metadatos del expediente (fechas, estado, etc.)
- **Documentos**: PDFs y otros archivos asociados al expediente

## 🔗 Referencias Útiles

- **CONEX**: https://servayto.madrid.es/CONEX_FTCONSULTAEXP/#/
- **Callejero de Madrid**: https://www.madrid.es/portales/munimadrid/es/Inicio/Vivienda-urbanismo-y-obras/Callejero-Municipal/
- **Visor Urbanístico**: https://www.madrid.es/go/VisorUrbanistico

## 👥 Autores

- Alfonso Soria Muñoz
- Tecnosor © 2026

## 📄 Licencia

MIT License