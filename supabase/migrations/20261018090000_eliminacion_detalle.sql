-- ═══════════════════════════════════════════════════════════════════════════
-- Detalle completo de una póliza marcada para eliminar (o ya eliminada).
--
-- Las pólizas marcadas no se pueden leer con la API normal (RLS las oculta,
-- también al administrador), así que la pantalla "Eliminaciones por
-- autorizar" no podía mostrar más que un resumen. Esta función, solo para
-- Administrador, devuelve la fila completa con los nombres de sus relaciones:
--   · si la póliza todavía existe (pendiente o rechazada): la fila en vivo;
--   · si ya se eliminó: la copia (snapshot) que se guardó al aprobar.
-- Solo lee: no modifica nada. Se puede volver a correr sin problema.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function polizas_eliminacion_detalle(p_poliza_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_fila jsonb;
begin
  if app_rol() is distinct from 'A' then
    raise exception 'Solo un Administrador puede ver este detalle.' using errcode = 'P0001';
  end if;

  select to_jsonb(v) into v_fila
    from vw_polizas_busqueda v
   where v.id = p_poliza_id;

  if v_fila is null then
    select e.snapshot into v_fila
      from polizas_eliminacion e
     where e.poliza_id = p_poliza_id and e.snapshot is not null
     order by e.id desc
     limit 1;
  end if;

  return v_fila;
end;
$$;

revoke all on function polizas_eliminacion_detalle(bigint) from public, anon;
grant execute on function polizas_eliminacion_detalle(bigint) to authenticated;
