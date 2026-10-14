import '../datos/catalogos.dart';

/// Minúsculas, sin tildes, sin signos de puntuación y con un solo espacio
/// entre palabras: "Bogotá, D.C." y "bogota d c" dan lo mismo.
String normalizarTexto(String s) {
  const de = 'áàäâãéèëêíìïîóòöôõúùüûñÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑ';
  const a = 'aaaaaeeeeiiiiooooouuuunAAAAAEEEEIIIIOOOOOUUUUN';
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final i = de.indexOf(c);
    b.write(i >= 0 ? a[i] : c);
  }
  return b
      .toString()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

/// Municipio que corresponde al texto escrito, o null.
///
/// Solo asigna cuando no hay duda: coincidencia exacta única (sin tildes ni
/// mayúsculas) o, si no hay exacta, un único municipio que empiece por el
/// texto. Si hay varios con el mismo nombre (ej. "Santa Rosa" en distintos
/// departamentos) devuelve null para obligar a elegir de la lista.
Municipio? resolverMunicipio(List<Municipio> municipios, String texto) {
  final q = normalizarTexto(texto);
  if (q.isEmpty) return null;
  final exactos =
      municipios.where((m) => normalizarTexto(m.nombreMunic) == q).toList();
  if (exactos.length == 1) return exactos.first;
  if (exactos.length > 1) return null;
  final empieza = municipios
      .where((m) => normalizarTexto(m.nombreMunic).startsWith(q))
      .toList();
  return empieza.length == 1 ? empieza.first : null;
}
