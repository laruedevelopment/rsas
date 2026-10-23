-- ═══════════════════════════════════════════════════════════════════════════
-- Oportunidades SECOP: seguimiento de los contratos públicos que el equipo
-- comercial trabaja como posibles clientes (póliza de cumplimiento, etc.).
--
-- La lista de contratos NO se guarda aquí: se consulta en vivo a datos.gov.co.
-- Esta tabla solo recuerda qué se hizo con cada contrato (contactado,
-- cotizado, cerrado, descartado) y por quién.
--
-- Se puede volver a correr sin problema. Correr primero en PRUEBAS.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists oportunidades_secop (
  id_contrato   text primary key,                -- p. ej. CO1.PCCNTR.10080090
  estado        text not null default 'nuevo'
                  check (estado in ('nuevo', 'contactado', 'cotizado', 'cerrado', 'descartado')),
  nota          text check (nota is null or length(nota) <= 500),
  proveedor     text,                            -- nombre y NIT, para ubicarlo sin consultar de nuevo
  documento     text,
  entidad       text,
  valor         numeric,
  usuario_id    bigint,                          -- quién hizo el último cambio
  fcreado       timestamptz not null default now(),
  fultmod       timestamptz not null default now()
);

create index if not exists oportunidades_secop_estado_idx on oportunidades_secop (estado);

alter table oportunidades_secop enable row level security;

drop policy if exists oportunidades_secop_lectura on oportunidades_secop;
drop policy if exists oportunidades_secop_insercion on oportunidades_secop;
drop policy if exists oportunidades_secop_edicion on oportunidades_secop;

create policy oportunidades_secop_lectura on oportunidades_secop for select to authenticated
  using ((select app_rol()) is not null);
create policy oportunidades_secop_insercion on oportunidades_secop for insert to authenticated
  with check ((select app_rol()) is not null);
create policy oportunidades_secop_edicion on oportunidades_secop for update to authenticated
  using ((select app_rol()) is not null)
  with check ((select app_rol()) is not null);

revoke all on oportunidades_secop from anon;
revoke delete on oportunidades_secop from authenticated;
grant select, insert, update on oportunidades_secop to authenticated;

create or replace function oportunidades_secop_marcar_cambio()
returns trigger
language plpgsql
as $$
begin
  new.fultmod := now();
  return new;
end;
$$;

drop trigger if exists oportunidades_secop_cambio on oportunidades_secop;
create trigger oportunidades_secop_cambio
  before update on oportunidades_secop
  for each row execute function oportunidades_secop_marcar_cambio();
