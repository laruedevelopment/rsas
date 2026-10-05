-- Metas comerciales para el Dashboard gerencial.
--
-- Una fila = una meta mensual de un indicador, para toda la agencia
-- (asesor_id = 0) o para un asesor puntual. Idempotente; NO toca datos
-- existentes. Correr en el SQL Editor, primero en PRUEBAS y luego en PRODUCCIÓN.
--
-- Indicadores: prima (prima emitida), polizas (cantidad emitida),
--              comision (comisión recibida), recaudo (prima recaudada).
-- Quién ve y quién escribe: solo Administrador (la regla vive en la base, no
-- depende de qué versión de la app tenga abierta cada usuario).

create table if not exists metas_comerciales (
  id         bigint generated always as identity primary key,
  anio       int     not null check (anio between 2000 and 2100),
  mes        int     not null check (mes between 1 and 12),
  indicador  text    not null check (indicador in ('prima', 'polizas', 'comision', 'recaudo')),
  asesor_id  bigint  not null default 0,   -- 0 = toda la agencia
  valor      numeric not null default 0 check (valor >= 0),
  fcreado    timestamptz not null default now(),
  fultmod    timestamptz not null default now(),
  unique (anio, mes, indicador, asesor_id)
);

alter table metas_comerciales enable row level security;

drop policy if exists app_authenticated_full_access on metas_comerciales;
drop policy if exists app_lectura on metas_comerciales;
drop policy if exists app_escritura on metas_comerciales;

create policy app_lectura on metas_comerciales for select to authenticated
  using ((select app_rol()) = 'A');

create policy app_escritura on metas_comerciales for all to authenticated
  using ((select app_rol()) = 'A')
  with check ((select app_rol()) = 'A');

-- fultmod lo pone la base, como en el resto de tablas.
do $$
begin
  if to_regprocedure('public.set_fultmod()') is not null then
    drop trigger if exists trg_fultmod on metas_comerciales;
    create trigger trg_fultmod before update on metas_comerciales
      for each row execute function set_fultmod();
  end if;
end $$;

-- Verificación: debe devolver 0 filas la primera vez.
select count(*) as metas from metas_comerciales;
