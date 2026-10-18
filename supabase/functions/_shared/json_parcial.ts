/// Rescata los campos COMPLETOS de un JSON que la IA dejó cortado a la mitad
/// (por ejemplo, porque se enredó escribiendo un texto largo y llegó al tope de
/// salida). El schema obliga a la IA a escribir los campos en orden, así que casi
/// siempre lo que se pierde es el último campo y todo lo anterior está bien.
///
/// Devuelve el objeto con los campos terminados, o null si no hay nada rescatable.
export function rescatarJsonTruncado(texto: string): Record<string, unknown> | null {
  const t = texto.trim();
  if (!t.startsWith("{")) return null;

  // Ya viene completo.
  try {
    const completo = JSON.parse(t);
    if (completo && typeof completo === "object") return completo as Record<string, unknown>;
  } catch { /* se cortó: se rescata abajo */ }

  // Posiciones de las comas del primer nivel (fuera de cadenas de texto).
  const comas: number[] = [];
  let enCadena = false;
  let escape = false;
  let profundidad = 0;
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (enCadena) {
      if (escape) escape = false;
      else if (c === "\\") escape = true;
      else if (c === '"') enCadena = false;
      continue;
    }
    if (c === '"') enCadena = true;
    else if (c === "{" || c === "[") profundidad++;
    else if (c === "}" || c === "]") profundidad--;
    else if (c === "," && profundidad === 1) comas.push(i);
  }

  // Desde la última coma hacia atrás: el primer corte que forme un JSON válido.
  for (let k = comas.length - 1; k >= 0; k--) {
    try {
      const o = JSON.parse(t.slice(0, comas[k]) + "}");
      if (o && typeof o === "object") return o as Record<string, unknown>;
    } catch { /* prueba con la coma anterior */ }
  }
  return null;
}
