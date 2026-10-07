// Edge Function: extraer-poliza
//
// Recibe un PDF o imagen de una póliza (base64) y le pide a Gemini los datos
// estructurados para pre-llenar el formulario de "Nueva póliza". La API key
// de Google vive solo acá (secret de Supabase), nunca llega al cliente.

import {
  bytesDeBase64,
  CORS_HEADERS,
  jsonError,
  jsonOk,
  llamarGemini,
  MAX_BYTES_ARCHIVO,
  usuarioDeLaPeticion,
} from "../_shared/comun.ts";
import { recortarPdf } from "../_shared/pdf.ts";

const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    nro_poliza: {
      type: "STRING",
      nullable: true,
      description:
        "Número de póliza COMPLETO: todos sus segmentos unidos con guiones y el número de " +
        "ANEXO siempre al final como último segmento, aunque sea 0. Nunca espacios. " +
        "Ej.: Póliza '400-97-994000000046' + Anexo '6' → '400-97-994000000046-6'; " +
        "'B-100071475' + Anexo '0' → 'B-100071475-0'. Si el documento no tiene campo de " +
        "anexo, el número tal cual (con guiones en lugar de espacios).",
    },
    nombre_cliente: {
      type: "STRING",
      nullable: true,
      description:
        "Nombre del TOMADOR (bloque 'TOMADOR' o 'DATOS DEL TOMADOR'). En las pólizas de " +
        "cumplimiento y seriedad (garantías) ese mismo cliente se llama 'Tomador', " +
        "'Afianzado' o 'Garantizado' según la aseguradora: es el PRIMERO que aparece en el " +
        "documento y es el que se toma como cliente. NUNCA uses aquí al asegurado o " +
        "beneficiario de una garantía (es la entidad contratante). Fuera de las garantías, " +
        "si el documento no tiene un bloque de tomador aparte, el del asegurado.",
    },
    doc_cliente: {
      type: "STRING",
      nullable: true,
      description:
        "Documento (NIT o cédula) del tomador / afianzado / garantizado, el mismo de " +
        "nombre_cliente, sin puntos ni espacios; conserve el guion del dígito de " +
        "verificación del NIT si aparece (ej. '901983472-9'). En las garantías NO es el " +
        "NIT del asegurado/beneficiario.",
    },
    nombre_asegurado: {
      type: "STRING",
      nullable: true,
      description: "Nombre del ASEGURADO, solo si es distinto del tomador; si es el mismo, null.",
    },
    doc_asegurado: {
      type: "STRING",
      nullable: true,
      description: "Documento del asegurado, mismo formato que doc_cliente; null si es el mismo tomador.",
    },
    nombre_beneficiario: {
      type: "STRING",
      nullable: true,
      description: "Nombre del BENEFICIARIO, solo si es distinto del tomador y del asegurado.",
    },
    doc_beneficiario: {
      type: "STRING",
      nullable: true,
      description: "Documento del beneficiario, mismo formato que doc_cliente.",
    },
    nombre_aseguradora: { type: "STRING", nullable: true, description: "Compañía aseguradora que emite la póliza." },
    nombre_ramo: {
      type: "STRING",
      nullable: true,
      description:
        "Ramo del seguro. Si el producto coincide con una fila del catálogo, el ramo de esa " +
        "fila; si no, el ramo escrito en el documento o null si no aparece.",
    },
    nombre_producto: {
      type: "STRING",
      nullable: true,
      description:
        "Producto o plan. Si no hay un campo 'Producto'/'Plan', use el título que describe el " +
        "tipo de póliza (ej. 'POLIZA SEGURO DE ACCIDENTES ESCOLARES' → 'Accidentes Escolares'). " +
        "OJO con las garantías: si el objeto, las observaciones o los comentarios del " +
        "documento hablan de 'seriedad' (ej. 'garantizar la seriedad de la oferta'), el " +
        "producto es el de SERIEDAD, NO el de cumplimiento, aunque el ramo o el título digan " +
        "Cumplimiento. Con el catálogo, usa la fila de esa aseguradora cuyo producto sea de " +
        "seriedad.",
    },
    fecha_inicio: { type: "STRING", nullable: true, description: "Inicio de vigencia, YYYY-MM-DD." },
    fecha_fin: { type: "STRING", nullable: true, description: "Fin de vigencia, YYYY-MM-DD." },
    fecha_expedicion: { type: "STRING", nullable: true, description: "Fecha de expedición/emisión, YYYY-MM-DD." },
    prima: { type: "NUMBER", nullable: true, description: "Valor de la prima (campo 'Prima' del documento)." },
    valor_asegurado: { type: "NUMBER", nullable: true, description: "Valor asegurado." },
    valor_poliza: {
      type: "NUMBER",
      nullable: true,
      description:
        "Valor total de la póliza: el 'TOTAL A PAGAR' (o 'Total póliza'). Transcriba sus " +
        "dígitos uno por uno, sin confundir 0, 5, 6 y 8, y compruebe que sea igual a prima + " +
        "gastos de expedición + IVA.",
    },
    gastos_expedicion: {
      type: "NUMBER",
      nullable: true,
      description: "Gastos de expedición (campo 'Gastos Exp.'); 0 si aparece en cero, null si no hay campo.",
    },
    iva: {
      type: "NUMBER",
      nullable: true,
      description: "Valor del IVA de la póliza (campo 'IVA'); null si no aparece.",
    },
    bien_asegurado: {
      type: "STRING",
      nullable: true,
      description: "Bien o riesgo asegurado (ej. placa del vehículo, dirección del inmueble, objeto del contrato).",
    },
  },
};

const INSTRUCCIONES_BASE =
  "Usted extrae datos de pólizas de seguros emitidas por aseguradoras colombianas y los " +
  "devuelve según el schema.\n" +
  "- Números en formato colombiano: el punto separa miles y la coma los decimales " +
  "(1.234.567,89 → 1234567.89). Devuelva números planos, sin símbolo de moneda.\n" +
  "- Fechas en día/mes/año (05/03/2026 → 2026-03-05).\n" +
  "- Distinga los bloques Tomador, Asegurado y Beneficiario cuando el documento los separa.\n" +
  "- Pólizas de cumplimiento y seriedad (garantías) traen dos NIT: el del Tomador (también " +
  "rotulado Afianzado o Garantizado, el primero del documento), que es el cliente, y el del " +
  "Asegurado/Beneficiario, que es la entidad contratante. Devuelva el primero en " +
  "nombre_cliente/doc_cliente y el segundo en asegurado/beneficiario.\n" +
  "- Si el objeto, las observaciones o los comentarios de una garantía mencionan " +
  "'seriedad' (de la oferta), es una póliza de seriedad, no de cumplimiento.\n" +
  "- Valores: devuelva por separado prima, gastos_expedicion, iva y valor_poliza (total a " +
  "pagar). Los dígitos de los totales se transcriben con cuidado: en documentos escaneados " +
  "es fácil confundir 0, 5, 6 y 8; la suma prima + gastos + IVA debe dar el total.
" +
  "- Si un dato no aparece, devuelva null. Nunca invente valores.";

/// Páginas que se envían a la IA de un PDF largo (override: secret MAX_PAGINAS_POLIZA).
const MAX_PAGINAS_POLIZA = Number(Deno.env.get("MAX_PAGINAS_POLIZA") ?? "3") || 3;

type Producto = { aseguradora: string; ramo: string; producto: string };

/// Catálogo agrupado por aseguradora y en orden estable: menos tokens que
/// repetir la aseguradora en cada línea, y el mismo texto en cada llamada
/// (Gemini cachea el prefijo repetido).
function textoCatalogo(catalogo: Producto[]): string {
  if (catalogo.length === 0) return "";
  const porAseg = new Map<string, string[]>();
  for (const p of catalogo) {
    const lista = porAseg.get(p.aseguradora) ?? [];
    lista.push(`${p.ramo} | ${p.producto}`);
    porAseg.set(p.aseguradora, lista);
  }
  const bloques = [...porAseg.keys()].sort().map((aseg) =>
    `## ${aseg}\n${[...new Set(porAseg.get(aseg))].sort().join("\n")}`
  );
  return "\n\nCatálogo de productos existentes (ramo | producto, agrupados por aseguradora):\n" +
    bloques.join("\n") +
    "\n\nSi la póliza corresponde a una aseguradora/producto del catálogo (aunque el documento " +
    "use siglas o abreviaturas), devuelva nombre_aseguradora, nombre_ramo y nombre_producto " +
    "EXACTAMENTE como están en el catálogo. Si no corresponde a ninguno, devuelva lo que diga " +
    "el documento.";
}

/// La IA a veces lee mal un dígito del total en documentos escaneados (0↔5↔8).
/// Si prima + gastos + IVA (que vienen por separado en el documento) no da el
/// total leído, y el desfase es chico (menos del 15 %: un dígito mal leído),
/// se usa la suma y se devuelve un aviso para que el digitador lo revise.
/// Si el desfase es grande puede haber otros conceptos (extra prima,
/// descuentos), así que no se toca.
function ajustarTotal(datos: unknown): unknown {
  if (!datos || typeof datos !== "object") return datos;
  const d = datos as Record<string, unknown>;
  const num = (v: unknown) => (typeof v === "number" && isFinite(v) ? v : null);
  const prima = num(d.prima);
  const iva = num(d.iva);
  const total = num(d.valor_poliza);
  if (prima == null || iva == null || iva <= 0 || total == null) return d;
  const gastos = num(d.gastos_expedicion) ?? 0;
  const suma = Math.round((prima + gastos + iva) * 100) / 100;
  const dif = Math.abs(suma - total);
  if (dif <= 1 || dif > suma * 0.15) return d;
  console.warn(`extraer-poliza: total leído ${total} no cuadra con prima+gastos+IVA ${suma}; se usa la suma`);
  d.valor_poliza = suma;
  d.aviso_total =
    `El total leído en el documento (${total.toLocaleString("es-CO")}) no cuadraba con ` +
    `prima + gastos + IVA; se usó ${suma.toLocaleString("es-CO")}. Verifíquelo contra el documento.`;
  return d;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonError("Método no permitido.", 405);

  if (!(await usuarioDeLaPeticion(req))) {
    return jsonError("Su sesión no es válida o ya venció. Inicie sesión de nuevo.", 401);
  }

  let body: { fileBase64?: string; mimeType?: string; catalogoProductos?: Producto[] };
  try {
    body = await req.json();
  } catch {
    return jsonError("Petición inválida.", 400);
  }

  const { fileBase64, mimeType, catalogoProductos } = body;
  if (!fileBase64 || !mimeType) return jsonError("Falta el archivo.", 400);

  const tiposValidos = ["application/pdf", "image/jpeg", "image/png", "image/webp"];
  if (!tiposValidos.includes(mimeType)) {
    return jsonError("Tipo de archivo no soportado. Use PDF, JPG, PNG o WEBP.", 400);
  }
  if (bytesDeBase64(fileBase64) > MAX_BYTES_ARCHIVO) {
    return jsonError("El archivo pesa más de 15 MB. Use una versión más liviana.", 413);
  }

  try {
    // Lo importante de una póliza está en las primeras páginas: se mandan
    // solo esas (menos tokens y menos tiempo). Si no se puede recortar
    // (cifrado, corrupto) se manda completo.
    const archivo = mimeType === "application/pdf"
      ? await recortarPdf(fileBase64, MAX_PAGINAS_POLIZA)
      : { base64: fileBase64, paginas: null, enviadas: null };
    const resultado = await llamarGemini({
      etiqueta: "extraer-poliza",
      instrucciones: INSTRUCCIONES_BASE + textoCatalogo(catalogoProductos ?? []),
      partes: [{ inlineData: { mimeType, data: archivo.base64 } }],
      schema: RESPONSE_SCHEMA,
      maxOutputTokens: 4096,
    });
    if (!resultado.ok) return jsonError(resultado.error, resultado.status);
    return jsonOk(ajustarTotal(resultado.datos));
  } catch (e) {
    console.error("extraer-poliza: error inesperado", e);
    return jsonError("No se pudo procesar el archivo. Intente de nuevo.", 500);
  }
});
