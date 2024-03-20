## Recopilador Masivo expedientes Conex
Recopilación masiva de datos usando la api de backend del servicio de conex del ayuntamiento de madrid.

El proyecto contiene:

- Collección de llamadas con postman
- Script en python
- fichero de calles como entrada

## Requirements
- Python 3

## Como usar

- En tu navegador (google chrome como ejemplo), obtén el bearer token que esta usando el cliente de conex para tu sesión, y reemplazalo en la constante `CTE_BEARER_TOKEN`

- Modifica las calles de las que quieres obtener documentos. Puedes descargarte un listado csv desde las plataformas del ayuntamiento (y el callejero)

- Adapta las funciones, parametriza mejor las llamadas si quieres añadir más criterios de filtrado

- Runea el proyecto

# Otros
- CONEX: https://servayto.madrid.es/CONEX_FTCONSULTAEXP/#/
- CALLEJERO DE MADRID: https://www.madrid.es/portales/munimadrid/es/Inicio/Vivienda-urbanismo-y-obras/Callejero-Municipal/?vgnextfmt=default&vgnextoid=45619bba4fa52710VgnVCM1000001d4a900aRCRD&vgnextchannel=593e31d3b28fe410VgnVCM1000000b205a0aRCRD&idCapitulo=11187495
- VISOR URBANISTICO DE MADRID: https://www.madrid.es/go/VisorUrbanistico

## 📝 Authors:
- Alfonso Soria Muñoz
- Tecnosor ©

 
MIT License.