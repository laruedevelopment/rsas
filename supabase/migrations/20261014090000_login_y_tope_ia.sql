-- Endurece el login y pone tope diario a las lecturas con IA.
-- Idempotente; NO toca datos existentes. Correr en el SQL Editor, primero en
-- PRUEBAS y luego en PRODUCCIÓN. Despliegue de funciones: ver abajo.
--
-- ORDEN: (1) correr este SQL, (2) desplegar las Edge Functions `login`,
-- `extraer-poliza` y `extraer-reporte-pago`. Las funciones nuevas funcionan
-- aunque este SQL no esté corrido (el tope simplemente no se aplica), pero el
-- SQL no rompe a las funciones viejas.

-- ═══ A. Login: intentos simultáneos ya no se saltan el bloqueo ═════════════
-- Antes la función contaba los fallos y luego insertaba el nuevo: 50 intentos
-- en paralelo veían "0 fallos" a la vez y todos probaban clave. Ahora los
-- intentos del MISMO apodo se encolan (lock por apodo hasta fin de la
-- transacción). Misma lógica y mismo resultado que la versión anterior.

create or replace function autenticar_usuario_v2(p_apodo text, p_clave text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_apodo text := left(coalesce(p_apodo, ''), 64);
  v_fallos int;
  v_u usuarios%rowtype;
  v_ok boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended(lower(v_apodo), 0));

  select count(*) into v_fallos
    from login_intentos
   where lower(apodo) = lower(v_apodo)
     and not exitoso
     and fecha > now() - interval '15 minutes';
  if v_fallos >= 5 then
    return jsonb_build_object('ok', false, 'bloqueado', true);
  end if;

  select * into v_u
    from usuarios u
   where u.apodo_usuario = p_apodo
     and u.estado_usuario = true
     and u.clave_usuario = crypt(p_clave, u.clave_usuario)
   limit 1;
  v_ok := found;

  insert into login_intentos (apodo, exitoso) values (v_apodo, v_ok);
  delete from login_intentos where fecha < now() - interval '30 days';
  if not v_ok then
    return jsonb_build_object('ok', false);
  end if;

  delete from login_intentos where lower(apodo) = lower(v_apodo) and not exitoso;

  if v_u.clave_usuario !~ '^\$2[aby]\$(1[1-9]|[2-3][0-9])\$' then
    update usuarios set clave_usuario = crypt(p_clave, gen_salt('bf', 11)) where id = v_u.id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'usuario', jsonb_build_object(
      'id', v_u.id,
      'apodo_usuario', v_u.apodo_usuario,
      'nombre_usuario', v_u.nombre_usuario,
      'rol', v_u.rol,
      'asesor_id', v_u.asesor_id,
      'correo_usuario', v_u.correo_usuario,
      'estado_usuario', v_u.estado_usuario
    )
  );
end;
$$;

revoke all on function autenticar_usuario_v2(text, text) from public, anon, authenticated;
grant execute on function autenticar_usuario_v2(text, text) to service_role;

-- Un Administrador puede desbloquear a un usuario (si alguien lo bloqueó a
-- propósito con intentos fallidos): select desbloquear_usuario('apodo');
create or replace function desbloquear_usuario(p_apodo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if app_rol() is distinct from 'A' then
    raise exception 'Solo un Administrador puede desbloquear usuarios.';
  end if;
  delete from login_intentos where lower(apodo) = lower(p_apodo) and not exitoso;
end;
$$;

revoke all on function desbloquear_usuario(text) from public, anon;
grant execute on function desbloquear_usuario(text) to authenticated;


-- ═══ B. Tope diario de lecturas con IA por usuario ═════════════════════════
-- Lo usan las Edge Functions extraer-poliza y extraer-reporte-pago (con la
-- service role key). Tope por defecto 400 al día (secret IA_TOPE_DIARIO en
-- las funciones para cambiarlo). El día cuenta en hora de Colombia.

create table if not exists ia_uso (
  usuario_id bigint not null,
  dia        date   not null,
  llamadas   int    not null default 0,
  primary key (usuario_id, dia)
);

-- RLS activo y SIN políticas: nadie con sesión de usuario la lee ni la escribe;
-- solo la función de abajo (security definer) y la service role.
alter table ia_uso enable row level security;
drop policy if exists app_authenticated_full_access on ia_uso;

create or replace function ia_consumir(p_usuario bigint, p_tope int)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dia date := (now() at time zone 'America/Bogota')::date;
  v_n int;
begin
  insert into ia_uso as t (usuario_id, dia, llamadas)
  values (p_usuario, v_dia, 1)
  on conflict (usuario_id, dia)
  do update set llamadas = t.llamadas + 1
  where t.llamadas < p_tope
  returning t.llamadas into v_n;

  -- Limpieza ocasional: se conservan 60 días.
  if v_n = 1 then
    delete from ia_uso where dia < v_dia - 60;
  end if;
  return v_n is not null;
end;
$$;

revoke all on function ia_consumir(bigint, int) from public, anon, authenticated;
grant execute on function ia_consumir(bigint, int) to service_role;

-- Verificación: 1 fila con 0 = tabla lista; la función existe.
select (select count(*) from ia_uso) as filas_ia_uso,
       to_regprocedure('public.ia_consumir(bigint,integer)') is not null as funcion_ok,
       to_regprocedure('public.desbloquear_usuario(text)') is not null as desbloqueo_ok;
