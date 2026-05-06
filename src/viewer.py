#!/usr/bin/env python3
"""Servidor local para visualizar los expedientes CONEX descargados.

Uso:
    python3 viewer.py          →  http://localhost:8765/
    python3 viewer.py --port 9000
"""
import json
import mimetypes
import sys
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

_BASE_DIR     = Path(__file__).parent
DIRECTORIO_OUT = _BASE_DIR / "output"


# ---------------------------------------------------------------------------
# Lectura de datos
# ---------------------------------------------------------------------------
def _cargar_expedientes() -> list:
    expedientes = []
    if not DIRECTORIO_OUT.exists():
        return expedientes

    for calle_dir in sorted(DIRECTORIO_OUT.iterdir()):
        if not calle_dir.is_dir():
            continue
        nombre = calle_dir.name
        tipo, calle = nombre.split("_", 1) if "_" in nombre else ("??", nombre)

        for ref_dir in sorted(calle_dir.iterdir()):
            if not ref_dir.is_dir():
                continue
            exp_file = ref_dir / "expediente.json"
            if not exp_file.exists():
                continue
            try:
                data = json.loads(exp_file.read_text(encoding="utf-8"))
            except Exception:
                continue

            docs = [
                p.name for p in sorted(ref_dir.iterdir())
                if p.is_file() and p.name != "expediente.json"
            ]

            coords = data.get("coordenadasEdificio") or {}
            expedientes.append({
                "tipo":                   tipo,
                "calle":                  calle,
                "calleDir":               nombre,
                "refDir":                 ref_dir.name,
                "referencia":             data.get("referencia", ref_dir.name),
                "codigoInterno":          data.get("codigoInterno", ""),
                "fechaAlta":              data.get("fechaAlta", ""),
                "emplazamiento":          data.get("emplazamiento", ""),
                "tipoExp":                data.get("tipo", ""),
                "asunto":                 data.get("asunto", ""),
                "area":                   data.get("area", ""),
                "dependenciaTramitadora": data.get("dependenciaTramitadora", ""),
                "contieneResoluciones":   data.get("contieneResoluciones", False),
                "contieneDocumentos":     data.get("contieneDocumentos", False),
                "contieneInspecciones":   data.get("contieneInspecciones", False),
                "coordX":                 coords.get("coordED50X"),
                "coordY":                 coords.get("coordED50Y"),
                "documentos":             docs,
                "numDocs":                len(docs),
            })

    return expedientes


# ---------------------------------------------------------------------------
# Servidor HTTP
# ---------------------------------------------------------------------------
class ViewerHandler(BaseHTTPRequestHandler):
    _cache = None  # shared across requests

    @classmethod
    def _get_data(cls):
        if cls._cache is None:
            cls._cache = _cargar_expedientes()
        return cls._cache

    def log_message(self, fmt, *args):
        print(f"  {self.address_string()}  {args[0]}")

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path   = parsed.path

        if path in ("/", "/index.html"):
            self._file(_BASE_DIR / "viewer.html", "text/html; charset=utf-8")

        elif path == "/api/data":
            self._json(self._get_data())

        elif path == "/api/reload":
            ViewerHandler._cache = None
            count = len(self._get_data())
            self._json({"ok": True, "count": count})

        elif path.startswith("/doc/"):
            rel      = urllib.parse.unquote(path[5:])
            doc_path = (DIRECTORIO_OUT / rel).resolve()
            # Path traversal guard
            if not str(doc_path).startswith(str(DIRECTORIO_OUT.resolve())):
                self._send(403, b"Forbidden", "text/plain")
                return
            if doc_path.is_file():
                mime, _ = mimetypes.guess_type(str(doc_path))
                self._file(doc_path, mime or "application/octet-stream")
            else:
                self._send(404, b"Not found", "text/plain")

        else:
            self._send(404, b"Not found", "text/plain")

    # ── helpers ──────────────────────────────────────────────────────────────
    def _json(self, data):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self._send(200, body, "application/json; charset=utf-8")

    def _file(self, path, content_type):
        try:
            body = path.read_bytes()
            self._send(200, body, content_type)
        except FileNotFoundError:
            self._send(404, b"File not found", "text/plain")

    def _send(self, code, body, content_type):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", len(body))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(body)


# ---------------------------------------------------------------------------
# Punto de entrada
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    port = 8765
    if "--port" in sys.argv:
        idx = sys.argv.index("--port")
        port = int(sys.argv[idx + 1])

    # Pre-load data
    ViewerHandler._cache = _cargar_expedientes()
    n = len(ViewerHandler._cache)

    print(f"\n  ✓ {n} expedientes cargados desde output/")
    print(f"  Visor → http://localhost:{port}/\n")
    print("  Ctrl+C para detener.\n")

    httpd = HTTPServer(("localhost", port), ViewerHandler)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n  Servidor detenido.")
