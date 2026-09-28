// Edge Function: extraer-reporte-pago
//
// Recibe un reporte de comisiones de una aseguradora (PDF, XLSX o imagen,
// en base64) y le pide a Gemini la cabecera y la lista completa de líneas
// para revisarlas y cargarlas como abonos. La API key de Google vive solo
// acá (secret de Supabase).
//
// Algunos reportes vienen protegidos con contraseña: se desprotegen con la
// contraseña estándar (secret REPORTE_PDF_PASSWORD) antes de enviarlos.

import { decryptPDF, isEncrypted } from "npm:@pdfsmaller/pdf-decrypt@1.0.1";
// SheetJS vendorizado (./xlsx.mjs, copiado tal cual de su CDN oficial,
// https://cdn.sheetjs.com/xlsx-0.20.3/package/xlsx.mjs) — la versión
// publicada en npm (0.18.5) está abandonada y tiene vulnerabilidades
// conocidas (CVE-2023-30533, CVE-2024-22363). Antes se importaba
// directo desde el CDN, pero el bundler de Supabase dejó de permitir
// imports desde hosts fuera de su lista permitida (esm.sh, npm:, jsr:,
// deno.land); vendorizar el archivo evita esa restricción sin bajar a la
// versión vieja de npm. Para actualizar: volver a bajar el .mjs de la
// nueva versión desde cdn.sheetjs.com y reemplazar este archivo.
import * as XLSX from "./xlsx.mjs";
import officeCrypto from "npm:officecrypto-tool@0.0.7";

import {
  bytesDeBase64,
  CORS_HEADERS,
  decodeBase64,
  encodeBase64,
  jsonError,
  jsonOk,
  llamarGemini,
  MAX_BYTES_ARCHIVO,
  usuarioDeLaPeticion,
} from "../_shared/comun.ts";

const PASSWORD_CONOCIDA = Deno.env.get("REPORTE_PDF_PASSWORD") ?? "";

const MIME_XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

/// Máximo de caracteres de tabla que se envían a la IA desde un Excel (unas
/// 1.500 filas). Evita un costo desbordado con hojas enormes.
const MAX_CARACTERES_XLSX = 400_000;

/// Desprotege (si hace falta) y convierte un XLSX a texto (un CSV por hoja
/// visible, sin filas vacías): Gemini no lee el binario de un Excel.
async function leerXlsxComoTexto(bytesOriginales: Uint8Array): Promise<string> {
  let bytes = bytesOriginales;
  if (officeCrypto.isEncrypted(bytes)) {
    if (!PASSWORD_CONOCIDA) throw new Error("sin contraseña configurada");
    bytes = await officeCrypto.decrypt(bytes, { password: PASSWORD_CONOCIDA });
  }

  const libro = XLSX.read(bytes, { type: "array" });
  const ocultas = new Set(
    (libro.Workbook?.Sheets ?? [])
      .filter((s: { Hidden?: number }) => (s.Hidden ?? 0) !== 0)
      .map((s: { name?: string }) => s.name),
  );
  const texto = libro.SheetNames
    .filter((nombre: string) => !ocultas.has(nombre))
    .map((nombre: string) => {
      const csv = XLSX.utils.sheet_to_csv(libro.Sheets[nombre], { blankrows: false, strip: true })
        .split("\n")
        .map((fila: string) => fila.replace(/,+$/, ""))
        .filter((fila: string) => fila.trim() !== "")
        .join("\n");
      return `--- Hoja: ${nombre} ---\n${csv}`;
    })
    .join("\n\n");

  if (texto.length > MAX_CARACTERES_XLSX) throw new Error("excel demasiado grande");
  return texto;
}

const LINEA_SCHEMA = {
  type: "OBJECT",
  properties: {
    nro_poliza: {
      type: "STRING",
      nullable: true,
      description:
        "Número de póliza exactamente como aparece en la columna 'Póliza' de esa fila (suele " +
        "ser solo el núcleo numérico, ej. '994000000193', '101011263'). No le agregue el anexo " +
        "ni otros segmentos.",
    },
    anexo: {
      type: "STRING",
      nullable: true,
      description:
        "Número de anexo/endoso de esa fila, de la columna 'End', 'End.', 'Endoso' o 'Anexo' " +
        "(suele estar junto a la columna Póliza; ej. '0', '1', '6', '16'). Una misma póliza " +
        "aparece en varias filas con anexos distintos y cada anexo es un registro distinto: " +
        "cópielo en cada fila, también cuando es '0'. No use 'Certificado', 'Recibo', " +
        "'Formulario' ni 'Transacción'. Null si el reporte no tiene columna de anexo.",
    },
    doc_cliente: {
      type: "STRING",
      nullable: true,
      description:
        "Documento del cliente de la fila (columna 'Docum', 'Doc. Tomador', 'Documento' o el " +
        "número junto al nombre del asegurado), solo dígitos. Si el nombre y el documento " +
        "vienen en la misma celda, sepárelos.",
    },
    nombre_cliente: { type: "STRING", nullable: true, description: "Nombre del asegurado/tomador de la fila." },
    nombre_ramo: { type: "STRING", nullable: true, description: "Ramo de la fila tal como aparece (texto o código)." },
    vlrprima_poliza: { type: "NUMBER", nullable: true, description: "Prima cobrada/base de la fila." },
    vlrabono_prima: {
      type: "NUMBER",
      nullable: true,
      description: "Valor abonado de la prima en este corte; el mismo que vlrprima_poliza si el reporte no los distingue.",
    },
    porccomision: { type: "NUMBER", nullable: true, description: "Porcentaje de comisión (columna 'Pje', '% Comisión')." },
    vlrcomision: { type: "NUMBER", nullable: true, description: "Comisión acreditada de la fila." },
    porccomad: { type: "NUMBER", nullable: true, description: "Porcentaje de comisión adicional, solo si hay columna aparte." },
    vlrcomad: { type: "NUMBER", nullable: true, description: "Valor de comisión adicional, solo si hay columna aparte." },
    num_factura: {
      type: "STRING",
      nullable: true,
      description: "Número de recibo/factura/transacción de la fila (columna 'Recibo', 'Transacción', 'Formulario').",
    },
    fecha_pago: { type: "STRING", nullable: true, description: "Fecha de la fila ('Fecha', 'Fecha Recibo', 'Fecha Recaudo'), YYYY-MM-DD." },
  },
};

const CABECERA_SCHEMA = {
  type: "OBJECT",
  properties: {
    nombre_aseguradora: { type: "STRING", nullable: true, description: "Aseguradora que emite el reporte." },
    nombre_intermediario: {
      type: "STRING",
      nullable: true,
      description:
        "Intermediario al que va dirigido el reporte, tal como está impreso en la cabecera " +
        "(puede traer un código antes del nombre, ej. '5728 - SERRANO MANTILLA LUZ STELLA').",
    },
    fecha_reporte: { type: "STRING", nullable: true, description: "Fecha del reporte, YYYY-MM-DD." },
    fecha_inicio_periodo: {
      type: "STRING",
      nullable: true,
      description: "Inicio del período, YYYY-MM-DD. Null si el documento solo trae una fecha de corte.",
    },
    fecha_fin_periodo: {
      type: "STRING",
      nullable: true,
      description: "Fin del período (o fecha de corte si hay una sola), YYYY-MM-DD.",
    },
    vlr_prima_total: {
      type: "NUMBER",
      nullable: true,
      description:
        "Total GENERAL de prima impreso en el reporte ('Total Prima', 'Total Saldo'). Null si " +
        "no hay un total general impreso (no sume líneas ni use subtotales por ramo).",
    },
    vlr_comision_total: {
      type: "NUMBER",
      nullable: true,
      description:
        "Total GENERAL de comisión impreso ('Total Comisión Acreditada', 'Valor Comisión'). " +
        "Null si no hay un total general impreso (no sume líneas).",
    },
  },
};

const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    cabecera: CABECERA_SCHEMA,
    lineas: { type: "ARRAY", items: LINEA_SCHEMA },
  },
  required: ["cabecera", "lineas"],
};

const INSTRUCCIONES =
  "Usted extrae reportes de comisiones que las aseguradoras colombianas envían a un " +
  "intermediario de seguros. Cada aseguradora usa su propio formato: identifique las " +
  "columnas de este reporte por su encabezado o posición.\n" +
  "- Extraiga la cabecera y TODAS las filas de pólizas: una línea por movimiento, aunque " +
  "falten datos. Las reversiones y anulaciones son líneas propias con signo contrario: no " +
  "las omita ni las compense entre sí.\n" +
  "- NO incluya en 'lineas' filas de subtotal o total (por ramo, sección o general), ni " +
  "encabezados repetidos entre páginas.\n" +
  "- Números en formato colombiano: el punto separa miles y la coma los decimales " +
  "(1.234.567,89 → 1234567.89). Los negativos pueden venir con '-' o entre paréntesis: " +
  "'(168.093,5)' → -168093.5.\n" +
  "- Fechas en día/mes/año (05/03/2026 → 2026-03-05).\n" +
  "- Si un dato no aparece, devuelva null. Nunca invente valores.";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonError("Método no permitido.", 405);

  if (!(await usuarioDeLaPeticion(req))) {
    return jsonError("Su sesión no es válida o ya venció. Inicie sesión de nuevo.", 401);
  }

  let body: { fileBase64?: string; mimeType?: string };
  try {
    body = await req.json();
  } catch {
    return jsonError("Petición inválida.", 400);
  }

  const { fileBase64, mimeType } = body;
  if (!fileBase64 || !mimeType) return jsonError("Falta el archivo.", 400);

  const tiposValidos = ["application/pdf", MIME_XLSX, "image/jpeg", "image/png", "image/webp"];
  if (!tiposValidos.includes(mimeType)) {
    return jsonError("Tipo de archivo no soportado. Use PDF, XLSX, JPG, PNG o WEBP.", 400);
  }
  if (bytesDeBase64(fileBase64) > MAX_BYTES_ARCHIVO) {
    return jsonError("El archivo pesa más de 15 MB. Use una versión más liviana.", 413);
  }

  // PDF/imagen van como archivo (Gemini los lee visualmente); un Excel se
  // manda como texto ya extraído acá.
  let partes: Record<string, unknown>[];
  try {
    if (mimeType === MIME_XLSX) {
      const texto = await leerXlsxComoTexto(decodeBase64(fileBase64));
      partes = [{ text: `Contenido del archivo Excel:\n\n${texto}` }];
    } else if (mimeType === "application/pdf") {
      let data = fileBase64;
      const bytes = decodeBase64(fileBase64);
      if ((await isEncrypted(bytes)).encrypted) {
        if (!PASSWORD_CONOCIDA) {
          console.error("extraer-reporte-pago: PDF protegido y falta el secret REPORTE_PDF_PASSWORD");
          return jsonError("El PDF tiene contraseña y no hay una contraseña configurada en el servidor.", 500);
        }
        data = encodeBase64(await decryptPDF(bytes, PASSWORD_CONOCIDA));
      }
      partes = [{ inlineData: { mimeType, data } }];
    } else {
      partes = [{ inlineData: { mimeType, data: fileBase64 } }];
    }
  } catch (e) {
    console.error("extraer-reporte-pago: no se pudo leer el archivo", e);
    const msg = String(e).includes("demasiado grande")
      ? "El Excel es demasiado grande para leerlo de una vez. Divídalo en partes más pequeñas."
      : "No se pudo abrir el archivo (¿contraseña distinta o archivo dañado?).";
    return jsonError(msg, 400);
  }

  try {
    const resultado = await llamarGemini({
      etiqueta: "extraer-reporte-pago",
      instrucciones: INSTRUCCIONES,
      partes,
      schema: RESPONSE_SCHEMA,
      // ~150 tokens por línea: alcanza para unas 200 líneas. Si un reporte
      // lo supera, se avisa al usuario (MAX_TOKENS) en vez de cortar callado.
      maxOutputTokens: 32768,
    });
    if (!resultado.ok) return jsonError(resultado.error, resultado.status);
    return jsonOk(resultado.datos);
  } catch (e) {
    console.error("extraer-reporte-pago: error inesperado", e);
    return jsonError("No se pudo procesar el archivo. Intente de nuevo.", 500);
  }
});
