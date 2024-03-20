import os
import requests

## CONSTANTS PRIVATES
CTE_ARCHIVO_IN   = "calles_in.txt"
CTE_BEARER_TOKEN = "este_token_se_obtiene_desde_tu_navegador_inspeccionando_elemento_mientras_usas_conex_reemplazalo"

class ConexApiService:
    def __init__(self, auth_token):
        self.__auth_token = auth_token
        self.__base_url = "https://servayto.madrid.es/CONEX_RSCONSULTAEXP/api_rsconsultaexp/v1/expedientes/"

    def __init_header(self): 
        return {
            'Authorization': f'Bearer {self.__auth_token}'
        }
    
    def getProyectosFromCalle(self,
                              tipo_calle: str, 
                              calle_name: str,):


        url = f"{self.__base_url}query?tipo={tipo_calle}&nombre={calle_name}&numeroDesde=&numeroHasta=&escalera=&planta=&puerta=&fechaAlta="
        payload={}
        headers = {
            'Authorization': f'Bearer {self.__auth_token}'
        }
        response = requests.request("GET", url, headers=headers, data=payload)

        return response.json()

    def getProyectoDetalle(self, codigo_interno: str):


        url = f"{self.__base_url}{codigo_interno}"
        payload={}
        headers = self.__init_header()
        response = requests.request("GET", url, headers=headers, data=payload)

        return response.json()

    def getDocumentosFromProyecto(self, codigo_interno: str):
        url = f"{self.__base_url}{codigo_interno}/documentos"

        payload={}
        headers = self.__init_header()

        response = requests.request("GET", url, headers=headers, data=payload)

        return response.json()

    def descargarDocumento(self, 
                           codigo_interno: str, 
                           codigo_doc: str):
            
        url = f"{self.__base_url}{codigo_interno}/documentos/{codigo_doc}/descarga"

        payload={}
        headers = self.__init_header()

        response = requests.request("GET", url, headers=headers, data=payload)
        return response.content

class GuardadorDeDocumentos:

    def guardarDocumento(nombre_carpeta, documento_info, binario):
        codigo_doc = documento_info["codigoDoc"]
        descripcion = str(documento_info["descripcion"]).replace(" ", "_").replace("\\", "_").replace("/", "_").replace(".","_")
        tipo = documento_info["tipo"].lower()
        with open(f"{nombre_carpeta}\{descripcion}.{tipo}", 'wb') as archivo:
            archivo.write(binario)

    def guardarExpediente(nombre_carpeta, proyecto_info):
        with open(f"{nombre_carpeta}\informacion_expediente.txt", 'w') as archivo:
            archivo.write(f"Código Interno: {proyecto_info['codigoInterno']}\n")
            archivo.write(f"Referencia: {proyecto_info['referencia']}\n")
            archivo.write(f"Fecha de Alta: {proyecto_info['fechaAlta']}\n")
            archivo.write(f"Emplazamiento: {proyecto_info['emplazamiento']}\n")
            archivo.write(f"Dependencia: {proyecto_info['dependencia']}\n")
            archivo.write(f"Tipo: {proyecto_info['tipo']}\n")
            archivo.write(f"Asunto: {proyecto_info['asunto']}\n")
            if proyecto_info['coordenadasEdificio'] is not None:
                archivo.write(f"Coordenadas ED50X: {proyecto_info['coordenadasEdificio']['coordED50X']}\n")
                archivo.write(f"Coordenadas ED50Y: {proyecto_info['coordenadasEdificio']['coordED50Y']}\n")
            archivo.write(f"Dependencia Tramitadora: {proyecto_info['dependenciaTramitadora']}\n")
            archivo.write(f"Contiene Resoluciones: {proyecto_info['contieneResoluciones']}\n")
            archivo.write(f"Contiene Documentos: {proyecto_info['contieneDocumentos']}\n")
            archivo.write(f"Contiene Inspecciones: {proyecto_info['contieneInspecciones']}\n")
            archivo.write(f"Código Local: {proyecto_info['codigoLocal']}\n")
            archivo.write(f"Área: {proyecto_info['area']}\n")

    def creaDirectorioSiNoExiste(nombre_carpeta):
        if not os.path.exists(nombre_carpeta):
            os.makedirs(nombre_carpeta)

def main():
    apiConex = ConexApiService(CTE_BEARER_TOKEN)
    guardador = GuardadorDeDocumentos()
    with open(CTE_ARCHIVO_IN, 'r') as archivo:
        for linea in archivo:
            tipo_calle, calle_name = linea.strip().split(';')
            proyectos = apiConex.getProyectosFromCalle(tipo_calle, calle_name)
            for expediente in proyectos['listaExpedientes']:
                codigo_interno = expediente['codigoInterno']
                referencia = str(expediente['referencia']).replace("/","-")
                nombre_carpeta = f"{tipo_calle}_{calle_name}_{referencia}"
                
                guardador.creaDirectorioSiNoExiste(nombre_carpeta)
                proyecto_info = apiConex.getProyectoDetalle(codigo_interno)
                guardador.guardarExpediente(nombre_carpeta, proyecto_info)
                
                documentos = apiConex.getDocumentosFromProyecto(codigo_interno)                
                for documento in documentos:
                    binario = apiConex.descargarDocumento(codigo_interno, documento["codigoDoc"])
                    guardador.guardarDocumento(nombre_carpeta, documento, binario)



if __name__ == '__main__':
    main()