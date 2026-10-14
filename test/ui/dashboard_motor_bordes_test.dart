import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento_polizas/datos/poliza.dart';
import 'package:seguimiento_polizas/datos/repositorio_dashboard.dart';
import 'package:seguimiento_polizas/ui/dashboard/dashboard_motor.dart';

Poliza pol(
  int id, {
  num prima = 1000,
  DateTime? exp,
  DateTime? ini,
  DateTime? fin,
  int? cliente = 1,
  int? ramo = 1,
  String estado = 'I',
  num? pagada,
  int? asesor = 1,
  DateTime? creado,
}) =>
    Poliza(
      id: id,
      primaPoliza: prima,
      valorPoliza: 0,
      fexpPoliza: exp,
      finiPoliza: ini,
      ffinPoliza: fin,
      clienteId: cliente,
      nombreCliente: cliente == null ? null : 'Cliente $cliente',
      ramoId: ramo,
      nombreRamo: ramo == null ? null : 'Ramo $ramo',
      nombreAseg: 'Sura',
      asesorId: asesor,
      nombreAsesor: asesor == null ? null : 'Asesor $asesor',
      estadoPolizaId: estado,
      vlrprimapagadaPoliza: pagada,
      fcreado: creado,
    );

void main() {
  final hoy = DateTime(2026, 10, 14);

  group('rangoComparacion', () {
    test('un solo día compara contra el día anterior', () {
      final r = MotorDash.rangoComparacion(DateTime(2026, 10, 14),
          DateTime(2026, 10, 14), Comparar.periodoAnterior)!;
      expect(r.$1, DateTime(2026, 10, 13));
      expect(r.$2, DateTime(2026, 10, 13));
    });

    test('un solo día 1 de mes no se confunde con mes completo', () {
      final r = MotorDash.rangoComparacion(DateTime(2026, 3, 1),
          DateTime(2026, 3, 1), Comparar.periodoAnterior)!;
      expect(r.$1, DateTime(2026, 2, 28));
      expect(r.$2, DateTime(2026, 2, 28));
    });

    test('trimestre que cruza el año (nov-ene) -> 3 meses previos', () {
      final r = MotorDash.rangoComparacion(DateTime(2025, 11, 1),
          DateTime(2026, 1, 31), Comparar.periodoAnterior)!;
      expect(r.$1, DateTime(2025, 8, 1));
      expect(r.$2, DateTime(2025, 10, 31));
    });

    test('enero completo -> diciembre del año anterior', () {
      final r = MotorDash.rangoComparacion(DateTime(2026, 1, 1),
          DateTime(2026, 1, 31), Comparar.periodoAnterior)!;
      expect(r.$1, DateTime(2025, 12, 1));
      expect(r.$2, DateTime(2025, 12, 31));
    });

    test('marzo completo -> febrero (28 o 29 días)', () {
      final r = MotorDash.rangoComparacion(DateTime(2024, 3, 1),
          DateTime(2024, 3, 31), Comparar.periodoAnterior)!;
      expect(r.$1, DateTime(2024, 2, 1));
      expect(r.$2, DateTime(2024, 2, 29));
    });

    test('rango arbitrario de 30 días cruzando fin de año', () {
      final r = MotorDash.rangoComparacion(DateTime(2026, 1, 10),
          DateTime(2026, 2, 8), Comparar.periodoAnterior)!;
      expect(r.$2, DateTime(2026, 1, 9));
      expect(r.$1, DateTime(2025, 12, 11));
    });

    test('ninguno -> null', () {
      expect(
          MotorDash.rangoComparacion(
              DateTime(2026, 1, 1), DateTime(2026, 1, 2), Comparar.ninguno),
          isNull);
    });

    test('año anterior de un rango normal', () {
      final r = MotorDash.rangoComparacion(
          DateTime(2026, 9, 1), DateTime(2026, 9, 30), Comparar.anioAnterior)!;
      expect(r.$1, DateTime(2025, 9, 1));
      expect(r.$2, DateTime(2025, 9, 30));
    });

    // BUG: DateTime(2023, 2, 29) se desborda a 1-mar-2023, así que febrero
    // 2024 completo se compara contra 1-feb..1-mar-2023 (29 días en vez de 28).
    test('año anterior de febrero bisiesto completo no desborda a marzo', () {
      final r = MotorDash.rangoComparacion(
          DateTime(2024, 2, 1), DateTime(2024, 2, 29), Comparar.anioAnterior)!;
      expect(r.$1, DateTime(2023, 2, 1));
      expect(r.$2, DateTime(2023, 2, 28));
    });
  });

  group('calcular con datos vacíos / bordes', () {
    test('sin pólizas ni abonos: todo en cero y sin división por cero', () {
      final m = MotorDash([], null, hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: DateTime(2026, 9, 1), hasta: DateTime(2026, 9, 30)));
      expect(r.actual.n, 0);
      expect(r.actual.ticket, 0);
      expect(r.actual.prima, 0);
      expect(r.pareto, isEmpty);
      expect(r.concentracionTop10, 0);
      expect(r.tasaRenovacion, isNull);
      expect(r.matriz, isEmpty);
      expect(r.comp, isNotNull);
      expect(r.comp!.n, 0);
      expect(r.venceN.length, 12);
      expect(m.rangoTotal(), isNull);
      expect(m.calidad().total, 0);
    });

    test('abonos null: recaudo y comisión en 0', () {
      final m = MotorDash([pol(1, exp: DateTime(2026, 9, 5))], null, hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: DateTime(2026, 9, 1), hasta: DateTime(2026, 9, 30)));
      expect(r.actual.recaudo, 0);
      expect(r.actual.comision, 0);
    });

    test('período de un solo día incluye pólizas de ese día y nada más', () {
      final m = MotorDash([
        pol(1, exp: DateTime(2026, 9, 14)),
        pol(2, exp: DateTime(2026, 9, 15)),
        pol(3, exp: DateTime(2026, 9, 13)),
      ], null, hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: DateTime(2026, 9, 14), hasta: DateTime(2026, 9, 14)));
      expect(r.actual.n, 1);
      expect(r.actual.primaMes.length, 1);
      expect(r.comp!.n, 1); // 13-sep
      expect(r.meses, [DateTime(2026, 9, 1)]);
    });

    test('rango que cruza el año: un bucket por mes y meses con año correcto',
        () {
      final m = MotorDash([
        pol(1, prima: 100, exp: DateTime(2025, 12, 31)),
        pol(2, prima: 200, exp: DateTime(2026, 1, 1)),
        pol(3, prima: 400, exp: DateTime(2026, 2, 28)),
      ], null, hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: DateTime(2025, 12, 1),
          hasta: DateTime(2026, 2, 28),
          comparar: Comparar.ninguno));
      expect(r.actual.primaMes, [100, 200, 400]);
      expect(r.actual.nMes, [1, 1, 1]);
      expect(r.meses,
          [DateTime(2025, 12, 1), DateTime(2026, 1, 1), DateTime(2026, 2, 1)]);
      expect(r.comp, isNull);
    });

    test('mismo mes de distinto año no se mezcla en los buckets', () {
      final m = MotorDash([
        pol(1, prima: 100, exp: DateTime(2025, 9, 10)),
        pol(2, prima: 300, exp: DateTime(2026, 9, 10)),
      ], null, hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: DateTime(2026, 9, 1),
          hasta: DateTime(2026, 9, 30),
          comparar: Comparar.anioAnterior));
      expect(r.actual.prima, 300);
      expect(r.comp!.prima, 100);
    });

    test('fecha de producción cae a inicio de vigencia y luego a fcreado', () {
      final conIni = pol(1, ini: DateTime(2026, 9, 3));
      final conCreado = pol(2, creado: DateTime.utc(2026, 9, 4, 12));
      final sinNada = pol(3);
      expect(fechaProduccion(conIni), DateTime(2026, 9, 3));
      expect(fechaProduccion(conCreado), isNotNull);
      expect(fechaProduccion(sinNada), isNull);
      final m = MotorDash([conIni, conCreado, sinNada], null, hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: DateTime(2026, 9, 1),
          hasta: DateTime(2026, 9, 30),
          comparar: Comparar.ninguno));
      expect(r.actual.n, 2); // la que no tiene ninguna fecha queda fuera
      expect(m.calidad().total, 3);
    });

    test('póliza en el último y primer día del rango (límites inclusivos)', () {
      final m = MotorDash([
        pol(1, exp: DateTime(2026, 9, 1)),
        pol(2, exp: DateTime(2026, 9, 30)),
        pol(3, exp: DateTime(2026, 8, 31)),
        pol(4, exp: DateTime(2026, 10, 1)),
      ], null, hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: DateTime(2026, 9, 1),
          hasta: DateTime(2026, 9, 30),
          comparar: Comparar.ninguno));
      expect(r.actual.polizas.map((p) => p.id).toSet(), {1, 2});
    });

    // BUG: rango invertido (desde > hasta en meses distintos) -> List.filled
    // con longitud negativa lanza RangeError y la pantalla se rompe.
    test('rango invertido no lanza excepción', () {
      final m = MotorDash([pol(1, exp: DateTime(2026, 9, 5))], null, hoy: hoy);
      expect(
          () => m.calcular(FiltrosDash(
              desde: DateTime(2026, 11, 1),
              hasta: DateTime(2026, 8, 1),
              comparar: Comparar.ninguno)),
          returnsNormally);
    });

    test('rango invertido se interpreta al revés (septiembre–octubre)', () {
      final m = MotorDash([pol(1, exp: DateTime(2026, 9, 5))], null, hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: DateTime(2026, 10, 1),
          hasta: DateTime(2026, 9, 1),
          comparar: Comparar.ninguno));
      expect(r.actual.n, 1);
    });
  });

  group('clientes y filtros', () {
    test('clientes sin clienteId con mismo nombre se agrupan; sin nombre no',
        () {
      final a = pol(1, cliente: null, exp: DateTime(2026, 9, 5));
      final b = pol(2, cliente: null, exp: DateTime(2026, 9, 6));
      // sin nombre -> clave por id de póliza: dos distintos
      expect(MotorDash.claveCliente(a), isNot(MotorDash.claveCliente(b)));
      final r = MotorDash([a, b], null, hoy: hoy).calcular(FiltrosDash(
          desde: DateTime(2026, 9, 1),
          hasta: DateTime(2026, 9, 30),
          comparar: Comparar.ninguno));
      expect(r.actual.clientes, 2);
      expect(r.clientesTop.first.nombre, 'Sin cliente');
    });

    test('filtro por dimensión "Sin asesor" encuentra pólizas sin asesor', () {
      final m = MotorDash([
        pol(1, exp: DateTime(2026, 9, 5), asesor: null),
        pol(2, exp: DateTime(2026, 9, 5)),
      ], null, hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: DateTime(2026, 9, 1),
          hasta: DateTime(2026, 9, 30),
          comparar: Comparar.ninguno,
          asesor: 'Sin asesor'));
      expect(r.actual.n, 1);
    });

    test('concentración top10 = 100% con menos de 10 clientes', () {
      final m = MotorDash([
        pol(1, prima: 100, exp: DateTime(2026, 9, 5), cliente: 1),
        pol(2, prima: 300, exp: DateTime(2026, 9, 5), cliente: 2),
      ], null, hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: DateTime(2026, 9, 1),
          hasta: DateTime(2026, 9, 30),
          comparar: Comparar.ninguno));
      expect(r.concentracionTop10, closeTo(100, 1e-9));
      expect(r.pareto.last, closeTo(100, 1e-9));
      expect(r.pareto.first, closeTo(75, 1e-9));
    });

    test(
        'cliente nuevo: su primera póliza el primer día del período cuenta nuevo',
        () {
      final m = MotorDash([
        pol(1, exp: DateTime(2026, 9, 1), cliente: 1),
        pol(2, exp: DateTime(2026, 8, 31), cliente: 2),
        pol(3, exp: DateTime(2026, 9, 10), cliente: 2),
      ], null, hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: DateTime(2026, 9, 1),
          hasta: DateTime(2026, 9, 30),
          comparar: Comparar.ninguno));
      expect(r.clientesNuevos, 1);
      expect(r.clientesRecurrentes, 1);
    });
  });

  group('cartera', () {
    test('pagado mayor que la prima se recorta; sin pagado = todo saldo', () {
      final m = MotorDash([
        pol(1, prima: 1000, exp: DateTime(2026, 9, 5), pagada: 5000),
        pol(2, prima: 500, exp: DateTime(2026, 9, 5), pagada: null),
        pol(3, prima: 0, exp: DateTime(2026, 9, 5)),
        pol(4, prima: -200, exp: DateTime(2026, 9, 5)),
      ], null, hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: DateTime(2026, 9, 1),
          hasta: DateTime(2026, 9, 30),
          comparar: Comparar.ninguno));
      expect(r.carteraPrima, 1500);
      expect(r.carteraPagada, 1000);
      expect(r.carteraSaldo, 500);
    });

    test('aging: frontera de 30/60/90/180 días y vigencia futura', () {
      final base = DateTime(2026, 10, 14);
      DateTime atras(int d) => base.subtract(Duration(days: d));
      final m = MotorDash([
        pol(1, prima: 1, exp: atras(30), ini: atras(30)),
        pol(2, prima: 10, exp: atras(31), ini: atras(31)),
        pol(3, prima: 100, exp: atras(60), ini: atras(60)),
        pol(4, prima: 1000, exp: atras(90), ini: atras(90)),
        pol(5, prima: 10000, exp: atras(180), ini: atras(180)),
        pol(6, prima: 100000, exp: atras(181), ini: atras(181)),
        pol(7,
            prima: 1000000,
            exp: atras(1),
            ini: base.add(const Duration(days: 5))),
      ], null, hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: atras(200), hasta: base, comparar: Comparar.ninguno));
      final a = {for (final e in r.aging) e.key: e.value};
      expect(a['0–30 días'], 1);
      expect(a['31–60 días'], 110);
      expect(a['61–90 días'], 1000);
      expect(a['91–180 días'], 10000);
      expect(a['Más de 180'], 100000);
      expect(a['Sin iniciar'], 1000000);
    });
  });

  group('renovaciones', () {
    test('póliza que vence hoy NO es base de renovación (aún vigente)', () {
      final m = MotorDash([
        pol(1, exp: DateTime(2025, 10, 14), fin: DateTime(2026, 10, 14)),
      ], null, hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: DateTime(2026, 10, 1),
          hasta: DateTime(2026, 10, 31),
          comparar: Comparar.ninguno));
      expect(r.renBase, 0);
      expect(r.vence30.$1, 1);
    });

    test('vence ayer sí es base y queda sin renovar (últimos 90 días)', () {
      final m = MotorDash([
        pol(1, exp: DateTime(2025, 10, 13), fin: DateTime(2026, 10, 13)),
      ], null, hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: DateTime(2026, 10, 1),
          hasta: DateTime(2026, 10, 31),
          comparar: Comparar.ninguno));
      expect(r.renBase, 1);
      expect(r.renRenovadas, 0);
      expect(r.tasaRenovacion, 0);
      expect(r.sinRenovar90Tot.$1, 1);
      expect(r.sinRenovar90.first.dias, 1);
    });

    test('ventanas de vencimiento 30/60/90: fronteras inclusivas', () {
      DateTime d(int n) => hoy.add(Duration(days: n));
      final m = MotorDash([
        pol(1, fin: d(30), exp: d(-335)),
        pol(2, fin: d(31), exp: d(-334)),
        pol(3, fin: d(60), exp: d(-305)),
        pol(4, fin: d(61), exp: d(-304)),
        pol(5, fin: d(90), exp: d(-275)),
        pol(6, fin: d(91), exp: d(-274)),
      ], null, hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: DateTime(2026, 10, 1),
          hasta: DateTime(2026, 10, 31),
          comparar: Comparar.ninguno));
      expect(r.vence30.$1, 1);
      expect(r.vence60.$1, 2);
      expect(r.vence90.$1, 2);
    });

    test('renovada: ventana -45/+180 días, inclusive, y no cuenta anuladas',
        () {
      final fin = DateTime(2026, 6, 30);
      final base = pol(1,
          exp: DateTime(2025, 6, 30), ini: DateTime(2025, 6, 30), fin: fin);
      bool conSiguiente(DateTime ini,
          {String estado = 'I', int ramo = 1, int? cliente = 1}) {
        final m = MotorDash([
          base,
          pol(2,
              exp: ini,
              ini: ini,
              fin: ini.add(const Duration(days: 365)),
              estado: estado,
              ramo: ramo,
              cliente: cliente),
        ], null, hoy: hoy);
        return m.renovada(base);
      }

      expect(conSiguiente(fin.subtract(const Duration(days: 45))), isTrue);
      expect(conSiguiente(fin.subtract(const Duration(days: 46))), isFalse);
      expect(conSiguiente(fin.add(const Duration(days: 180))), isTrue);
      expect(conSiguiente(fin.add(const Duration(days: 181))), isFalse);
      expect(conSiguiente(fin, estado: 'A'), isFalse);
      expect(conSiguiente(fin, ramo: 2), isFalse);
      expect(conSiguiente(fin, cliente: 2), isFalse);
    });

    test('sin clienteId o sin fecha fin nunca se considera renovada', () {
      final sinCliente = pol(1,
          cliente: null, exp: DateTime(2025, 1, 1), fin: DateTime(2026, 1, 1));
      final sinFin = pol(2, exp: DateTime(2025, 1, 1));
      final m = MotorDash([sinCliente, sinFin], null, hoy: hoy);
      expect(m.renovada(sinCliente), isFalse);
      expect(m.renovada(sinFin), isFalse);
    });

    test(
        'dos pólizas gemelas (mismo cliente, ramo y fechas) no se renuevan entre sí',
        () {
      final a = pol(1,
          exp: DateTime(2025, 6, 1),
          ini: DateTime(2025, 6, 1),
          fin: DateTime(2026, 6, 1));
      final b = pol(2,
          exp: DateTime(2025, 6, 1),
          ini: DateTime(2025, 6, 1),
          fin: DateTime(2026, 6, 1));
      final m = MotorDash([a, b], null, hoy: hoy);
      expect(m.renovada(a), isFalse);
      expect(m.renovada(b), isFalse);
    });

    test('el filtro de estado (vigentes) no afecta la base de renovaciones',
        () {
      final m = MotorDash([
        pol(1, exp: DateTime(2025, 9, 1), fin: DateTime(2026, 9, 1)),
      ], null, hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: DateTime(2026, 9, 1),
          hasta: DateTime(2026, 9, 30),
          comparar: Comparar.ninguno,
          estado: 1));
      expect(r.renBase, 1);
    });

    test('vencimientos de los 12 meses futuros cruzan el año correctamente',
        () {
      final m = MotorDash([
        pol(1, exp: DateTime(2026, 1, 1), fin: DateTime(2027, 1, 20)),
        pol(2, exp: DateTime(2026, 1, 1), fin: DateTime(2027, 9, 20)),
      ], null, hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: DateTime(2026, 10, 1),
          hasta: DateTime(2026, 10, 31),
          comparar: Comparar.ninguno));
      expect(r.mesesFuturos.first, DateTime(2026, 10, 1));
      expect(r.mesesFuturos[3], DateTime(2027, 1, 1));
      expect(r.venceN[3], 1);
      expect(r.venceN[11], 1); // sep-2027 es el último de los 12 meses
      expect(r.venceN.reduce((a, b) => a + b), 2);
    });
  });

  group('metas: realesAnio', () {
    test('12 posiciones, excluye anuladas, filtra por asesor y por año', () {
      final m = MotorDash([
        pol(1, prima: 100, exp: DateTime(2026, 1, 31)),
        pol(2, prima: 200, exp: DateTime(2026, 12, 31)),
        pol(3, prima: 400, exp: DateTime(2025, 12, 31)),
        pol(4, prima: 800, exp: DateTime(2026, 3, 1), estado: 'A'),
        pol(5, prima: 1600, exp: DateTime(2026, 3, 1), asesor: 2),
      ], [
        AbonoLite(
            idPoliza: 1, fecha: DateTime(2026, 1, 1), prima: 10, comision: 1),
        AbonoLite(
            idPoliza: 5, fecha: DateTime(2026, 12, 31), prima: 20, comision: 2),
        AbonoLite(
            idPoliza: 1, fecha: DateTime(2025, 12, 31), prima: 40, comision: 4),
        AbonoLite(
            idPoliza: 99, fecha: DateTime(2026, 5, 1), prima: 80, comision: 8),
        AbonoLite(idPoliza: 1, fecha: null, prima: 160, comision: 16),
      ], hoy: hoy);
      final todo = m.realesAnio(2026);
      expect(todo['prima']!.length, 12);
      expect(todo['prima']![0], 100);
      expect(todo['prima']![11], 200);
      expect(todo['prima']![2], 1600); // la anulada no cuenta
      expect(todo['polizas']![2], 1);
      expect(todo['recaudo']![0], 10);
      expect(todo['recaudo']![11], 20);
      expect(todo['recaudo']![4],
          80); // abono de póliza desconocida cuenta en agencia

      final a2 = m.realesAnio(2026, asesorId: 2);
      expect(a2['prima']![2], 1600);
      expect(a2['prima']![0], 0);
      expect(a2['recaudo']![4], 0); // póliza desconocida no es de ningún asesor
      expect(a2['recaudo']![11], 20);
    });

    test('año sin datos devuelve ceros', () {
      final r = MotorDash([], null, hoy: hoy).realesAnio(2030);
      expect(r.values.every((l) => l.length == 12 && l.every((v) => v == 0)),
          isTrue);
    });
  });

  group('recaudo / abonos', () {
    test('abono de póliza anulada o fuera del filtro de estado', () {
      final m = MotorDash([
        pol(1, exp: DateTime(2026, 9, 5), fin: DateTime(2027, 9, 5)),
        pol(2, exp: DateTime(2025, 1, 5), fin: DateTime(2026, 1, 5)), // vencida
      ], [
        AbonoLite(
            idPoliza: 1, fecha: DateTime(2026, 9, 6), prima: 100, comision: 10),
        AbonoLite(
            idPoliza: 2, fecha: DateTime(2026, 9, 6), prima: 200, comision: 20),
      ], hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: DateTime(2026, 9, 1),
          hasta: DateTime(2026, 9, 30),
          comparar: Comparar.ninguno,
          estado: 1));
      // Pólizas: solo la vigente. Recaudo: hoy ignora el filtro de estado.
      expect(r.actual.n, 1);
      expect(r.actual.recaudo, 100,
          reason: 'el recaudo debería respetar el filtro Vigentes');
    }, skip: 'INCONSISTENCIA: _agregar no aplica f.estado a los abonos');

    test('abono el último día del rango y el día siguiente', () {
      final m = MotorDash([
        pol(1, exp: DateTime(2026, 9, 5))
      ], [
        AbonoLite(
            idPoliza: 1, fecha: DateTime(2026, 9, 30), prima: 1, comision: 0),
        AbonoLite(
            idPoliza: 1, fecha: DateTime(2026, 10, 1), prima: 2, comision: 0),
      ], hoy: hoy);
      final r = m.calcular(FiltrosDash(
          desde: DateTime(2026, 9, 1),
          hasta: DateTime(2026, 9, 30),
          comparar: Comparar.ninguno));
      expect(r.actual.recaudo, 1);
    });
  });
}
