import json
import logging
import os
import re
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------
CTE_ARCHIVO_IN      = "calles_in.txt"
CTE_DIRECTORIO_OUT  = "output"
# El token se puede pasar como variable de entorno CONEX_TOKEN o editando esta línea
CTE_BEARER_TOKEN    = os.environ.get(
    "CONEX_TOKEN",
    "este_token_se_obtiene_desde_tu_navegador_inspeccionando_elemento_mientras_usas_conex_reemplazalo",
)

# Número de calles procesadas en paralelo (ajusta según límites de la API)
CTE_WORKERS_CALLES  = 4
# Documentos descargados en paralelo dentro de cada expediente
CTE_WORKERS_DOCS    = 6

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------
def _safe_name(text: str) -> str:
    """Convierte un texto en un nombre válido para fichero/carpeta."""
    return re.sub(r'[\\/:*?"<>|]', '_', str(text)).strip()


def _build_session(token: str) -> requests.Session:
    """Crea una sesión HTTP con pool de conexiones y reintentos automáticos."""
    session = requests.Session()
    session.headers.update({"Authorization": f"Bearer {token}"})
    retry = Retry(
        total=3,
        backoff_factor=1,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET"],
    )
    adapter = HTTPAdapter(
        max_retries=retry,
        pool_connections=20,
        pool_maxsize=20,
    )
    session.mount("https://", adapter)
    return session


# ---------------------------------------------------------------------------
# Capa de acceso a la API CONEX
# ---------------------------------------------------------------------------
class ConexApiService:
    _BASE = "https://servayto.madrid.es/CONEX_RSCONSULTAEXP/api_rsconsultaexp/v1/expedientes/"

    def __init__(self, session: requests.Session):
        self._session = session

    def get_expedientes_calle(self, tipo: str, nombre: str) -> list:
        params = {
            "tipo": tipo, "nombre": nombre,
            "numeroDesde": "", "numeroHasta": "",
            "escalera": "", "planta": "", "puerta": "", "fechaAlta": "",
        }
        r = self._session.get(f"{self._BASE}query", params=params, timeout=30)
        r.raise_for_status()
        return r.json().get("listaExpedientes", [])

    def get_detalle(self, codigo_interno: str) -> dict:
        r = self._session.get(f"{self._BASE}{codigo_interno}", timeout=30)
        r.raise_for_status()
        return r.json()

    def get_documentos(self, codigo_interno: str) -> list:
        r = self._session.get(f"{self._BASE}{codigo_interno}/documentos", timeout=30)
        r.raise_for_status()
        return r.json()

    def descargar_documento(self, codigo_interno: str, codigo_doc: str) -> bytes:
        r = self._session.get(
            f"{self._BASE}{codigo_interno}/documentos/{codigo_doc}/descarga",
            timeout=60,
        )
        r.raise_for_status()
        return r.content


# ---------------------------------------------------------------------------
# Capa de persistencia
# ---------------------------------------------------------------------------
class GuardadorDeDocumentos:
    """
    Estructura de carpetas generada:
        output/
            {TIPO}_{CALLE}/
                {REFERENCIA}/
                    expediente.json
                    {DESCRIPCION}.{ext}
                    ...
    """

    def __init__(self, directorio_base: str):
        self._base = Path(directorio_base)
        self._base.mkdir(parents=True, exist_ok=True)

    def _carpeta_expediente(self, tipo: str, calle: str, referencia: str) -> Path:
        carpeta = self._base / f"{tipo}_{_safe_name(calle)}" / _safe_name(referencia)
        carpeta.mkdir(parents=True, exist_ok=True)
        return carpeta

    def expediente_ya_descargado(self, tipo: str, calle: str, referencia: str) -> bool:
        """Devuelve True si el expediente ya fue descargado completamente."""
        carpeta = self._base / f"{tipo}_{_safe_name(calle)}" / _safe_name(referencia)
        return (carpeta / "expediente.json").exists()

    def guardar_expediente(self, carpeta: Path, proyecto_info: dict):
        ruta = carpeta / "expediente.json"
        with ruta.open("w", encoding="utf-8") as f:
            json.dump(proyecto_info, f, ensure_ascii=False, indent=2)

    def guardar_documento(self, carpeta: Path, documento_info: dict, binario: bytes):
        descripcion = _safe_name(documento_info["descripcion"])
        ext = documento_info["tipo"].lower()
        ruta = carpeta / f"{descripcion}.{ext}"
        # Evita colisión de nombres añadiendo el código del documento
        if ruta.exists():
            ruta = carpeta / f"{descripcion}_{documento_info['codigoDoc']}.{ext}"
        ruta.write_bytes(binario)

    def get_carpeta(self, tipo: str, calle: str, referencia: str) -> Path:
        return self._carpeta_expediente(tipo, calle, referencia)


# ---------------------------------------------------------------------------
# Lógica de procesado
# ---------------------------------------------------------------------------
def _procesar_expediente(
    api: ConexApiService,
    guardador: GuardadorDeDocumentos,
    tipo: str,
    calle: str,
    expediente: dict,
):
    codigo_interno = expediente["codigoInterno"]
    referencia = str(expediente["referencia"]).replace("/", "-")

    if guardador.expediente_ya_descargado(tipo, calle, referencia):
        log.debug("Omitido (ya descargado): %s / %s", calle, referencia)
        return

    carpeta = guardador.get_carpeta(tipo, calle, referencia)
    try:
        proyecto_info = api.get_detalle(codigo_interno)
        guardador.guardar_expediente(carpeta, proyecto_info)

        documentos = api.get_documentos(codigo_interno)

        # Descarga de documentos en paralelo
        with ThreadPoolExecutor(max_workers=CTE_WORKERS_DOCS) as pool_docs:
            futures = {
                pool_docs.submit(api.descargar_documento, codigo_interno, doc["codigoDoc"]): doc
                for doc in documentos
            }
            for fut in as_completed(futures):
                doc = futures[fut]
                try:
                    guardador.guardar_documento(carpeta, doc, fut.result())
                except Exception as exc:
                    log.warning(
                        "Error al descargar doc %s de %s: %s",
                        doc["codigoDoc"], codigo_interno, exc,
                    )

        log.info("  ✓ %s / %s  (%d docs)", calle, referencia, len(documentos))
    except Exception as exc:
        log.error("Error en expediente %s (%s %s): %s", codigo_interno, tipo, calle, exc)


def _procesar_calle(
    api: ConexApiService,
    guardador: GuardadorDeDocumentos,
    tipo: str,
    calle: str,
):
    try:
        expedientes = api.get_expedientes_calle(tipo, calle)
        if not expedientes:
            log.info("Sin expedientes: %s %s", tipo, calle)
            return
        log.info("%s %s → %d expedientes", tipo, calle, len(expedientes))
        for exp in expedientes:
            _procesar_expediente(api, guardador, tipo, calle, exp)
    except Exception as exc:
        log.error("Error procesando calle %s %s: %s", tipo, calle, exc)


# ---------------------------------------------------------------------------
# Punto de entrada
# ---------------------------------------------------------------------------
def main():
    session   = _build_session(CTE_BEARER_TOKEN)
    api       = ConexApiService(session)
    guardador = GuardadorDeDocumentos(CTE_DIRECTORIO_OUT)

    calles = []
    with open(CTE_ARCHIVO_IN, "r", encoding="utf-8") as f:
        for linea in f:
            linea = linea.strip()
            if linea and ";" in linea:
                tipo, nombre = linea.split(";", 1)
                calles.append((tipo.strip(), nombre.strip()))

    log.info("Procesando %d calles con hasta %d workers...", len(calles), CTE_WORKERS_CALLES)

    with ThreadPoolExecutor(max_workers=CTE_WORKERS_CALLES) as pool:
        futures = {
            pool.submit(_procesar_calle, api, guardador, tipo, nombre): (tipo, nombre)
            for tipo, nombre in calles
        }
        for fut in as_completed(futures):
            tipo, nombre = futures[fut]
            try:
                fut.result()
            except Exception as exc:
                log.error("Fallo inesperado en %s %s: %s", tipo, nombre, exc)

    log.info("Descarga completada. Archivos en: %s/", CTE_DIRECTORIO_OUT)


if __name__ == "__main__":
    main()
