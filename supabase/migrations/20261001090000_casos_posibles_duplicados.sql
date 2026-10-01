-- ═══════════════════════════════════════════════════════════════════════════
-- "Casos por revisar": un caso por cada grupo de pólizas duplicadas.
--
-- Hasta ahora el único caso de duplicados (#2, póliza 0969019-9) se cargó a
-- mano; los demás grupos duplicados que existan en la base no tenían caso.
-- Esta migración crea un caso POSIBLE_DUPLICADO por cada grupo de pólizas con
-- el mismo número (normalizado) en la misma aseguradora, con al menos dos
-- pólizas NO anuladas (mismo criterio que la pantalla "Pólizas duplicadas" y
-- que el cierre automático de casos).
--
-- Solo INSERTA filas en casos_revision: no modifica pólizas ni pagos. No
-- vuelve a crear un caso si alguna de las pólizas del grupo ya está en otro
-- caso de duplicados (pendiente o resuelto). Se puede volver a correr.
--
-- IMPORTANTE: correr el PASO 0 primero. Si el número de grupos es muy alto,
-- decidir antes de insertar (cada grupo es un caso en la bandeja).
-- Correr primero en PRUEBAS y luego en PRODUCCIÓN, por PASOS, en orden.
-- ═══════════════════════════════════════════════════════════════════════════


-- ── PASO 0 (solo lectura): cuántos casos se crearían ────────────────────────
with grupos as (
  select coalesce(aseg_id, 0) as aseg,
         nro_poliza_norm,
         array_agg(id order by id) as ids,
         count(*) filter (where coalesce(estado_poliza_id, '') <> 'A') as activas
    from polizas
   where nro_poliza_norm <> ''
   group by coalesce(aseg_id, 0), nro_poliza_norm
  having count(*) > 1
)
select count(*) as grupos_duplicados,
       count(*) filter (where activas >= 2) as con_2_o_mas_activas,
       count(*) filter (
         where activas >= 2
           and not exists (select 1 from casos_revision c
                            where c.tipo = 'POSIBLE_DUPLICADO' and c.polizas && grupos.ids)
       ) as casos_a_crear
  from grupos;


-- ── PASO 1: crear los casos ─────────────────────────────────────────────────
with grupos as (
  select coalesce(aseg_id, 0) as aseg,
         nro_poliza_norm,
         array_agg(id order by id) as ids,
         count(*) filter (where coalesce(estado_poliza_id, '') <> 'A') as activas
    from polizas
   where nro_poliza_norm <> ''
   group by coalesce(aseg_id, 0), nro_poliza_norm
  having count(*) > 1
)
insert into public.casos_revision (tipo, titulo, descripcion, pregunta, polizas)
select 'POSIBLE_DUPLICADO',
       'Póliza ' || (select p.nro_poliza from polizas p where p.id = g.ids[1])
         || ' registrada ' || array_length(g.ids, 1) || ' veces',
       'Estas pólizas tienen el mismo número y la misma aseguradora: '
         || (select string_agg(
                      'cód. ' || p.id
                      || ' (' || coalesce(v.nombre_cliente, 'sin cliente')
                      || ', vigencia '
                      || coalesce(to_char(p.fini_poliza at time zone 'UTC', 'DD/MM/YYYY'), '?')
                      || ' – '
                      || coalesce(to_char(p.ffin_poliza at time zone 'UTC', 'DD/MM/YYYY'), '?')
                      || ', prima $'
                      || replace(to_char(coalesce(p.prima_poliza, 0), 'FM999,999,999,990'), ',', '.')
                      || ', estado ' || coalesce(p.estado_poliza_id, 'sin estado')
                      || ', ' || (select count(*) from abonos_poliza a
                                   where a.id_poliza = p.id and a.estado_pago <> 'A')
                      || ' pago(s) vigente(s))',
                      '; ' order by p.id)
               from polizas p
               left join vw_polizas_busqueda v on v.id = p.id
              where p.id = any (g.ids))
         || '.',
       '¿Son la misma póliza? Si sí, anular la que sobra con el botón "Anular cód. X" '
         || '(ahí mismo se decide qué hacer con sus pagos) y el caso se cierra solo. '
         || 'Si no, corregir el número de la que esté mal o explicar en qué se diferencian.',
       g.ids
  from grupos g
 where g.activas >= 2
   and not exists (select 1 from public.casos_revision c
                    where c.tipo = 'POSIBLE_DUPLICADO' and c.polizas && g.ids);


-- ── PASO 2 (solo lectura): verificación ─────────────────────────────────────
select tipo, estado, count(*) as casos
  from public.casos_revision
 group by tipo, estado
 order by tipo, estado;
