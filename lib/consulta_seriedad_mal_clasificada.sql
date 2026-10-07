-- SOLO LECTURA. No modifica nada. Correr en el SQL Editor (pruebas o producción).
--
-- Busca pólizas ya guardadas que parecen de SERIEDAD pero quedaron con un
-- producto que no es de seriedad (típicamente Cumplimiento). El texto "seriedad"
-- se busca en el bien asegurado y en la observación.

-- 1. Resumen por aseguradora y producto actual.
select nombre_aseg, nombre_ramo, nombre_prod, count(*) as polizas,
       sum(prima_poliza) as prima
  from vw_polizas_busqueda
 where coalesce(estado_poliza_id, '') <> 'A'
   and (bien_asegurado ilike '%seriedad%' or obs_poliza ilike '%seriedad%')
   and coalesce(nombre_prod, '') not ilike '%seriedad%'
 group by nombre_aseg, nombre_ramo, nombre_prod
 order by polizas desc;

-- 2. Detalle para corregir una por una desde la app (Pólizas → buscar por cód.).
select id as cod, nro_poliza, nombre_cliente, nombre_aseg, nombre_ramo,
       nombre_prod, prima_poliza, fexp_poliza,
       left(coalesce(bien_asegurado, obs_poliza), 120) as texto
  from vw_polizas_busqueda
 where coalesce(estado_poliza_id, '') <> 'A'
   and (bien_asegurado ilike '%seriedad%' or obs_poliza ilike '%seriedad%')
   and coalesce(nombre_prod, '') not ilike '%seriedad%'
 order by fexp_poliza desc nulls last, id desc
 limit 200;

-- 3. Aseguradoras con productos de garantía pero SIN producto de seriedad en el
--    catálogo (la app no puede sugerirlo ahí: hay que crearlo en Catálogos →
--    Productos).
select a.nombre_aseg,
       count(*) filter (where p.nombre_prod ilike '%cumplimiento%') as prod_cumplimiento,
       count(*) filter (where p.nombre_prod ilike '%seriedad%')     as prod_seriedad
  from aseguradoras a
  join productos p on p.aseguradora_id = a.id
 group by a.nombre_aseg
having count(*) filter (where p.nombre_prod ilike '%cumplimiento%') > 0
   and count(*) filter (where p.nombre_prod ilike '%seriedad%') = 0
 order by a.nombre_aseg;
