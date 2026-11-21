-- =====================================================================
-- SIG Minimarket E2 (ICN-292, Grupo 5) - schema.sql COMPLETO
-- Generado el 20-11-2026 desde la base real de la app (database/minimarket.db
-- de la v1.2.4) + la tabla de avisos n8n. Crea en una base SQLite VACIA:
--   16 tablas: 9 del negocio, 3 de folios/jornada, 3 de caja y 1 de avisos n8n
--   indices, 19 triggers (stock, CPP, validaciones, historial protegido) y 5 vistas.
-- Orden de uso: schema.sql -> seed.sql -> consultas.sql
-- No ejecutar sobre una base que ya tiene tablas (usar una base nueva).
-- =====================================================================

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- ---------------------------------------------------------------
-- 1. Tablas del negocio (9)
-- ---------------------------------------------------------------

-- Tabla: proveedor
CREATE TABLE proveedor (
    id_proveedor INTEGER PRIMARY KEY,
    nombre TEXT NOT NULL CHECK (length(trim(nombre)) > 0),
    plazo_entrega_dias INTEGER CHECK (plazo_entrega_dias BETWEEN 0 AND 365),
    activo INTEGER NOT NULL DEFAULT 1 CHECK (activo IN (0, 1))
);

-- Tabla: producto
CREATE TABLE producto (
    id_producto INTEGER PRIMARY KEY,
    codigo_interno TEXT NOT NULL UNIQUE
        CHECK (codigo_interno LIKE 'INT-%' AND length(codigo_interno) > 4),
    codigo_barras TEXT UNIQUE,  -- NULL cuando no tiene código comercial
    nombre TEXT NOT NULL CHECK (length(trim(nombre)) > 0),
    precio_venta INTEGER NOT NULL CHECK (precio_venta >= 0),
    stock_actual INTEGER NOT NULL DEFAULT 0 CHECK (stock_actual >= 0),
    costo_promedio NUMERIC NOT NULL DEFAULT 0 CHECK (costo_promedio >= 0),
    stock_minimo INTEGER NOT NULL DEFAULT 0 CHECK (stock_minimo >= 0),
    id_proveedor_principal INTEGER REFERENCES proveedor(id_proveedor) ON DELETE RESTRICT,
    activo INTEGER NOT NULL DEFAULT 1 CHECK (activo IN (0, 1)),
    creado_en TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (codigo_barras IS NULL OR
           (length(trim(codigo_barras)) > 0 AND codigo_barras NOT LIKE 'INT-%'))
);

-- Tabla: pedido
CREATE TABLE pedido (
    id_pedido INTEGER PRIMARY KEY,
    id_proveedor INTEGER NOT NULL REFERENCES proveedor(id_proveedor) ON DELETE RESTRICT,
    fecha_pedido TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_entrega_estimada TEXT NOT NULL,
    estado_gestion TEXT NOT NULL DEFAULT 'EMITIDO'
        CHECK (estado_gestion IN ('EMITIDO', 'CANCELADO')),
    observacion TEXT,
    CHECK (date(fecha_pedido) IS NOT NULL
       AND date(fecha_entrega_estimada) IS NOT NULL
       AND date(fecha_entrega_estimada) >= date(fecha_pedido))
);

-- Tabla: detalle_pedido
CREATE TABLE detalle_pedido (
    id_detalle_pedido INTEGER PRIMARY KEY,
    id_pedido INTEGER NOT NULL REFERENCES pedido(id_pedido) ON DELETE RESTRICT,
    id_producto INTEGER NOT NULL REFERENCES producto(id_producto) ON DELETE RESTRICT,
    cantidad_solicitada INTEGER NOT NULL CHECK (cantidad_solicitada > 0),
    costo_unitario_estimado NUMERIC CHECK (costo_unitario_estimado >= 0),
    UNIQUE (id_pedido, id_producto)
);

-- Tabla: entrada_stock
CREATE TABLE entrada_stock (
    id_entrada INTEGER PRIMARY KEY,
    id_producto INTEGER NOT NULL REFERENCES producto(id_producto) ON DELETE RESTRICT,
    id_proveedor INTEGER REFERENCES proveedor(id_proveedor) ON DELETE RESTRICT,
    id_detalle_pedido INTEGER REFERENCES detalle_pedido(id_detalle_pedido) ON DELETE RESTRICT,
    tipo_entrada TEXT NOT NULL CHECK (tipo_entrada IN ('CARGA_INICIAL', 'RECEPCION')),
    cantidad INTEGER NOT NULL CHECK (cantidad > 0),
    costo_unitario NUMERIC NOT NULL CHECK (costo_unitario >= 0),
    fecha_hora TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    referencia_documento TEXT,
    observacion TEXT
);

-- Tabla: venta
CREATE TABLE venta (
    id_venta INTEGER PRIMARY KEY,
    fecha_hora TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    observacion TEXT
    -- El total se calcula desde detalle_venta, para evitar duplicar importes.
);

-- Tabla: detalle_venta
CREATE TABLE detalle_venta (
    id_detalle INTEGER PRIMARY KEY,
    id_venta INTEGER NOT NULL REFERENCES venta(id_venta) ON DELETE RESTRICT,
    id_producto INTEGER NOT NULL REFERENCES producto(id_producto) ON DELETE RESTRICT,
    cantidad INTEGER NOT NULL CHECK (cantidad > 0),
    precio_unitario INTEGER NOT NULL CHECK (precio_unitario >= 0),
    costo_unitario_cpp NUMERIC NOT NULL CHECK (costo_unitario_cpp >= 0),
    UNIQUE (id_venta, id_producto)
);

-- Tabla: ajuste_inventario
CREATE TABLE ajuste_inventario (
    id_ajuste INTEGER PRIMARY KEY,
    id_producto INTEGER NOT NULL REFERENCES producto(id_producto) ON DELETE RESTRICT,
    fecha_hora TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tipo_ajuste TEXT NOT NULL CHECK (tipo_ajuste IN ('MERMA', 'CORRECCION')),
    cantidad_delta INTEGER NOT NULL CHECK (cantidad_delta <> 0),
    motivo TEXT NOT NULL CHECK (length(trim(motivo)) > 0),
    costo_unitario_cpp NUMERIC NOT NULL CHECK (costo_unitario_cpp >= 0),
    CHECK (tipo_ajuste <> 'MERMA' OR cantidad_delta < 0)
);

-- Tabla: conteo_fisico
CREATE TABLE conteo_fisico (
    id_conteo INTEGER PRIMARY KEY,
    id_producto INTEGER NOT NULL REFERENCES producto(id_producto) ON DELETE RESTRICT,
    fecha_hora TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    stock_sistema INTEGER NOT NULL CHECK (stock_sistema >= 0),
    cantidad_fisica INTEGER NOT NULL CHECK (cantidad_fisica >= 0),
    observacion TEXT
);

-- ---------------------------------------------------------------
-- 2. Tablas auxiliares de folio y jornada (3)
-- ---------------------------------------------------------------

-- Tabla: sig_folio_venta
CREATE TABLE sig_folio_venta (
 id_venta INTEGER PRIMARY KEY REFERENCES venta(id_venta) ON DELETE RESTRICT,
 fecha_local TEXT NOT NULL,
 secuencia INTEGER NOT NULL CHECK(secuencia > 0),
 folio TEXT NOT NULL UNIQUE,
 UNIQUE(fecha_local,secuencia)
);

-- Tabla: sig_jornada
CREATE TABLE sig_jornada (
 fecha_local TEXT PRIMARY KEY,
 estado TEXT NOT NULL CHECK(estado IN ('ABIERTA','CERRADA')),
 cerrado_utc TEXT,
 ventas_cierre INTEGER,
 unidades_cierre INTEGER,
 total_cierre INTEGER,
 reaperturas INTEGER NOT NULL DEFAULT 0
);

-- Tabla: sig_evento_jornada
CREATE TABLE sig_evento_jornada (
 id_evento INTEGER PRIMARY KEY,
 fecha_local TEXT NOT NULL REFERENCES sig_jornada(fecha_local),
 accion TEXT NOT NULL CHECK(accion IN ('CIERRE','REAPERTURA')),
 fecha_hora_utc TEXT NOT NULL,
 ventas INTEGER,
 unidades INTEGER,
 total_clp INTEGER
);

-- ---------------------------------------------------------------
-- 3. Tablas de caja: medios de pago, arqueo y conciliacion Transbank (3)
-- ---------------------------------------------------------------

-- Tabla: sig_pago_venta
CREATE TABLE sig_pago_venta(
    id_pago INTEGER PRIMARY KEY,
    id_venta INTEGER NOT NULL REFERENCES venta(id_venta) ON DELETE RESTRICT,
    medio TEXT NOT NULL CHECK(medio IN ('EFECTIVO','TRANSBANK')),
    monto_clp INTEGER NOT NULL CHECK(monto_clp>=0),
    referencia TEXT,
    tipo_tarjeta TEXT,
    confirmado INTEGER NOT NULL DEFAULT 0 CHECK(confirmado IN (0,1)),
    registrado_utc TEXT NOT NULL,
    UNIQUE(id_venta,medio)
);

-- Tabla: sig_arqueo_caja
CREATE TABLE sig_arqueo_caja(
    fecha_local TEXT PRIMARY KEY,
    fondo_inicial_clp INTEGER NOT NULL CHECK(fondo_inicial_clp>=0),
    ingresos_clp INTEGER NOT NULL DEFAULT 0 CHECK(ingresos_clp>=0),
    retiros_clp INTEGER NOT NULL DEFAULT 0 CHECK(retiros_clp>=0),
    contado_clp INTEGER NOT NULL CHECK(contado_clp>=0),
    esperado_clp INTEGER NOT NULL CHECK(esperado_clp>=0),
    diferencia_clp INTEGER NOT NULL,
    observacion TEXT,
    excepcion_cierre TEXT,
    actualizado_utc TEXT NOT NULL
);

-- Tabla: sig_conciliacion_transbank
CREATE TABLE sig_conciliacion_transbank(
    fecha_local TEXT PRIMARY KEY,
    fecha_reporte TEXT,
    periodo_inicio TEXT,
    periodo_fin TEXT,
    terminal TEXT,
    nivel_detalle TEXT NOT NULL CHECK(nivel_detalle IN ('DETALLE','RESUMEN')),
    total_reporte_clp INTEGER,
    total_sig_clp INTEGER NOT NULL,
    diferencia_clp INTEGER,
    estado TEXT NOT NULL,
    operaciones_json TEXT NOT NULL DEFAULT '[]',
    hallazgos_json TEXT NOT NULL DEFAULT '[]',
    observacion TEXT,
    actualizado_utc TEXT NOT NULL
);

CREATE INDEX idx_sig_pago_medio ON sig_pago_venta(medio,id_venta);

-- ---------------------------------------------------------------
-- 4. Avisos de reposicion enviados a n8n (1)
--    Un aviso por producto mientras siga en alerta (indice unico parcial).
-- ---------------------------------------------------------------

-- Tabla: sig_alerta_n8n
CREATE TABLE sig_alerta_n8n(
    id_alerta INTEGER PRIMARY KEY,
    id_producto INTEGER NOT NULL REFERENCES producto(id_producto) ON DELETE RESTRICT,
    estado_alerta TEXT NOT NULL CHECK(estado_alerta IN ('EN_UMBRAL','BAJO_UMBRAL')),
    stock_detectado INTEGER NOT NULL CHECK(stock_detectado>=0),
    punto_reposicion INTEGER NOT NULL CHECK(punto_reposicion>=0),
    unidades_para_reponer INTEGER NOT NULL CHECK(unidades_para_reponer>=1),
    metodo_calculo TEXT NOT NULL,
    origen TEXT NOT NULL CHECK(origen IN ('VENTA','AJUSTE','ENTRADA','REVISION')),
    detectada_utc TEXT NOT NULL,
    cerrada_utc TEXT,
    estado_envio TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK(estado_envio IN ('PENDIENTE','ENVIADA','ERROR')),
    intentos INTEGER NOT NULL DEFAULT 0 CHECK(intentos>=0),
    ultimo_intento_utc TEXT,
    detalle_envio TEXT
);

CREATE UNIQUE INDEX ux_sig_alerta_n8n_abierta ON sig_alerta_n8n(id_producto) WHERE cerrada_utc IS NULL;
CREATE INDEX idx_sig_alerta_n8n_envio ON sig_alerta_n8n(estado_envio,id_alerta);

-- ---------------------------------------------------------------
-- 5. Indices de las tablas del negocio
-- ---------------------------------------------------------------

CREATE INDEX ix_ajuste_producto_fecha ON ajuste_inventario(id_producto, fecha_hora);

CREATE INDEX ix_conteo_producto_fecha ON conteo_fisico(id_producto, fecha_hora);

CREATE INDEX ix_detalle_pedido_producto ON detalle_pedido(id_producto);

CREATE INDEX ix_detalle_producto ON detalle_venta(id_producto);

CREATE INDEX ix_entrada_detalle_pedido ON entrada_stock(id_detalle_pedido);

CREATE INDEX ix_entrada_producto_fecha ON entrada_stock(id_producto, fecha_hora);

CREATE INDEX ix_pedido_proveedor_fecha ON pedido(id_proveedor, fecha_pedido);

CREATE INDEX ix_venta_fecha ON venta(fecha_hora);

-- ---------------------------------------------------------------
-- 6. Triggers (19)
-- ---------------------------------------------------------------

CREATE TRIGGER tr_ajuste_actualiza_stock
AFTER INSERT ON ajuste_inventario
BEGIN
    UPDATE producto
       SET stock_actual = stock_actual + NEW.cantidad_delta
     WHERE id_producto = NEW.id_producto;
END;

CREATE TRIGGER tr_ajuste_no_delete BEFORE DELETE ON ajuste_inventario
BEGIN SELECT RAISE(ABORT, 'Ajuste historico: no se elimina'); END;

CREATE TRIGGER tr_ajuste_no_update BEFORE UPDATE ON ajuste_inventario
BEGIN SELECT RAISE(ABORT, 'Ajuste historico: no se modifica'); END;

CREATE TRIGGER tr_ajuste_validar
BEFORE INSERT ON ajuste_inventario
BEGIN
    SELECT CASE WHEN
      (SELECT stock_actual FROM producto WHERE id_producto = NEW.id_producto) + NEW.cantidad_delta < 0
      THEN RAISE(ABORT, 'Ajuste excede el stock disponible') END;
    SELECT CASE WHEN ABS(
        (SELECT costo_promedio FROM producto WHERE id_producto = NEW.id_producto)
         - NEW.costo_unitario_cpp) > 0.00005
        THEN RAISE(ABORT, 'CPP del ajuste no coincide con el vigente') END;
END;

CREATE TRIGGER tr_conteo_no_delete BEFORE DELETE ON conteo_fisico
BEGIN SELECT RAISE(ABORT, 'Conteo historico: no se elimina'); END;

CREATE TRIGGER tr_conteo_no_update BEFORE UPDATE ON conteo_fisico
BEGIN SELECT RAISE(ABORT, 'Conteo historico: no se modifica'); END;

CREATE TRIGGER tr_conteo_validar
BEFORE INSERT ON conteo_fisico
BEGIN
    SELECT CASE WHEN (SELECT stock_actual FROM producto
                      WHERE id_producto = NEW.id_producto) <> NEW.stock_sistema
      THEN RAISE(ABORT, 'El stock de sistema del conteo no coincide con el vigente') END;
END;

CREATE TRIGGER tr_detalle_descuenta_stock
AFTER INSERT ON detalle_venta
BEGIN
    UPDATE producto
       SET stock_actual = stock_actual - NEW.cantidad
     WHERE id_producto = NEW.id_producto;
END;

CREATE TRIGGER tr_detalle_no_delete BEFORE DELETE ON detalle_venta
BEGIN SELECT RAISE(ABORT, 'Detalle historico: no se elimina'); END;

CREATE TRIGGER tr_detalle_no_update BEFORE UPDATE ON detalle_venta
BEGIN SELECT RAISE(ABORT, 'Detalle historico: no se modifica'); END;

CREATE TRIGGER tr_detalle_pedido_no_delete BEFORE DELETE ON detalle_pedido
BEGIN SELECT RAISE(ABORT, 'Detalle pedido historico: no se elimina'); END;

CREATE TRIGGER tr_detalle_pedido_no_update BEFORE UPDATE ON detalle_pedido
BEGIN SELECT RAISE(ABORT, 'Detalle pedido historico: no se modifica'); END;

CREATE TRIGGER tr_detalle_validar
BEFORE INSERT ON detalle_venta
BEGIN
    SELECT CASE WHEN (SELECT activo FROM producto WHERE id_producto = NEW.id_producto) <> 1
        THEN RAISE(ABORT, 'Producto inactivo') END;
    SELECT CASE WHEN (SELECT stock_actual FROM producto WHERE id_producto = NEW.id_producto) < NEW.cantidad
        THEN RAISE(ABORT, 'Stock insuficiente para registrar venta') END;
    SELECT CASE WHEN ABS(
        (SELECT costo_promedio FROM producto WHERE id_producto = NEW.id_producto)
         - NEW.costo_unitario_cpp) > 0.00005
        THEN RAISE(ABORT, 'CPP historico no coincide con el CPP vigente') END;
END;

CREATE TRIGGER tr_entrada_actualiza_producto
AFTER INSERT ON entrada_stock
BEGIN
    UPDATE producto
    SET costo_promedio = ROUND(
            (1.0 * stock_actual * costo_promedio + NEW.cantidad * NEW.costo_unitario)
            / (stock_actual + NEW.cantidad), 4
        ),
        stock_actual = stock_actual + NEW.cantidad
    WHERE id_producto = NEW.id_producto;
END;

CREATE TRIGGER tr_entrada_no_delete BEFORE DELETE ON entrada_stock
BEGIN SELECT RAISE(ABORT, 'Entrada historica: no se elimina'); END;

CREATE TRIGGER tr_entrada_no_update BEFORE UPDATE ON entrada_stock
BEGIN SELECT RAISE(ABORT, 'Entrada historica: no se modifica'); END;

CREATE TRIGGER tr_entrada_validar_pedido
BEFORE INSERT ON entrada_stock
WHEN NEW.id_detalle_pedido IS NOT NULL
BEGIN
    SELECT CASE WHEN NEW.tipo_entrada <> 'RECEPCION'
        THEN RAISE(ABORT, 'Una carga inicial no puede estar asociada a un pedido') END;
    SELECT CASE WHEN NEW.id_producto <> (
            SELECT dp.id_producto FROM detalle_pedido dp
            WHERE dp.id_detalle_pedido = NEW.id_detalle_pedido
        ) THEN RAISE(ABORT, 'Producto distinto al solicitado en pedido') END;
    SELECT CASE WHEN NEW.id_proveedor IS NULL OR NEW.id_proveedor <> (
            SELECT ped.id_proveedor FROM detalle_pedido dp
            JOIN pedido ped ON ped.id_pedido = dp.id_pedido
            WHERE dp.id_detalle_pedido = NEW.id_detalle_pedido
        ) THEN RAISE(ABORT, 'Proveedor no coincide con pedido') END;
    SELECT CASE WHEN (
            SELECT ped.estado_gestion FROM detalle_pedido dp
            JOIN pedido ped ON ped.id_pedido = dp.id_pedido
            WHERE dp.id_detalle_pedido = NEW.id_detalle_pedido
        ) <> 'EMITIDO' THEN RAISE(ABORT, 'Pedido cancelado') END;
    SELECT CASE WHEN NEW.cantidad + COALESCE((
            SELECT SUM(e.cantidad) FROM entrada_stock e
            WHERE e.id_detalle_pedido = NEW.id_detalle_pedido
        ), 0) > (
            SELECT dp.cantidad_solicitada FROM detalle_pedido dp
            WHERE dp.id_detalle_pedido = NEW.id_detalle_pedido
        ) THEN RAISE(ABORT, 'Recepcion excede cantidad solicitada') END;
END;

CREATE TRIGGER tr_pedido_cancelacion_validar
BEFORE UPDATE OF estado_gestion ON pedido
WHEN NEW.estado_gestion = 'CANCELADO' AND OLD.estado_gestion <> 'CANCELADO'
BEGIN
    SELECT CASE WHEN EXISTS (
        SELECT 1 FROM entrada_stock e
        JOIN detalle_pedido dp ON dp.id_detalle_pedido = e.id_detalle_pedido
        WHERE dp.id_pedido = OLD.id_pedido
    ) THEN RAISE(ABORT, 'No se cancela un pedido con recepciones registradas') END;
END;

CREATE TRIGGER tr_pedido_no_delete BEFORE DELETE ON pedido
BEGIN SELECT RAISE(ABORT, 'El pedido historico no se elimina'); END;

-- ---------------------------------------------------------------
-- 7. Vistas (5): se calculan, no guardan datos
-- ---------------------------------------------------------------

CREATE VIEW v_puntos_reposicion AS
WITH ventas_14 AS (
    SELECT d.id_producto, SUM(d.cantidad) AS unidades_vendidas_14_dias
    FROM detalle_venta d
    JOIN venta v ON v.id_venta = d.id_venta
    WHERE v.fecha_hora >= datetime('now', '-14 days')
      AND v.fecha_hora <= datetime('now')
    GROUP BY d.id_producto
), inicio_observacion AS (
    SELECT id_producto, MIN(fecha_hora) AS primera_entrada
    FROM entrada_stock
    GROUP BY id_producto
), base AS (
    SELECT p.id_producto, p.codigo_interno, p.nombre,
           p.stock_actual, p.stock_minimo,
           pr.plazo_entrega_dias,
           COALESCE(v.unidades_vendidas_14_dias, 0) AS unidades_vendidas_14_dias,
           i.primera_entrada,
           CASE WHEN i.primera_entrada <= datetime('now', '-14 days')
                 AND COALESCE(v.unidades_vendidas_14_dias, 0) > 0
                 AND pr.plazo_entrega_dias IS NOT NULL
                THEN 1 ELSE 0 END AS historial_suficiente
    FROM producto p
    LEFT JOIN proveedor pr ON pr.id_proveedor = p.id_proveedor_principal
    LEFT JOIN ventas_14 v ON v.id_producto = p.id_producto
    LEFT JOIN inicio_observacion i ON i.id_producto = p.id_producto
), calculo AS (
    SELECT *, (unidades_vendidas_14_dias / 14.0)
               * (plazo_entrega_dias + 1.5) AS umbral_calculado
    FROM base
)
SELECT id_producto, codigo_interno, nombre, stock_actual, stock_minimo,
       plazo_entrega_dias, unidades_vendidas_14_dias,
       ROUND(unidades_vendidas_14_dias / 14.0, 4) AS demanda_diaria_estimada,
       CASE WHEN historial_suficiente = 1
            THEN CAST(umbral_calculado AS INTEGER)
               + CASE WHEN umbral_calculado > CAST(umbral_calculado AS INTEGER)
                      THEN 1 ELSE 0 END
            ELSE stock_minimo END AS punto_reposicion,
       CASE WHEN historial_suficiente = 1
            THEN 'AUTOMATICO_14_DIAS' ELSE 'MANUAL_RESPALDO' END AS metodo_calculo
FROM calculo;

CREATE VIEW v_alertas_reposicion AS
SELECT r.id_producto, r.codigo_interno, r.nombre,
       r.stock_actual, r.stock_minimo, r.punto_reposicion,
       r.metodo_calculo, r.unidades_vendidas_14_dias,
       CASE WHEN r.stock_actual = r.punto_reposicion
            THEN 'EN_UMBRAL' ELSE 'BAJO_UMBRAL' END AS estado_alerta,
       r.punto_reposicion - r.stock_actual + 1 AS unidades_para_reponer
FROM v_puntos_reposicion r
JOIN producto p ON p.id_producto = r.id_producto
WHERE p.activo = 1 AND r.stock_actual <= r.punto_reposicion;

CREATE VIEW v_estado_pedidos AS
WITH recibidas AS (
    SELECT id_detalle_pedido, SUM(cantidad) AS cantidad_recibida
    FROM entrada_stock
    WHERE id_detalle_pedido IS NOT NULL
    GROUP BY id_detalle_pedido
), resumen AS (
    SELECT dp.id_pedido,
           SUM(dp.cantidad_solicitada) AS unidades_solicitadas,
           SUM(COALESCE(r.cantidad_recibida, 0)) AS unidades_recibidas
    FROM detalle_pedido dp
    LEFT JOIN recibidas r ON r.id_detalle_pedido = dp.id_detalle_pedido
    GROUP BY dp.id_pedido
)
SELECT ped.id_pedido, ped.id_proveedor, pr.nombre AS proveedor,
       ped.fecha_pedido, ped.fecha_entrega_estimada, ped.estado_gestion,
       COALESCE(r.unidades_solicitadas, 0) AS unidades_solicitadas,
       COALESCE(r.unidades_recibidas, 0) AS unidades_recibidas,
       COALESCE(r.unidades_solicitadas, 0) - COALESCE(r.unidades_recibidas, 0)
           AS unidades_pendientes,
       CASE
           WHEN ped.estado_gestion = 'CANCELADO' THEN 'CANCELADO'
           WHEN COALESCE(r.unidades_solicitadas, 0) = 0 THEN 'SIN_DETALLE'
           WHEN COALESCE(r.unidades_recibidas, 0) = 0 THEN 'PENDIENTE'
           WHEN r.unidades_recibidas >= r.unidades_solicitadas THEN 'RECIBIDO'
           ELSE 'PARCIAL'
       END AS estado_recepcion
FROM pedido ped
JOIN proveedor pr ON pr.id_proveedor = ped.id_proveedor
LEFT JOIN resumen r ON r.id_pedido = ped.id_pedido;

CREATE VIEW v_resumen_venta AS
SELECT v.id_venta, v.fecha_hora,
       SUM(d.cantidad * d.precio_unitario) AS total_venta_clp,
       ROUND(SUM(d.cantidad * d.costo_unitario_cpp), 2) AS costo_mercaderia_clp,
       ROUND(SUM(d.cantidad * (d.precio_unitario - d.costo_unitario_cpp)), 2)
          AS margen_bruto_estimado_clp
FROM venta v JOIN detalle_venta d ON d.id_venta = v.id_venta
GROUP BY v.id_venta, v.fecha_hora;

CREATE VIEW v_movimientos_inventario AS
SELECT e.fecha_hora, e.id_producto, 'ENTRADA' AS tipo_movimiento,
       e.id_entrada AS id_origen, e.cantidad AS variacion_stock
FROM entrada_stock e
UNION ALL
SELECT v.fecha_hora, d.id_producto, 'VENTA', d.id_detalle, -d.cantidad
FROM detalle_venta d JOIN venta v ON v.id_venta = d.id_venta
UNION ALL
SELECT a.fecha_hora, a.id_producto, a.tipo_ajuste, a.id_ajuste, a.cantidad_delta
FROM ajuste_inventario a;

COMMIT;
