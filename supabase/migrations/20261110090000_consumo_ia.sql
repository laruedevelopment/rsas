-- ═══════════════════════════════════════════════════════════════════════════
-- Consumo de IA: registro de cada llamada a Gemini y panel del administrador.
--
-- · consumo_ia: una fila por llamada a Gemini (la escriben las Edge Functions
--   extraer-poliza y extraer-reporte-pago con la service role key): quién, qué
--   función, tipo de archivo, tokens de entrada/caché/pensamiento/salida y cómo
--   terminó. Los reintentos cuentan aparte porque también se cobran.
-- · consumo_precios / consumo_config: precios por millón de tokens y TRM que usa
--   el panel para ESTIMAR el costo. Son editables por el administrador: el costo
--   real es el de la factura de Google; esto es una aproximación para seguirlo.
-- · RPC solo para Administrador: resumen por día, precios y uso de la base.
--
-- RLS activo y SIN políticas: nadie con sesión lee ni escribe las tablas
-- directamente; solo las funciones de abajo (security definer) y la service role.
-- Se puede volver a correr sin problema. Correr primero en PRUEBAS.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists consumo_ia (
  id                  bigint generated always as identity primary key,
  creado              timestamptz not null default now(),
  usuario_id          bigint,
  funcion             text not null,          -- extraer-poliza | extraer-reporte-pago
  modelo              text not null,
  tipo_archivo        text,                   -- pdf | xlsx | imagen
  bytes               int,
  tokens_entrada      int,
  tokens_cache        int,
  tokens_pensamiento  int,
  tokens_salida       int,
  reintento           boolean not null default false,
  estado              text not null,          -- STOP | MAX_TOKENS | http_402 | red ...
  ms                  int
);

create index if not exists consumo_ia_creado_idx on consumo_ia (creado);

alter table consumo_ia enable row level security;
drop policy if exists app_authenticated_full_access on consumo_ia;

revoke all on consumo_ia from anon, authenticated;
grant insert on consumo_ia to service_role;

create table if not exists consumo_precios (
  modelo              text primary key,       -- 'default' sirve para cualquier modelo sin fila propia
  usd_entrada_millon  numeric not null,
  usd_cache_millon    numeric not null,
  usd_salida_millon   numeric not null,       -- el "pensamiento" se cobra como salida
  actualizado         timestamptz not null default now()
);

create table if not exists consumo_config (
  clave  text primary key,
  valor  numeric not null
);

alter table consumo_precios enable row level security;
alter table consumo_config enable row level security;
drop policy if exists app_authenticated_full_access on consumo_precios;
drop policy if exists app_authenticated_full_access on consumo_config;
revoke all on consumo_precios from anon, authenticated;
revoke all on consumo_config from anon, authenticated;

-- Valores iniciales de REFERENCIA (verifíquelos con la tarifa vigente de Google
-- AI Studio y ajústelos desde el panel). No pisan lo que ya se haya guardado.
insert into consumo_precios (modelo, usd_entrada_millon, usd_cache_millon, usd_salida_millon)
values ('default', 0.30, 0.03, 2.50)
on conflict (modelo) do nothing;
insert into consumo_config (clave, valor) values ('trm_cop', 4000)
on conflict (clave) do nothing;

-- ── Resumen por día (hora de Colombia) ─────────────────────────────────────
create or replace function consumo_ia_resumen(p_desde date, p_hasta date)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  if app_rol() is distinct from 'A' then
    raise exception 'Solo un Administrador puede ver el consumo.' using errcode = 'P0001';
  end if;
  return coalesce((
    select jsonb_agg(f order by f.dia, f.funcion)
    from (
      select
        (c.creado at time zone 'America/Bogota')::date            as dia,
        c.funcion,
        coalesce(c.tipo_archivo, 'otro')                          as tipo_archivo,
        c.modelo,
        c.usuario_id,
        coalesce(u.apodo_usuario, '—')                            as usuario,
        count(*)                                                  as llamadas,
        count(*) filter (where not c.reintento)                   as lecturas,
        count(*) filter (where c.estado in ('STOP', 'ok'))        as exitosas,
        count(*) filter (where c.reintento)                       as reintentos,
        coalesce(sum(c.tokens_entrada), 0)                        as tokens_entrada,
        coalesce(sum(c.tokens_cache), 0)                          as tokens_cache,
        coalesce(sum(c.tokens_pensamiento), 0)                    as tokens_pensamiento,
        coalesce(sum(c.tokens_salida), 0)                         as tokens_salida,
        round(coalesce(sum(
          ( greatest(coalesce(c.tokens_entrada, 0) - coalesce(c.tokens_cache, 0), 0) * p.usd_entrada_millon
            + coalesce(c.tokens_cache, 0) * p.usd_cache_millon
            + (coalesce(c.tokens_salida, 0) + coalesce(c.tokens_pensamiento, 0)) * p.usd_salida_millon
          ) / 1000000.0
        ), 0)::numeric, 6)                                        as costo_usd
      from consumo_ia c
      left join usuarios u on u.id = c.usuario_id
      left join lateral (
        select pr.* from consumo_precios pr
         where pr.modelo in (c.modelo, 'default')
         order by (pr.modelo = c.modelo) desc
         limit 1
      ) p on true
      where (c.creado at time zone 'America/Bogota')::date between p_desde and p_hasta
      group by 1, c.funcion, 3, c.modelo, c.usuario_id, u.apodo_usuario
    ) f
  ), '[]'::jsonb);
end;
$$;

-- ── Precios y TRM ──────────────────────────────────────────────────────────
create or replace function consumo_ia_config()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  if app_rol() is distinct from 'A' then
    raise exception 'Solo un Administrador puede ver la configuración.' using errcode = 'P0001';
  end if;
  return jsonb_build_object(
    'trm', (select valor from consumo_config where clave = 'trm_cop'),
    'precios', coalesce((
      select jsonb_agg(jsonb_build_object(
        'modelo', modelo,
        'usd_entrada_millon', usd_entrada_millon,
        'usd_cache_millon', usd_cache_millon,
        'usd_salida_millon', usd_salida_millon,
        'actualizado', actualizado
      ) order by modelo)
      from consumo_precios
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function consumo_ia_guardar_config(
  p_trm numeric, p_modelo text, p_entrada numeric, p_cache numeric, p_salida numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if app_rol() is distinct from 'A' then
    raise exception 'Solo un Administrador puede cambiar los precios.' using errcode = 'P0001';
  end if;
  if p_trm is null or p_trm <= 0 or p_entrada < 0 or p_cache < 0 or p_salida < 0 then
    raise exception 'Los valores deben ser números positivos.' using errcode = 'P0001';
  end if;
  insert into consumo_config (clave, valor) values ('trm_cop', p_trm)
  on conflict (clave) do update set valor = excluded.valor;
  insert into consumo_precios (modelo, usd_entrada_millon, usd_cache_millon, usd_salida_millon, actualizado)
  values (coalesce(nullif(trim(p_modelo), ''), 'default'), p_entrada, p_cache, p_salida, now())
  on conflict (modelo) do update
    set usd_entrada_millon = excluded.usd_entrada_millon,
        usd_cache_millon   = excluded.usd_cache_millon,
        usd_salida_millon  = excluded.usd_salida_millon,
        actualizado        = now();
end;
$$;

-- ── Uso de la base de datos (plan gratuito: 500 MB de base, 1 GB de archivos) ─
create or replace function consumo_servicios()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_db bigint;
  v_storage bigint := 0;
begin
  if app_rol() is distinct from 'A' then
    raise exception 'Solo un Administrador puede ver esto.' using errcode = 'P0001';
  end if;
  select pg_database_size(current_database()) into v_db;
  if to_regclass('storage.objects') is not null then
    execute $q$select coalesce(sum((metadata ->> 'size')::bigint), 0) from storage.objects$q$
      into v_storage;
  end if;
  return jsonb_build_object(
    'db_bytes', v_db,
    'storage_bytes', v_storage,
    'polizas', (select count(*) from polizas),
    'clientes', (select count(*) from clientes)
  );
end;
$$;

revoke all on function consumo_ia_resumen(date, date) from public, anon;
revoke all on function consumo_ia_config() from public, anon;
revoke all on function consumo_ia_guardar_config(numeric, text, numeric, numeric, numeric) from public, anon;
revoke all on function consumo_servicios() from public, anon;
grant execute on function consumo_ia_resumen(date, date) to authenticated;
grant execute on function consumo_ia_config() to authenticated;
grant execute on function consumo_ia_guardar_config(numeric, text, numeric, numeric, numeric) to authenticated;
grant execute on function consumo_servicios() to authenticated;
