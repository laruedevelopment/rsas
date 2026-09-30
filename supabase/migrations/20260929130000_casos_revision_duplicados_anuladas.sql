-- ═══════════════════════════════════════════════════════════════════════════
-- "Casos por revisar": una póliza ANULADA ya no cuenta como duplicada.
--
-- Desde el caso se puede anular una de las pólizas duplicadas (estado 'A' en
-- estados_poliza). El cierre automático de casos POSIBLE_DUPLICADO debe
-- ignorar las anuladas: si queda una sola póliza activa con ese número, el
-- caso está corregido. Solo cambia la función de verificación; no toca
-- datos. Requiere haber corrido antes 20260929120000_casos_revision_autovalidar.sql.
--
-- Se puede volver a correr sin problema. Correr primero en PRUEBAS y luego
-- en PRODUCCIÓN.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function casos_revision_sigue_abierto(c public.casos_revision)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case c.tipo
    when 'COMISION_RARA' then
      c.abono_id is null
      or exists (
        select 1 from abonos_poliza a
         where a.id = c.abono_id
           and coalesce(a.vlrabono_prima, 0) <> 0
           and coalesce(a.vlrcomision, 0) <> 0
           and a.vlrcomision / nullif(a.vlrabono_prima, 0) not between 0 and 1
      )
    when 'PAGO_SIN_POLIZA' then
      c.abono_id is null
      or cardinality(c.polizas) = 0
      or exists (
        select 1 from abonos_poliza a
         where a.id = c.abono_id
           and a.id_poliza = any (c.polizas)
      )
    when 'POSIBLE_DUPLICADO' then
      cardinality(c.polizas) < 2
      or exists (
        select 1 from polizas p
         where p.id = any (c.polizas)
           and coalesce(p.estado_poliza_id, '') <> 'A'
         group by p.aseg_id, p.nro_poliza_norm
        having count(*) >= 2
      )
    else true
  end;
$$;

revoke all on function casos_revision_sigue_abierto(public.casos_revision) from public, anon, authenticated;

-- Verificación (solo lectura): qué pasaría hoy con los casos pendientes.
select c.id, c.tipo, c.titulo, casos_revision_sigue_abierto(c) as sigue_abierto
  from public.casos_revision c
 where c.estado = 'P'
 order by c.id;
