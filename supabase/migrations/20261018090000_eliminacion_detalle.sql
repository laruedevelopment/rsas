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
  v_snap jsonb;
begin
  if app_rol() is distinct from 'A' then
    raise exception 'Solo un Administrador puede ver este detalle.' using errcode = 'P0001';
  end if;

  select to_jsonb(v) into v_fila
    from vw_polizas_busqueda v
   where v.id = p_poliza_id;

  if v_fila is not null then
    return v_fila;
  end if;

  -- Ya eliminada: la copia solo trae ids; se le agregan los nombres de sus relaciones.
  select e.snapshot into v_snap
    from polizas_eliminacion e
   where e.poliza_id = p_poliza_id and e.snapshot is not null
   order by e.id desc
   limit 1;
  if v_snap is null then
    return null;
  end if;

  return v_snap || jsonb_strip_nulls(jsonb_build_object(
    'nombre_cliente',    (select to_jsonb(t) ->> 'nombre_cliente' from clientes t where t.id = (v_snap ->> 'cliente_id')::bigint),
    'doc_cliente',       (select to_jsonb(t) ->> 'doc_cliente' from clientes t where t.id = (v_snap ->> 'cliente_id')::bigint),
    'tipodoc_cliente',   (select to_jsonb(t) ->> 'tipodoc_cliente' from clientes t where t.id = (v_snap ->> 'cliente_id')::bigint),
    'tel_cliente',       (select to_jsonb(t) ->> 'tel_cliente' from clientes t where t.id = (v_snap ->> 'cliente_id')::bigint),
    'nombre_aseg',       (select to_jsonb(t) ->> 'nombre_aseg' from aseguradoras t where t.id = (v_snap ->> 'aseg_id')::bigint),
    'nombre_ramo',       (select to_jsonb(t) ->> 'nombre_ramo' from ramos t where t.id = (v_snap ->> 'ramo_id')::bigint),
    'nombre_prod',       (select to_jsonb(t) ->> 'nombre_prod' from productos t where t.id = (v_snap ->> 'producto_id')::bigint),
    'nombre_asesor',     (select to_jsonb(t) ->> 'nombre_asesor' from asesores t where t.id = (v_snap ->> 'asesor_id')::bigint),
    'nombre_forma_pago', (select to_jsonb(t) ->> 'nombre_forma_pago' from formas_pago t where t.id = (v_snap ->> 'forma_pago_id')::bigint),
    'nombre_formaexp',   (select to_jsonb(t) ->> 'nombre_formaexp' from formaexp t where t.id = (v_snap ->> 'formaexp_id')::bigint),
    'apodo_usuario',     (select to_jsonb(t) ->> 'apodo_usuario' from usuarios t where t.id = (v_snap ->> 'usuario_id')::bigint)
  ));
end;
$$;

revoke all on function polizas_eliminacion_detalle(bigint) from public, anon;
grant execute on function polizas_eliminacion_detalle(bigint) to authenticated;
