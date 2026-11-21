-- DATOS SINTETICOS: NO representan ventas, costos ni existencias reales de la PYME.
-- Ejecutar DESPUES de schema.sql sobre una base vacia para cargar ejemplos.
-- Si la base ya tiene datos, no inserta nada y no altera el inventario.
 -- SQLite usa fecha relativa a la primera ejecucion.
PRAGMA foreign_keys = ON;
BEGIN TRANSACTION;

-- Datos de demostracion: se cargan solo cuando las nueve tablas estan vacias.
-- Reejecutar este archivo en una base ya cargada NO duplica datos.
-- Si existen registros previos, no se modifica ninguno.
CREATE TEMP TABLE IF NOT EXISTS __seed_gate (run_seed INTEGER NOT NULL);
DELETE FROM temp.__seed_gate;
INSERT INTO temp.__seed_gate(run_seed)
SELECT 1 WHERE NOT EXISTS(SELECT 1 FROM proveedor)
  AND NOT EXISTS(SELECT 1 FROM producto)
  AND NOT EXISTS(SELECT 1 FROM entrada_stock)
  AND NOT EXISTS(SELECT 1 FROM venta)
  AND NOT EXISTS(SELECT 1 FROM detalle_venta)
  AND NOT EXISTS(SELECT 1 FROM ajuste_inventario)
  AND NOT EXISTS(SELECT 1 FROM conteo_fisico)
  AND NOT EXISTS(SELECT 1 FROM pedido)
  AND NOT EXISTS(SELECT 1 FROM detalle_pedido);


INSERT INTO proveedor (id_proveedor, nombre, plazo_entrega_dias)
SELECT * FROM (VALUES
(1, 'Distribuidora de prueba A', 2),
(2, 'Mayorista de prueba B', 3),
(3, 'Proveedor de prueba C', 2)
) WHERE EXISTS(SELECT 1 FROM temp.__seed_gate);

INSERT INTO producto
(id_producto, codigo_interno, codigo_barras, nombre, precio_venta,
 stock_minimo, id_proveedor_principal)
SELECT * FROM (VALUES
(1, 'INT-000001', '7800000000001', 'Agua mineral 500 ml', 700, 10, 1),
(2, 'INT-000002', '7800000000002', 'Bebida en lata 350 ml', 1200, 6, 1),
(3, 'INT-000003', '7800000000003', 'Arroz 1 kg', 1600, 10, 2),
(4, 'INT-000004', NULL, 'Huevo unidad', 350, 10, 3),
(5, 'INT-000005', '7800000000005', 'Leche 1 litro', 1300, 12, 3),
(6, 'INT-000006', '7800000000006', 'Galletas paquete', 700, 4, 2)
) WHERE EXISTS(SELECT 1 FROM temp.__seed_gate);

-- Pedidos de ejemplo: fechas coherentes con las recepciones de prueba.
-- Se documentan 2 pedidos recibidos, 1 parcial y 1 pendiente.
INSERT INTO pedido (id_pedido, id_proveedor, fecha_pedido,
                    fecha_entrega_estimada, estado_gestion, observacion)
SELECT * FROM (VALUES
 (1, 1, datetime('now','-9 days'), date('now','-7 days'), 'EMITIDO', 'Pedido de prueba A'),
 (2, 2, datetime('now','-7 days'), date('now','-5 days'), 'EMITIDO', 'Pedido parcial de prueba'),
 (3, 3, datetime('now','-7 days'), date('now','-5 days'), 'EMITIDO', 'Pedido recibido de prueba'),
 (4, 2, datetime('now','-1 day'), date('now','+2 days'), 'EMITIDO', 'Pedido pendiente de prueba')
) WHERE EXISTS(SELECT 1 FROM temp.__seed_gate);

INSERT INTO detalle_pedido
(id_detalle_pedido, id_pedido, id_producto, cantidad_solicitada, costo_unitario_estimado)
SELECT * FROM (VALUES
 (1, 1, 1, 10, 400),
 (2, 1, 2, 5, 800),
 (3, 2, 3, 6, 1050),
 (4, 3, 5, 20, 900),
 (5, 4, 6, 6, NULL)
) WHERE EXISTS(SELECT 1 FROM temp.__seed_gate);

-- Conteo/carga inicial: muestra el punto de partida del sistema.
INSERT INTO entrada_stock
(id_producto, tipo_entrada, cantidad, costo_unitario, fecha_hora, observacion)
SELECT * FROM (VALUES
(1, 'CARGA_INICIAL', 20, 350, datetime('now','-15 days'), 'Conteo inicial simulado'),
(2, 'CARGA_INICIAL', 10, 700, datetime('now','-15 days'), 'Conteo inicial simulado'),
(3, 'CARGA_INICIAL', 15, 1000, datetime('now','-15 days'), 'Conteo inicial simulado'),
(4, 'CARGA_INICIAL', 30, 200, datetime('now','-15 days'), 'Conteo inicial simulado'),
(5, 'CARGA_INICIAL', 12, 850, datetime('now','-15 days'), 'Conteo inicial simulado'),
(6, 'CARGA_INICIAL', 8, 400, datetime('now','-15 days'), 'Conteo inicial simulado')
) WHERE EXISTS(SELECT 1 FROM temp.__seed_gate);

-- Recepciones posteriores con costos que varian y cambian el CPP.
INSERT INTO entrada_stock
(id_producto, id_proveedor, id_detalle_pedido, tipo_entrada,
 cantidad, costo_unitario, fecha_hora, referencia_documento)
SELECT * FROM (VALUES
(1, 1, 1, 'RECEPCION', 10, 400, datetime('now','-7 days'), 'DOC-PRUEBA-001'),
(2, 1, 2, 'RECEPCION', 5, 800, datetime('now','-6 days'), 'DOC-PRUEBA-002'),
(3, 2, 3, 'RECEPCION', 4, 1050, datetime('now','-5 days'), 'DOC-PRUEBA-003'),
(5, 3, 4, 'RECEPCION', 20, 900, datetime('now','-5 days'), 'DOC-PRUEBA-004')
) WHERE EXISTS(SELECT 1 FROM temp.__seed_gate);

-- VENTA 1. Todo el alta de venta y sus detalles ocurre en la MISMA transaccion.
INSERT INTO venta (id_venta, fecha_hora)
SELECT * FROM (VALUES
(1, datetime('now','-4 days','-2 hours'))
) WHERE EXISTS(SELECT 1 FROM temp.__seed_gate);
INSERT INTO detalle_venta(id_venta, id_producto, cantidad, precio_unitario, costo_unitario_cpp)
SELECT 1, id_producto, 4, precio_venta, costo_promedio FROM producto WHERE id_producto = 1 AND EXISTS(SELECT 1 FROM temp.__seed_gate);
INSERT INTO detalle_venta(id_venta, id_producto, cantidad, precio_unitario, costo_unitario_cpp)
SELECT 1, id_producto, 7, precio_venta, costo_promedio FROM producto WHERE id_producto = 2 AND EXISTS(SELECT 1 FROM temp.__seed_gate);
INSERT INTO detalle_venta(id_venta, id_producto, cantidad, precio_unitario, costo_unitario_cpp)
SELECT 1, id_producto, 3, precio_venta, costo_promedio FROM producto WHERE id_producto = 6 AND EXISTS(SELECT 1 FROM temp.__seed_gate);

-- VENTA 2.
INSERT INTO venta (id_venta, fecha_hora)
SELECT * FROM (VALUES
(2, datetime('now','-2 days','-1 hours'))
) WHERE EXISTS(SELECT 1 FROM temp.__seed_gate);
INSERT INTO detalle_venta(id_venta, id_producto, cantidad, precio_unitario, costo_unitario_cpp)
SELECT 2, id_producto, 10, precio_venta, costo_promedio FROM producto WHERE id_producto = 3 AND EXISTS(SELECT 1 FROM temp.__seed_gate);
INSERT INTO detalle_venta(id_venta, id_producto, cantidad, precio_unitario, costo_unitario_cpp)
SELECT 2, id_producto, 4, precio_venta, costo_promedio FROM producto WHERE id_producto = 5 AND EXISTS(SELECT 1 FROM temp.__seed_gate);

-- VENTA 3.
INSERT INTO venta (id_venta, fecha_hora)
SELECT * FROM (VALUES
(3, datetime('now','-1 day','-30 minutes'))
) WHERE EXISTS(SELECT 1 FROM temp.__seed_gate);
INSERT INTO detalle_venta(id_venta, id_producto, cantidad, precio_unitario, costo_unitario_cpp)
SELECT 3, id_producto, 5, precio_venta, costo_promedio FROM producto WHERE id_producto = 2 AND EXISTS(SELECT 1 FROM temp.__seed_gate);
INSERT INTO detalle_venta(id_venta, id_producto, cantidad, precio_unitario, costo_unitario_cpp)
SELECT 3, id_producto, 6, precio_venta, costo_promedio FROM producto WHERE id_producto = 4 AND EXISTS(SELECT 1 FROM temp.__seed_gate);
INSERT INTO detalle_venta(id_venta, id_producto, cantidad, precio_unitario, costo_unitario_cpp)
SELECT 3, id_producto, 3, precio_venta, costo_promedio FROM producto WHERE id_producto = 6 AND EXISTS(SELECT 1 FROM temp.__seed_gate);

-- VENTA 4 (hoy).
INSERT INTO venta (id_venta, fecha_hora)
SELECT * FROM (VALUES
(4, datetime('now','-5 minutes'))
) WHERE EXISTS(SELECT 1 FROM temp.__seed_gate);
INSERT INTO detalle_venta(id_venta, id_producto, cantidad, precio_unitario, costo_unitario_cpp)
SELECT 4, id_producto, 5, precio_venta, costo_promedio FROM producto WHERE id_producto = 1 AND EXISTS(SELECT 1 FROM temp.__seed_gate);
INSERT INTO detalle_venta(id_venta, id_producto, cantidad, precio_unitario, costo_unitario_cpp)
SELECT 4, id_producto, 2, precio_venta, costo_promedio FROM producto WHERE id_producto = 5 AND EXISTS(SELECT 1 FROM temp.__seed_gate);

-- Conteos ANTES de registrar las mermas: permiten medir las diferencias.
INSERT INTO conteo_fisico (id_producto, fecha_hora, stock_sistema, cantidad_fisica, observacion)
SELECT id_producto, datetime('now','-2 minutes'), stock_actual, 23,
       'Se observa diferencia en leche; ejemplo sintetico'
FROM producto WHERE id_producto = 5 AND EXISTS(SELECT 1 FROM temp.__seed_gate);
INSERT INTO conteo_fisico (id_producto, fecha_hora, stock_sistema, cantidad_fisica, observacion)
SELECT id_producto, datetime('now','-2 minutes'), stock_actual, 22,
       'Huevos danados; ejemplo sintetico'
FROM producto WHERE id_producto = 4 AND EXISTS(SELECT 1 FROM temp.__seed_gate);
INSERT INTO conteo_fisico (id_producto, fecha_hora, stock_sistema, cantidad_fisica, observacion)
SELECT id_producto, datetime('now','-2 minutes'), stock_actual, stock_actual,
       'Conteo sin diferencia; ejemplo sintetico'
FROM producto WHERE id_producto = 2 AND EXISTS(SELECT 1 FROM temp.__seed_gate);

-- Los ajustes disminuyen existencias sin contabilizarse como ventas.
INSERT INTO ajuste_inventario
(id_producto, fecha_hora, tipo_ajuste, cantidad_delta, motivo, costo_unitario_cpp)
SELECT id_producto, datetime('now','-1 minutes'), 'MERMA', -3,
       'Unidades vencidas (simulacion)', costo_promedio
FROM producto WHERE id_producto = 5 AND EXISTS(SELECT 1 FROM temp.__seed_gate);
INSERT INTO ajuste_inventario
(id_producto, fecha_hora, tipo_ajuste, cantidad_delta, motivo, costo_unitario_cpp)
SELECT id_producto, datetime('now','-1 minutes'), 'MERMA', -2,
       'Huevos quebrados (simulacion)', costo_promedio
FROM producto WHERE id_producto = 4 AND EXISTS(SELECT 1 FROM temp.__seed_gate);
INSERT INTO ajuste_inventario
(id_producto, fecha_hora, tipo_ajuste, cantidad_delta, motivo, costo_unitario_cpp)
SELECT id_producto, datetime('now','-1 minutes'), 'MERMA', -1,
       'Paquete danado (simulacion)', costo_promedio
FROM producto WHERE id_producto = 6 AND EXISTS(SELECT 1 FROM temp.__seed_gate);

SELECT CASE WHEN EXISTS (SELECT 1 FROM temp.__seed_gate)
  THEN 'OK: datos sinteticos cargados'
  ELSE 'OMITIDO: la base ya contenia datos; no se duplico nada'
END AS estado_carga;
DROP TABLE temp.__seed_gate;
COMMIT;
