import { decodeBase64, encodeBase64 } from "./comun.ts";
import { PDFDocument } from "npm:pdf-lib@1.17.1";

// ── PDF ─────────────────────────────────────────────────────────────────────

/// Deja solo las primeras [maxPaginas] páginas de un PDF (base64). Si el PDF
/// tiene esas páginas o menos, o no se puede leer (cifrado, dañado), devuelve
/// el original: recortar es solo una optimización, nunca debe romper la lectura.
export async function recortarPdf(
  base64: string,
  maxPaginas: number,
): Promise<{ base64: string; paginas: number | null; enviadas: number | null }> {
  try {
    const origen = await PDFDocument.load(decodeBase64(base64));
    const total = origen.getPageCount();
    if (total <= maxPaginas) return { base64, paginas: total, enviadas: total };
    const nuevo = await PDFDocument.create();
    const copiadas = await nuevo.copyPages(origen, Array.from({ length: maxPaginas }, (_, i) => i));
    copiadas.forEach((p) => nuevo.addPage(p));
    const salida = encodeBase64(await nuevo.save());
    console.log(`recortarPdf: ${total} páginas → ${maxPaginas}`);
    return { base64: salida, paginas: total, enviadas: maxPaginas };
  } catch (e) {
    console.warn("recortarPdf: se envía completo (", String(e).slice(0, 120), ")");
    return { base64, paginas: null, enviadas: null };
  }
}
