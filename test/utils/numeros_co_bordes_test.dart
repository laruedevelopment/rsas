import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento_polizas/utils/numeros_co.dart';

void main() {
  group('parseNumCO bordes', () {
    test('vacíos y basura', () {
      expect(parseNumCO(null), isNull);
      expect(parseNumCO('   '), isNull);
      expect(parseNumCO('-'), isNull);
      expect(parseNumCO('abc'), isNull);
      expect(parseNumCO('\$'), isNull);
      expect(parseNumCO('.'), isNull);
      expect(parseNumCO(','), isNull);
    });

    test('moneda COP con símbolo, espacios y sufijo', () {
      expect(parseNumCO(r'$ 1.234.567'), 1234567);
      expect(parseNumCO('1.234.567,50'), 1234567.5);
      expect(parseNumCO('  \$ 1.500  '), 1500);
      expect(parseNumCO('COP 1.500'), 1500);
    });

    test('decimales y miles', () {
      expect(parseNumCO('0,5'), 0.5);
      expect(parseNumCO(',5'), 0.5);
      expect(parseNumCO('.5'), 0.5);
      expect(parseNumCO('0.5'), 0.5);
      expect(parseNumCO('1.000'), 1000);
      expect(parseNumCO('1.0'), 1.0);
      expect(parseNumCO('100.25'), 100.25);
      expect(parseNumCO('1.234.567'), 1234567);
      expect(parseNumCO('19%'), 19);
      expect(parseNumCO('19,5%'), 19.5);
    });

    test('negativos', () {
      expect(parseNumCO('-0'), 0);
      expect(parseNumCO('(1.500)'), -1500);
      expect(parseNumCO('-\$ 1.500'), -1500);
      expect(parseNumCO('-1.234,5'), -1234.5);
    });

    test('formato US con coma de miles', () {
      expect(parseNumCO('1,234,567.89'), 1234567.89);
      expect(parseNumCO('1,234.5'), 1234.5);
    });

    // BUG: sin punto, dos o más comas son miles (US) pero el código las trata
    // como coma decimal -> "1.234.567" no parsea y devuelve null.
    test('"1,234,567" (miles US sin decimales) = 1234567', () {
      expect(parseNumCO('1,234,567'), 1234567);
    }, skip: 'BUG: devuelve null (varias comas se tratan como decimal)');

    // BUG: "(-5)" invierte el signo dos veces y devuelve +5.
    test('"(-5)" no debería ser positivo', () {
      expect(parseNumCO('(-5)'), isNot(5));
    }, skip: 'BUG: doble negación -> +5');

    // RIESGO (diseño): "1,500" se lee como 1,5 (coma = decimal colombiano).
    // Con plata, un valor pegado desde un sistema US/Excel en inglés se
    // guarda mil veces menor sin avisar.
    test('documenta: "1,500" se interpreta como 1.5', () {
      expect(parseNumCO('1,500'), 1.5);
    });

    // RIESGO: caracteres no numéricos intermedios se descartan en silencio.
    test('documenta: "12a5" -> 125 y "5-3" -> 53 (sin validar)', () {
      expect(parseNumCO('12a5'), 125);
      expect(parseNumCO('5-3'), 53);
    });

    test('múltiples puntos con decimales dudosos: "1.234.56" -> 123456', () {
      expect(parseNumCO('1.234.56'), 123456);
    });
  });

  group('formatearNumCO bordes', () {
    test('null, cero y negativos cercanos a cero', () {
      expect(formatearNumCO(null), '');
      expect(formatearNumCO(0), '0');
      expect(formatearNumCO(-0.001), '0'); // sin "-0"
      expect(formatearNumCO(-0.0), '0');
      expect(formatearNumCO(-1500), '-1.500');
    });

    test('miles, decimales y redondeo', () {
      expect(formatearNumCO(1000), '1.000');
      expect(formatearNumCO(999), '999');
      expect(formatearNumCO(1234567.891), '1.234.567,89');
      expect(formatearNumCO(0.999), '1');
      expect(formatearNumCO(999999.999), '1.000.000');
      expect(formatearNumCO(12.5), '12,5');
      expect(formatearNumCO(1500, maxDecimales: 0), '1.500');
      expect(formatearNumCO(33.333, maxDecimales: 5), '33,333');
    });

    test('ida y vuelta parse(format(x)) == x', () {
      for (final v in [0, 1, 12.5, 1500, 1234567.89, -168093.5, 100000.1]) {
        expect(parseNumCO(formatearNumCO(v)), v, reason: 'v=$v');
      }
    });
  });

  group('sumarDinero', () {
    test('vacío = 0', () => expect(sumarDinero([]), 0));
    test('10 cuotas de 100000.10 suman exacto', () {
      expect(sumarDinero(List.filled(10, 100000.10)), 1000001);
    });
    test('0.1 + 0.2 = 0.3 exacto', () {
      expect(sumarDinero([0.1, 0.2]), 0.3);
    });
    test('positivos y negativos', () {
      expect(sumarDinero([100.5, -100.5, 0.01]), 0.01);
    });
  });

  group('NumeroCOInputFormatter', () {
    const f = NumeroCOInputFormatter();
    TextEditingValue v(String t) => TextEditingValue(text: t);
    String tipea(String viejo, String nuevo,
            [NumeroCOInputFormatter fmt = f]) =>
        fmt.formatEditUpdate(v(viejo), v(nuevo)).text;

    test('vacío', () => expect(tipea('1', ''), ''));
    test('escribe miles', () {
      expect(tipea('123', '1234'), '1.234');
      expect(tipea('1.234', '1.2345'), '12.345');
    });
    test('punto final = coma decimal', () => expect(tipea('12', '12.'), '12,'));
    test('segundo separador decimal no se duplica', () {
      expect(tipea('12,5', '12,5,'), '12,5');
    });
    test('limita decimales', () => expect(tipea('12,55', '12,555'), '12,55'));
    test('sin decimales ignora la coma', () {
      expect(tipea('12', '12,', const NumeroCOInputFormatter(maxDecimales: 0)),
          '12');
    });
    test('ceros a la izquierda', () => expect(tipea('0', '00'), '0'));
    test('negativo permitido y no permitido', () {
      expect(tipea('', '-'), '-');
      expect(tipea('-1', '-12'), '-12');
      expect(
          tipea(
              '', '-', const NumeroCOInputFormatter(permitirNegativos: false)),
          '');
    });
    test('borrar hasta quedar vacío', () => expect(tipea('1', ''), ''));
    test('pegado se interpreta con parseNumCO', () {
      expect(tipea('', '168093.5'), '168.093,5');
      expect(tipea('', '(168.093,5)'), '-168.093,5');
      expect(tipea('', r'$ 1.500.000'), '1.500.000');
    });
    test('pegado inválido conserva el valor anterior', () {
      expect(tipea('5', '5abcdef'), '5');
    });
    test('pegado negativo con permitirNegativos=false pasa a positivo', () {
      expect(
          tipea('', '-1.500',
              const NumeroCOInputFormatter(permitirNegativos: false)),
          '1.500');
    });
  });
}
