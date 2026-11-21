-- Consultas SIG Minimarket E2 (SQLite 3.35+). Datos sinteticos.
-- Ejecutar despues de schema.sql y seed.sql.

-- ============================================================
-- CONSULTAS DE NEGOCIO
-- ============================================================

-- 1. Articulos en o bajo su minimo (que reponer)
SELECT nombre, stock_actual, stock_minimo, punto_reposicion,
       metodo_calculo, unidades_para_reponer
FROM v_alertas_reposicion
ORDER BY stock_actual, nombre;

-- 2. Ingresos diarios y numero de ventas
SELECT date(fecha_hora) AS fecha,
       COUNT(*) AS numero_ventas,
       SUM(total_venta_clp) AS ingresos_clp
FROM v_resumen_venta
GROUP BY date(fecha_hora)
ORDER BY fecha;

-- 3. Unidades vendidas por producto (rotacion)
SELECT p.nombre,
       SUM(d.cantidad) AS unidades_vendidas,
       SUM(d.cantidad * d.precio_unitario) AS ingresos_clp
FROM detalle_venta d
JOIN producto p ON p.id_producto = d.id_producto
GROUP BY p.id_producto, p.nombre
ORDER BY unidades_vendidas DESC, p.nombre;

-- 4. Costo de mercaderia vendida y margen bruto por dia
SELECT date(fecha_hora) AS fecha,
       SUM(total_venta_clp) AS ingresos_clp,
       ROUND(SUM(costo_mercaderia_clp), 2) AS costo_mercaderia_clp,
       ROUND(SUM(margen_bruto_estimado_clp), 2) AS margen_bruto_estimado_clp
FROM v_resumen_venta
GROUP BY date(fecha_hora)
ORDER BY fecha;

-- 5. Mermas valorizadas con el CPP vigente en el ajuste
SELECT p.nombre,
       SUM(-a.cantidad_delta) AS unidades_merma,
       ROUND(SUM(-a.cantidad_delta * a.costo_unitario_cpp), 2) AS valor_estimado_clp
FROM ajuste_inventario a
JOIN producto p ON p.id_producto = a.id_producto
WHERE a.tipo_ajuste = 'MERMA'
GROUP BY p.id_producto, p.nombre
ORDER BY unidades_merma DESC;

-- 6. Precision de conteos: % de productos sin diferencia
SELECT COUNT(*) AS productos_contados,
       SUM(CASE WHEN stock_sistema = cantidad_fisica THEN 1 ELSE 0 END)
           AS productos_sin_diferencia,
       ROUND(100.0 * SUM(CASE WHEN stock_sistema = cantidad_fisica THEN 1 ELSE 0 END)
             / NULLIF(COUNT(*), 0), 2) AS porcentaje_coincidencia
FROM conteo_fisico;

-- 7. Historial unificado de movimientos de inventario
SELECT m.fecha_hora, p.nombre, m.tipo_movimiento, m.variacion_stock, m.id_origen
FROM v_movimientos_inventario m
JOIN producto p ON p.id_producto = m.id_producto
ORDER BY m.fecha_hora, m.tipo_movimiento, m.id_origen;

-- 8. Puntos efectivos de reposicion (automatico o minimo manual)
SELECT nombre, stock_actual, stock_minimo, unidades_vendidas_14_dias,
       demanda_diaria_estimada, plazo_entrega_dias,
       punto_reposicion, metodo_calculo
FROM v_puntos_reposicion
ORDER BY nombre;

-- 9. Pedidos, recepciones y cantidades pendientes
SELECT id_pedido, proveedor, date(fecha_pedido) AS fecha_pedido,
       fecha_entrega_estimada, unidades_solicitadas, unidades_recibidas,
       unidades_pendientes, estado_recepcion
FROM v_estado_pedidos
ORDER BY id_pedido;

-- 10. Detalle de pedidos pendientes o parcialmente recibidos
SELECT ped.id_pedido, pr.nombre AS proveedor, p.nombre AS producto,
       dp.cantidad_solicitada,
       COALESCE(SUM(e.cantidad), 0) AS cantidad_recibida,
       dp.cantidad_solicitada - COALESCE(SUM(e.cantidad), 0) AS cantidad_pendiente
FROM detalle_pedido dp
JOIN pedido ped ON ped.id_pedido = dp.id_pedido
JOIN proveedor pr ON pr.id_proveedor = ped.id_proveedor
JOIN producto p ON p.id_producto = dp.id_producto
LEFT JOIN entrada_stock e ON e.id_detalle_pedido = dp.id_detalle_pedido
WHERE ped.estado_gestion = 'EMITIDO'
GROUP BY ped.id_pedido, pr.nombre, p.id_producto, p.nombre,
         dp.id_detalle_pedido, dp.cantidad_solicitada
HAVING cantidad_pendiente > 0
ORDER BY ped.id_pedido, p.nombre;

-- ============================================================
-- CONSULTAS CON FECHA DE CORTE FIJA (ultima venta del seed, venta 4)
-- ============================================================

-- 11. Alertas de reposicion al corte
WITH parametros(fecha_corte) AS (SELECT fecha_hora FROM venta WHERE id_venta = 4),
ventas_14 AS (
    SELECT d.id_producto, SUM(d.cantidad) AS unidades_vendidas_14_dias
    FROM detalle_venta d
    JOIN venta v ON v.id_venta = d.id_venta
    WHERE v.fecha_hora >= datetime((SELECT fecha_corte FROM parametros), '-14 days')
      AND v.fecha_hora <= (SELECT fecha_corte FROM parametros)
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
           CASE WHEN i.primera_entrada <= datetime((SELECT fecha_corte FROM parametros), '-14 days')
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
),
puntos AS (
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
FROM calculo
)
SELECT nombre, stock_actual, stock_minimo, punto_reposicion,
       metodo_calculo,
       CASE WHEN stock_actual = punto_reposicion
            THEN 'EN_UMBRAL' ELSE 'BAJO_UMBRAL' END AS estado_alerta,
       punto_reposicion - stock_actual + 1 AS unidades_para_reponer
FROM puntos
WHERE stock_actual <= punto_reposicion
ORDER BY stock_actual, nombre;

-- 12. Puntos de reposicion al corte
WITH parametros(fecha_corte) AS (SELECT fecha_hora FROM venta WHERE id_venta = 4),
ventas_14 AS (
    SELECT d.id_producto, SUM(d.cantidad) AS unidades_vendidas_14_dias
    FROM detalle_venta d
    JOIN venta v ON v.id_venta = d.id_venta
    WHERE v.fecha_hora >= datetime((SELECT fecha_corte FROM parametros), '-14 days')
      AND v.fecha_hora <= (SELECT fecha_corte FROM parametros)
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
           CASE WHEN i.primera_entrada <= datetime((SELECT fecha_corte FROM parametros), '-14 days')
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
),
puntos AS (
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
FROM calculo
)
SELECT nombre, stock_actual, stock_minimo, unidades_vendidas_14_dias,
       demanda_diaria_estimada, plazo_entrega_dias,
       punto_reposicion, metodo_calculo
FROM puntos
ORDER BY nombre;

-- ============================================================
-- CONSULTAS DE LA AUTOMATIZACION N8N (tabla sig_alerta_n8n, fechas en UTC)
-- ============================================================

-- 13. Alertas de reposicion por mes y avisos enviados por correo
SELECT strftime('%Y-%m', detectada_utc)                         AS mes,
       COUNT(*)                                                  AS alertas,
       SUM(estado_envio = 'ENVIADA')                             AS enviadas,
       ROUND(100.0 * SUM(estado_envio = 'ENVIADA') / COUNT(*), 1) AS pct_enviadas
FROM sig_alerta_n8n
GROUP BY mes
ORDER BY mes;

-- 14. Quiebres de stock por mes (alerta con stock 0)
SELECT strftime('%Y-%m', detectada_utc) AS mes,
       COUNT(*)                         AS quiebres_stock
FROM sig_alerta_n8n
WHERE stock_detectado = 0
GROUP BY mes
ORDER BY mes;

-- 15. Productos que mas veces entraron en alerta
SELECT p.nombre, p.codigo_interno, COUNT(*) AS veces_en_alerta
FROM sig_alerta_n8n a
JOIN producto p ON p.id_producto = a.id_producto
GROUP BY p.id_producto
ORDER BY veces_en_alerta DESC, p.nombre
LIMIT 10;

-- 16. Tiempo promedio (horas) en alerta
SELECT ROUND(AVG((julianday(cerrada_utc) - julianday(detectada_utc)) * 24), 1) AS horas_promedio_en_alerta,
       COUNT(*) AS alertas_cerradas
FROM sig_alerta_n8n
WHERE cerrada_utc IS NOT NULL;

-- 17. Avisos abiertos que no llegaron
SELECT a.id_alerta, p.nombre, a.detectada_utc, a.intentos, a.detalle_envio
FROM sig_alerta_n8n a
JOIN producto p ON p.id_producto = a.id_producto
WHERE a.cerrada_utc IS NULL AND a.estado_envio <> 'ENVIADA'
ORDER BY a.id_alerta;
