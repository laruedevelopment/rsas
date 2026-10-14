import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento_polizas/datos/matching_reporte_pago.dart';
import 'package:seguimiento_polizas/datos/poliza.dart';

Poliza p(int id, String? nro, {String? doc, int? aseg}) => Poliza(
      id: id,
      nroPoliza: nro,
      primaPoliza: 1000,
      valorPoliza: 0,
      docCliente: doc,
      asegId: aseg,
    );

void main() {
  group('anexoSiCorresponde', () {
    test('núcleo vacío o póliza vacía', () {
      expect(anexoSiCorresponde('123456', ''), isNull);
      expect(anexoSiCorresponde('123456', '---'), isNull);
      expect(anexoSiCorresponde('', '123456'), isNull);
      expect(anexoSiCorresponde('---', '123456'), isNull);
    });

    test('ceros a la izquierda en núcleo y en póliza', () {
      expect(anexoSiCorresponde('00012345', '12345'), '');
      expect(anexoSiCorresponde('12345', '0012345'), '');
      expect(anexoSiCorresponde('12345-007', '12345'), '7');
    });

    test('anexo cero se conserva como "0"', () {
      expect(anexoSiCorresponde('12345-0', '12345'), '0');
      expect(anexoSiCorresponde('12345-000', '12345'), '0');
    });

    test('nunca por "contiene"', () {
      expect(anexoSiCorresponde('1234567', '234567'), isNull);
      expect(anexoSiCorresponde('400-97-1046', '046'), isNull);
      expect(anexoSiCorresponde('123456-1', '12345'), isNull);
    });

    test('núcleo corto solo si es el número completo', () {
      expect(anexoSiCorresponde('400', '400'), '');
      expect(anexoSiCorresponde('400-97-994000000046-6', '400'), isNull);
      expect(anexoSiCorresponde('400-97-994000000046-6', '97'), isNull);
      expect(anexoSiCorresponde('6', '6'), '');
    });

    test('núcleo en cualquier segmento del número con guiones', () {
      expect(anexoSiCorresponde('400-97-994000000046-6', '994000000046'), '6');
      expect(anexoSiCorresponde('400-97-994000000046', '994000000046'), '');
    });

    test('letras: prefijo AUT y minúsculas', () {
      expect(anexoSiCorresponde('AUT12345', '12345'), '');
      expect(anexoSiCorresponde('aut-12345-2', '12345'), '2');
      expect(anexoSiCorresponde('AUT12345', 'aut12345'), '');
    });

    test('número pegado con anexo del reporte', () {
      expect(
          anexoSiCorresponde('9940000001936', '994000000193',
              anexoReporte: '6'),
          '6');
      expect(anexoSiCorresponde('9940000001936', '994000000193'), isNull);
      expect(
          anexoSiCorresponde('9940000001936', '994000000193',
              anexoReporte: '7'),
          isNull);
      // anexo con ceros
      expect(
          anexoSiCorresponde('99400000019306', '994000000193',
              anexoReporte: '06'),
          '6');
    });

    // BUG probable: el "núcleo" del reporte con separadores (copiado tal cual
    // del número de póliza) se normaliza a un solo bloque y ya no coincide con
    // ningún segmento -> noEncontrada aunque la póliza exista.
    test('núcleo con guiones coincide con la póliza que lo contiene', () {
      expect(anexoSiCorresponde('400-97-994000000046-6', '400-97-994000000046'),
          '6');
    },
        skip:
            'BUG probable: núcleo con separadores nunca matchea (devuelve null)');
  });

  group('mismoDocumento', () {
    test('iguales con distinto formato', () {
      expect(mismoDocumento('900.159.756-1', '9001597561'), isTrue);
      expect(mismoDocumento('abc123', 'ABC-123'), isTrue);
    });
    test('vacíos nunca coinciden', () {
      expect(mismoDocumento('', ''), isFalse);
      expect(mismoDocumento('---', '123456'), isFalse);
    });
    test('NIT con dígito de verificación', () {
      expect(mismoDocumento('900159756', '9001597561'), isTrue);
      expect(mismoDocumento('9001597561', '900159756'), isTrue);
      expect(mismoDocumento('900159756', '900159757'), isFalse);
    });
    test('prefijo corto (<6 dígitos) no se tolera', () {
      expect(mismoDocumento('12345', '123456'), isFalse);
    });
    test('letras en el más largo no se toleran', () {
      expect(mismoDocumento('123456', '123456A'), isFalse);
    });
    test('dos o más dígitos de diferencia no coinciden', () {
      expect(mismoDocumento('900159756', '90015975612'), isFalse);
    });

    // RIESGO: dos cédulas distintas (7 y 8 dígitos) donde una es prefijo de la
    // otra se toman como la misma persona -> un abono podría pasar como
    // "exacta" a la póliza de otro cliente sin pedir confirmación.
    test('cédulas distintas donde una es prefijo de otra', () {
      expect(mismoDocumento('1234567', '12345678'), isFalse);
    }, skip: 'RIESGO: se consideran el mismo documento (falso positivo)');
  });

  group('resolverMatch bordes', () {
    test('sin candidatos -> noEncontrada con mensaje', () {
      final r = resolverMatch(nucleo: '123456', candidatos: []);
      expect(r.estado, EstadoMatch.noEncontrada);
      expect(r.seIncluyeSolo, isFalse);
      expect(r.poliza, isNull);
    });

    test('noEncontrada sugiere las pólizas del cliente', () {
      final del = [p(9, '777777')];
      final r = resolverMatch(
          nucleo: '123456', candidatos: [], polizasDelCliente: del);
      expect(r.estado, EstadoMatch.noEncontrada);
      expect(r.candidatos, del);
    });

    test('candidato con nroPoliza null se ignora', () {
      final r = resolverMatch(nucleo: '123456', candidatos: [p(1, null)]);
      expect(r.estado, EstadoMatch.noEncontrada);
    });

    test('candidatos duplicados por id no generan ambigüedad', () {
      final r = resolverMatch(
          nucleo: '123456', candidatos: [p(1, '123456'), p(1, '123456')]);
      expect(r.estado, EstadoMatch.unicaSinAnexo);
    });

    test('anexo del reporte solo con ceros/símbolos equivale a sin anexo', () {
      final r = resolverMatch(
          nucleo: '123456', anexo: '--', candidatos: [p(1, '123456')]);
      expect(r.estado, EstadoMatch.unicaSinAnexo);
    });

    test('exacta con anexo "00" vs póliza "-0"', () {
      final r = resolverMatch(
          nucleo: '123456', anexo: '00', candidatos: [p(1, '123456-0')]);
      expect(r.estado, EstadoMatch.exacta);
    });

    test(
        'sin anexo en el reporte y varias pólizas -> ambigua, ordenadas por prima',
        () {
      final a = Poliza(
          id: 1, nroPoliza: '123456-1', primaPoliza: 100, valorPoliza: 0);
      final b = Poliza(
          id: 2, nroPoliza: '123456-2', primaPoliza: 5000, valorPoliza: 0);
      final r =
          resolverMatch(nucleo: '123456', primaLinea: 4900, candidatos: [a, b]);
      expect(r.estado, EstadoMatch.ambigua);
      expect(r.candidatos.first.id, 2);
    });

    test('dos pólizas con mismo número y anexo -> ambigua', () {
      final r = resolverMatch(
          nucleo: '123456',
          anexo: '1',
          candidatos: [p(1, '123456-1'), p(2, '123456-1')]);
      expect(r.estado, EstadoMatch.ambigua);
      expect(r.poliza, isNull);
    });

    test('anexo no registrado entre varios', () {
      final r = resolverMatch(
          nucleo: '123456',
          anexo: '9',
          candidatos: [p(1, '123456-1'), p(2, '123456-2')]);
      expect(r.estado, EstadoMatch.anexoNoRegistrado);
      expect(r.motivo, contains('1, 2'));
    });

    test(
        'póliza sin anexo + otra con anexo y reporte con otro anexo -> anexoNoRegistrado',
        () {
      final r = resolverMatch(
          nucleo: '123456',
          anexo: '5',
          candidatos: [p(1, '123456'), p(2, '123456-1')]);
      expect(r.estado, EstadoMatch.anexoNoRegistrado);
    });

    test('póliza sin anexo y reporte con anexo -> revisar', () {
      final r = resolverMatch(
          nucleo: '123456', anexo: '3', candidatos: [p(1, '123456')]);
      expect(r.estado, EstadoMatch.revisar);
      expect(r.poliza!.id, 1);
      expect(r.seIncluyeSolo, isFalse);
    });

    test(
        'documento distinto -> revisar; con DV o formato distinto -> automática',
        () {
      final c = [p(1, '123456-1', doc: '900.159.756-1')];
      expect(
          resolverMatch(
                  nucleo: '123456',
                  anexo: '1',
                  docCliente: '111222333',
                  candidatos: c)
              .estado,
          EstadoMatch.revisar);
      expect(
          resolverMatch(
                  nucleo: '123456',
                  anexo: '1',
                  docCliente: '900159756',
                  candidatos: c)
              .estado,
          EstadoMatch.exacta);
    });

    test('documento faltante en reporte o en póliza no bloquea', () {
      expect(
          resolverMatch(
              nucleo: '123456',
              anexo: '1',
              candidatos: [p(1, '123456-1', doc: '555')]).estado,
          EstadoMatch.exacta);
      expect(
          resolverMatch(
              nucleo: '123456',
              anexo: '1',
              docCliente: '555',
              candidatos: [p(1, '123456-1')]).estado,
          EstadoMatch.exacta);
    });

    test('filtra por aseguradora; las de aseguradora null pasan', () {
      final c = [
        p(1, '123456', aseg: 2),
        p(2, '123456', aseg: 1),
        p(3, '123456')
      ];
      final r =
          resolverMatch(nucleo: '123456', aseguradoraId: 1, candidatos: c);
      expect(r.estado, EstadoMatch.ambigua);
      expect(r.candidatos.map((e) => e.id).toSet(), {2, 3});
    });

    test('número pegado nunca se incluye solo', () {
      final r = resolverMatch(
          nucleo: '994000000193',
          anexo: '6',
          candidatos: [p(1, '9940000001936')]);
      expect(r.estado, EstadoMatch.revisar);
      expect(r.seIncluyeSolo, isFalse);
    });

    test('mismo núcleo en pegado y en formato normal con el mismo anexo', () {
      final r = resolverMatch(nucleo: '994000000193', anexo: '6', candidatos: [
        p(1, '9940000001936'),
        p(2, '994000000193-6'),
      ]);
      // Dos candidatos exactos distintos: debe pedir elegir, no escoger solo.
      expect(r.seIncluyeSolo, isFalse);
    });

    // Comportamiento conservador: "AUT12345" único con núcleo 12345 cae en
    // _esNumeroPegado (segmento != núcleo) y pide revisión aunque coincide.
    test('documenta: AUT12345 con núcleo 12345 va a revisar, no automática',
        () {
      final r = resolverMatch(nucleo: '12345', candidatos: [p(1, 'AUT12345')]);
      expect(r.estado, EstadoMatch.revisar);
    });
  });
}
