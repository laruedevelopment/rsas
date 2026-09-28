// Código compartido por las Edge Functions de extracción con IA.

import { decodeBase64, encodeBase64 } from "jsr:@std/encoding@1/base64";

export const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function jsonError(mensaje: string, status: number): Response {
  return new Response(JSON.stringify({ error: mensaje }), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json" },
  });
}

export function jsonOk(data: unknown): Response {
  return new Response(JSON.stringify(data), {
    headers: { ...CORS_HEADERS, "content-type": "application/json" },
  });
}

export { decodeBase64, encodeBase64 };

/// Tamaño máximo del archivo recibido. Un documento de póliza o un reporte
/// de comisiones pesa normalmente menos de 2 MB; el límite evita que un
/// archivo enorme tumbe la función (256 MB de memoria) o dispare el costo.
export const MAX_BYTES_ARCHIVO = 15 * 1024 * 1024;

export function bytesDeBase64(fileBase64: string): number {
  return Math.floor((fileBase64.length * 3) / 4);
}

// ── Sesión ──────────────────────────────────────────────────────────────────

const JWT_SECRET = Deno.env.get("LOGIN_JWT_SECRET");

/// Devuelve el id del usuario si la petición trae el token de una sesión
/// válida (el que firma la función `login`), o null. Con solo la anon key
/// (pública, viaja en la app) NO alcanza: sin esto, cualquiera podía gastar
/// la cuota de Google llamando la función directamente.
export async function usuarioDeLaPeticion(req: Request): Promise<string | null> {
  if (!JWT_SECRET) return null;
  const auth = req.headers.get("authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "");
  const partes = token.split(".");
  if (partes.length !== 3) return null;

  try {
    const clave = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(JWT_SECRET),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"],
    );
    const valido = await crypto.subtle.verify(
      "HMAC",
      clave,
      base64urlABytes(partes[2]),
      new TextEncoder().encode(`${partes[0]}.${partes[1]}`),
    );
    if (!valido) return null;

    const payload = JSON.parse(new TextDecoder().decode(base64urlABytes(partes[1])));
    const ahora = Math.floor(Date.now() / 1000);
    if (payload.role !== "authenticated" || typeof payload.exp !== "number" || payload.exp < ahora) {
      return null;
    }
    return typeof payload.sub === "string" && payload.sub ? payload.sub : null;
  } catch {
    return null;
  }
}

function base64urlABytes(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  return decodeBase64(b64 + "=".repeat((4 - (b64.length % 4)) % 4));
}

// ── Gemini ──────────────────────────────────────────────────────────────────

const GOOGLE_API_KEY = Deno.env.get("GOOGLE_API_KEY");

/// Configurable sin tocar código (secret GEMINI_MODEL) por si se quiere
/// probar un modelo más barato.
const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.6-flash";

export type ResultadoGemini =
  | { ok: true; datos: unknown }
  | { ok: false; error: string; status: number };

/// Llama a Gemini pidiendo JSON con el schema dado.
///
/// - Las instrucciones van como systemInstruction y ANTES del archivo: esa
///   parte es idéntica en cada llamada y Gemini la puede cachear (el input
///   cacheado cuesta ~10% del normal).
/// - thinkingLevel "low": la tarea es transcribir un documento a un schema,
///   no razonar. El "pensamiento" se cobra como tokens de salida, así que
///   bajarlo reduce el costo y el tiempo de respuesta.
/// - La API key va en un header, nunca en la URL (una URL con la key podía
///   terminar en un mensaje de error mostrado al usuario o en los logs).
export async function llamarGemini(opciones: {
  instrucciones: string;
  partes: Record<string, unknown>[];
  schema: unknown;
  maxOutputTokens: number;
  etiqueta: string;
}): Promise<ResultadoGemini> {
  if (!GOOGLE_API_KEY) {
    console.error(`${opciones.etiqueta}: falta el secret GOOGLE_API_KEY`);
    return { ok: false, error: "El servicio de IA no está configurado.", status: 500 };
  }

  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

  const pedir = (conThinking: boolean) =>
    fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json", "x-goog-api-key": GOOGLE_API_KEY },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: opciones.instrucciones }] },
        contents: [{ role: "user", parts: opciones.partes }],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: opciones.schema,
          maxOutputTokens: opciones.maxOutputTokens,
          ...(conThinking ? { thinkingConfig: { thinkingLevel: "low" } } : {}),
        },
      }),
    });

  let res: Response;
  try {
    res = await pedir(true);
    // Si el modelo configurado no acepta thinkingLevel, se reintenta sin él
    // en vez de dejar la extracción rota.
    if (res.status === 400) {
      const detalle = await res.clone().text();
      if (/thinking/i.test(detalle)) {
        console.warn(`${opciones.etiqueta}: el modelo no acepta thinkingLevel, se reintenta sin él`);
        res = await pedir(false);
      }
    }
  } catch (e) {
    console.error(`${opciones.etiqueta}: error de red con Gemini`, String(e).replace(/key=[^&\s]+/g, "key=***"));
    return { ok: false, error: "No se pudo contactar el servicio de IA. Intente de nuevo.", status: 502 };
  }

  if (!res.ok) {
    const detalle = await res.text();
    console.error(`${opciones.etiqueta}: Gemini ${res.status}`, detalle.slice(0, 2000));
    if (res.status === 429) {
      return { ok: false, error: "Se alcanzó el límite de uso de la IA. Intente de nuevo en un minuto.", status: 429 };
    }
    if (res.status === 402) {
      return {
        ok: false,
        error: "El servicio de IA se quedó sin crédito prepago. Avise al administrador para recargarlo.",
        status: 402,
      };
    }
    if (res.status >= 500) {
      return { ok: false, error: "El servicio de IA no está disponible en este momento. Intente de nuevo.", status: 502 };
    }
    return { ok: false, error: "La IA no pudo procesar este archivo.", status: 502 };
  }

  const data = await res.json();
  const candidato = data.candidates?.[0];
  const finishReason = candidato?.finishReason;
  const uso = data.usageMetadata ?? {};
  console.log(
    `${opciones.etiqueta}: modelo=${GEMINI_MODEL} finish=${finishReason} ` +
      `entrada=${uso.promptTokenCount ?? "?"} cache=${uso.cachedContentTokenCount ?? 0} ` +
      `pensamiento=${uso.thoughtsTokenCount ?? 0} salida=${uso.candidatesTokenCount ?? "?"}`,
  );

  // Solo las partes de respuesta (no las de "pensamiento").
  const texto = (candidato?.content?.parts ?? [])
    .filter((p: { thought?: boolean; text?: string }) => !p.thought && typeof p.text === "string")
    .map((p: { text: string }) => p.text)
    .join("");

  if (finishReason === "MAX_TOKENS") {
    return {
      ok: false,
      error: "El documento es demasiado largo para leerlo de una vez. Divídalo en partes más pequeñas.",
      status: 422,
    };
  }
  if (!texto) {
    return {
      ok: false,
      error: "La IA no devolvió datos de este archivo. Pruebe con otro archivo o uno más nítido.",
      status: 422,
    };
  }

  try {
    return { ok: true, datos: JSON.parse(texto) };
  } catch {
    console.error(`${opciones.etiqueta}: JSON inválido (finish=${finishReason}, largo=${texto.length})`);
    return { ok: false, error: "La respuesta de la IA llegó incompleta. Intente de nuevo.", status: 502 };
  }
}
