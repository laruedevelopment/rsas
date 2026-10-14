// Edge Function: login
//
// Verifica apodo+clave contra la función `autenticar_usuario` (que ya existía
// y sigue comparando el hash bcrypt server-side, ver migracion_hash_claves.sql)
// y, si son válidos, firma un JWT propio de Supabase (HS256, con el "Legacy
// JWT secret" del proyecto). Ese token es lo que le permite al cliente Flutter
// hacer consultas como rol `authenticated` una vez habilitada la RLS — ver
// lib/fix_rls_seguridad.sql. El secret nunca sale de acá.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const JWT_SECRET = Deno.env.get("LOGIN_JWT_SECRET");

// Duración de la sesión: 12 horas (una jornada). No hay refresh token —
// pasado ese tiempo, la próxima consulta falla y hay que loguearse de nuevo.
const EXPIRACION_SEGUNDOS = 12 * 60 * 60;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonError("Método no permitido.", 405);
  }
  if (!JWT_SECRET) {
    return jsonError("Falta configurar LOGIN_JWT_SECRET en los secrets de Supabase.", 500);
  }

  let body: { apodo?: string; clave?: string };
  try {
    body = await req.json();
  } catch {
    return jsonError("Body inválido, se esperaba JSON.", 400);
  }

  const apodo = (body.apodo ?? "").trim();
  const clave = body.clave ?? "";
  if (!apodo || !clave) {
    return jsonError("Faltan apodo y/o clave.", 400);
  }
  // Límites razonables: evitan llenar la tabla de intentos con textos enormes
  // y costos de hash con claves gigantes.
  if (apodo.length > 64 || clave.length > 128) {
    return jsonError("Usuario o contraseña incorrectos.", 401);
  }

  try {
    const resultado = await verificarCredenciales(apodo, clave);
    if (resultado === "bloqueado") {
      return jsonError(
        "Demasiados intentos fallidos. Espere 15 minutos e intente de nuevo.",
        429,
      );
    }
    if (resultado === null) {
      return jsonError("Usuario o contraseña incorrectos.", 401);
    }

    const usuario = resultado;
    const ahora = Math.floor(Date.now() / 1000);
    const payload = {
      aud: "authenticated",
      role: "authenticated",
      sub: String(usuario.id),
      iat: ahora,
      exp: ahora + EXPIRACION_SEGUNDOS,
      apodo_usuario: usuario.apodo_usuario,
      rol_app: usuario.rol,
    };

    const accessToken = await firmarJwtHS256(payload, JWT_SECRET);

    return new Response(
      JSON.stringify({ usuario, accessToken, expiresAt: payload.exp }),
      { headers: { ...CORS_HEADERS, "content-type": "application/json" } },
    );
  } catch (e) {
    console.error("login: error inesperado", e);
    return jsonError("No se pudo iniciar sesión. Intente de nuevo en un momento.", 500);
  }
});

type Usuario = Record<string, unknown> & { id: number; apodo_usuario: string; rol: string };

/// Verifica apodo+clave en la base. Usa `autenticar_usuario_v2` (bloqueo por
/// intentos, solo invocable con la service role key — ver
/// lib/migracion_2026_09_seguridad_y_pagos.sql). Si esa migración todavía no
/// se corrió (la función no existe), cae a la `autenticar_usuario` vieja.
async function verificarCredenciales(
  apodo: string,
  clave: string,
): Promise<Usuario | "bloqueado" | null> {
  const res = await rpc("autenticar_usuario_v2", { p_apodo: apodo, p_clave: clave }, SERVICE_ROLE_KEY);

  if (res.status === 404) {
    const viejo = await rpc("autenticar_usuario", { p_apodo: apodo, p_clave: clave }, SUPABASE_ANON_KEY);
    if (!viejo.ok) throw new Error(`autenticar_usuario ${viejo.status}: ${await viejo.text()}`);
    const filas = await viejo.json();
    return Array.isArray(filas) && filas.length > 0 ? filas[0] : null;
  }
  if (!res.ok) throw new Error(`autenticar_usuario_v2 ${res.status}: ${await res.text()}`);

  const data = await res.json();
  if (data?.bloqueado) return "bloqueado";
  return data?.ok ? data.usuario : null;
}

function rpc(nombre: string, body: unknown, key: string): Promise<Response> {
  return fetch(`${SUPABASE_URL}/rest/v1/rpc/${nombre}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "apikey": key,
      "authorization": `Bearer ${key}`,
    },
    body: JSON.stringify(body),
  });
}

function jsonError(mensaje: string, status: number): Response {
  return new Response(JSON.stringify({ error: mensaje }), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json" },
  });
}

// ── Firma JWT HS256 sin dependencias externas (Web Crypto API) ─────────────

function base64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlJson(obj: unknown): string {
  return base64url(new TextEncoder().encode(JSON.stringify(obj)));
}

async function firmarJwtHS256(
  payload: Record<string, unknown>,
  secret: string,
): Promise<string> {
  const header = { alg: "HS256", typ: "JWT" };
  const data = `${base64urlJson(header)}.${base64urlJson(payload)}`;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(data),
  );

  return `${data}.${base64url(new Uint8Array(signature))}`;
}
