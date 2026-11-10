-- Los ajustes de facturación (porcentajes por defecto y empresas aseguradoras con su IVA)
-- los pueden cambiar también el Supervisor y el Digitador, igual que las facturas.
-- Crear y editar nada más; borrar empresas sigue siendo solo del Administrador.

drop policy if exists facturas_empresas_escritura on facturas_empresas;
drop policy if exists facturas_empresas_alta on facturas_empresas;
drop policy if exists facturas_empresas_edicion on facturas_empresas;
drop policy if exists facturas_empresas_borrado on facturas_empresas;
create policy facturas_empresas_alta on facturas_empresas for insert to authenticated
  with check ((select app_rol()) in ('A', 'S', 'D'));
create policy facturas_empresas_edicion on facturas_empresas for update to authenticated
  using ((select app_rol()) in ('A', 'S', 'D')) with check ((select app_rol()) in ('A', 'S', 'D'));
create policy facturas_empresas_borrado on facturas_empresas for delete to authenticated
  using ((select app_rol()) = 'A');

create or replace function facturacion_config_guardar(p_iva numeric, p_rete numeric, p_ica numeric)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(app_rol(), '') not in ('A', 'S', 'D') then
    raise exception 'No tiene permiso para cambiar los porcentajes.' using errcode = 'P0001';
  end if;
  if p_iva is null or p_rete is null or p_ica is null
     or least(p_iva, p_rete, p_ica) < 0 or greatest(p_iva, p_rete, p_ica) > 100 then
    raise exception 'Los porcentajes deben estar entre 0 y 100.' using errcode = 'P0001';
  end if;
  insert into facturacion_config (clave, valor) values ('iva_pct', p_iva), ('retefuente_pct', p_rete), ('ica_pct', p_ica)
  on conflict (clave) do update set valor = excluded.valor;
end;
$$;

revoke all on function facturacion_config_guardar(numeric, numeric, numeric) from public, anon;
grant execute on function facturacion_config_guardar(numeric, numeric, numeric) to authenticated;
