import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento_polizas/datos/catalogos.dart';
import 'package:seguimiento_polizas/utils/municipios.dart';

void main() {
  final lista = [
    Municipio(id: 1, nombreMunic: 'BUCARAMANGA'),
    Municipio(id: 2, nombreMunic: 'Moniquirá'),
    Municipio(id: 3, nombreMunic: 'Santa Rosa'),
    Municipio(id: 4, nombreMunic: 'Santa Rosa'),
    Municipio(id: 5, nombreMunic: 'Calima'),
    Municipio(id: 6, nombreMunic: 'Cali'),
    Municipio(id: 7, nombreMunic: 'Bogotá, D.C.'),
  ];

  test('ignora tildes, mayúsculas y espacios', () {
    expect(resolverMunicipio(lista, 'moniquira')?.id, 2);
    expect(resolverMunicipio(lista, '  Bucaramanga '), isNotNull);
    expect(resolverMunicipio(lista, 'BUCARAMANGA')?.id, 1);
  });

  test('puntuación no impide la coincidencia', () {
    expect(resolverMunicipio(lista, 'bogota d c')?.id, 7);
    expect(resolverMunicipio(lista, 'Bogotá D.C.')?.id, 7);
  });

  test('nombres repetidos no se resuelven solos', () {
    expect(resolverMunicipio(lista, 'Santa Rosa'), isNull);
  });

  test('exacto gana sobre prefijo; prefijo único se acepta', () {
    expect(resolverMunicipio(lista, 'cali')?.id, 6);
    expect(resolverMunicipio(lista, 'moniq')?.id, 2);
  });

  test('texto vacío o inexistente da null', () {
    expect(resolverMunicipio(lista, ''), isNull);
    expect(resolverMunicipio(lista, 'xyz'), isNull);
    // "ca" empieza varios (Calima, Cali) → ambiguo
    expect(resolverMunicipio(lista, 'ca'), isNull);
  });
}
