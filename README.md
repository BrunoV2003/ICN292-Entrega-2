# SIG Minimarket (Rengo) · ICN-292 · Entrega 2

Sistema de información local para un minimarket de Rengo que hoy controla su inventario "al ojo". El SIG registra productos, pedidos, recepciones, costos, ventas y mermas; calcula cuándo reponer cada producto; y **avisa por correo a la encargada** (automatización con n8n).

**Grupo 5 · Paralelo P101 · UTFSM, Campus Vitacura · 2026-2**
Bruno Vega Veloso · Lorenzo Ruiz Flandez · Igor Rios Rojas · Michelle Medina Barra · Charles Piket Silva

> Todos los datos del repositorio son **sintéticos** (de prueba) y coherentes con el negocio. No son ventas reales del minimarket.


```bash


Debe terminar con `OK 17 consultas ejecutadas sin errores`. El script hace esto:

1. Crea `db/minimarket_e2.db` desde cero con `db/schema.sql` y `db/seed.sql`.
2. Revisa la base: `quick_check` = ok, sin errores de claves foráneas, 16 tablas, 5 vistas y 19 triggers.
3. Prueba que la base **rechace** 4 operaciones inválidas, como vender sin stock o borrar historial.
4. Ejecuta `consultas.sql` (10 consultas de negocio), `consultas_demo_fecha_fija.sql` y `consultas_n8n.sql`, y guarda los resultados en `db/resultados/resultados_consultas.md`.

Con la consola de SQLite el resultado es el mismo:

```bash
sqlite3 db/minimarket_e2.db ".read db/schema.sql" ".read db/seed.sql" ".mode box" ".read db/consultas.sql"
```

La interpretación de los resultados está en [`docs/04-sql-consultas.md`](docs/04-sql-consultas.md).

## La aplicación (opcional para la auditoría)

Código en `app/SIG_Minimarket_E2_v1.2.4/`, hecho con Flask y SQLite y pensado para un computador Windows, por `localhost`.

- **Abrir la app en Windows:** doble clic en `INICIAR_SIG_CON_AVISO_CORREO.bat`. Crea su entorno de Python e instala `requirements.txt` la primera vez, y abre `http://127.0.0.1:5000`.
- **Abrirla en cualquier sistema:** ejecutar en la carpeta de la app:

  ```bash
  pip install -r requirements.txt
  python sig_windows.py
  ```

- **Pruebas automáticas:** `python -m pytest -q` debe dar **70 passed**.
- **Ejecutable `.exe`:** se arma con `CONSTRUIR_EXE_WINDOWS.bat`.

Sin configurar n8n, la app funciona igual: el aviso por correo es opcional.

## Automatización (n8n)

Cuando un producto entra en alerta de reposición después de una venta, un ajuste o una entrada, el SIG llama a un webhook de n8n y n8n envía un **correo con Gmail** a la encargada. Está trazado a la tarea BPMN *Generar alerta de reposición*.

- Flujo para importar: `n8n/alerta_reposicion_correo.json`.
- Probador del webhook: `n8n/PROBAR_N8N.bat`.
- Evidencias reales: `n8n/evidencias/`.
- Documentación paso a paso: [`docs/05-automatizacion-n8n.md`](docs/05-automatizacion-n8n.md).

La clave del webhook **nunca** está en el repositorio.

## Estructura del repositorio

| Ruta | Contenido |
|---|---|
| `README.md` | Este archivo |
| `docs/00-caso-pyme.md` | La PYME, el problema medible y el objetivo |
| `docs/01-requerimientos.md` | Requisitos funcionales y no funcionales verificables; matriz de trazabilidad requisito → BPMN → datos → prueba |
| `docs/02-bpmn.md` | As-Is, To-Be de reposición y To-Be de ventas; cambios respecto de la E1 |
| `docs/03-modelo-datos.md` | ER, justificación de 3FN, anomalías evitadas, triggers y diccionario de datos |
| `docs/04-sql-consultas.md` | Cómo ejecutar y resultados interpretados |
| `docs/05-automatizacion-n8n.md` | Automatización n8n: diseño, nodos, puesta en marcha, pruebas y KPI |
| `docs/DECLARACION_IA.md` | Uso de inteligencia artificial |
| `docs/CHANGELOG.md` | Cambios desde la E1 |
| `docs/img/` | Diagramas BPMN, ER y capturas de la prueba real |
| `db/` | `schema.sql`, `seed.sql`, consultas, script `crear_y_consultar.py` y resultados |
| `bpmn/` | Modelo Bizagi (`.bpm`), exportación BPMN 2.0 (`.bpmn`) e imágenes |
| `n8n/` | Flujo de n8n, probador y evidencias |
| `app/` | Código fuente de la aplicación (con 70 pruebas) |
| `presentacion/` | Diapositivas de la defensa |
| `informe/` | Informe E2 en PDF y .zip(latex) |
| `ENLACE_GITHUB.txt` | URL y tag de la versión defendida |

## Versiones usadas

| Componente | Versión |
|---|---|
| Python | 3.10 o superior (probado con 3.13) |
| SQLite | 3.35 o superior (probado con 3.53) |
| Flask / Waitress | 3.1.3 / 3.0.2 |
| Bizagi Modeler | 4.3.0.008 |
| n8n | n8n Cloud (nodos Webhook v2, Code v2, IF v2, Gmail v2.1) |
