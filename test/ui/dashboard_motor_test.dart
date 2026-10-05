import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento_polizas/datos/poliza.dart';
import 'package:seguimiento_polizas/datos/repositorio_dashboard.dart';
import 'package:seguimiento_polizas/ui/dashboard/dashboard_motor.dart';

Poliza pol(
  int id, {
  required num prima,
  required DateTime exp,
  DateTime? fin,
  DateTime? ini,
  int cliente = 1,
  int ramo = 1,
  String aseg = 'Sura',
  String asesorN = 'Ana',
  int asesor = 1,
  String estado = 'I',
  num pagada = 0,
}) =>
    Poliza(
      id: id,
      primaPoliza: prima,
      valorPoliza: 0,
      fexpPoliza: exp,
      finiPoliza: ini ?? exp,
      ffinPoliza: fin ?? DateTime(exp.year + 1, exp.month, exp.day),
      clienteId: cliente,
      nombreCliente: 'Cliente $cliente',
      ramoId: ramo,
      nombreRamo: 'Ramo $ramo',
      nombreAseg: aseg,
      asesorId: asesor,
      nombreAsesor: asesorN,
      estadoPolizaId: estado,
      vlrprimapagadaPoliza: pagada,
    );

void main() {
  final hoy = DateTime(2026, 10, 5);
  final polizas = [
    pol(1, prima: 1000, exp: DateTime(2026, 9, 10), pagada: 400),
    pol(2, prima: 3000, exp: DateTime(2026, 9, 20), cliente: 2, aseg: 'Axa'),
    pol(3,
        prima: 500,
        exp: DateTime(2026, 8, 5),
        cliente: 3,
        asesorN: 'Beto',
        asesor: 2),
    pol(4, prima: 9999, exp: DateTime(2026, 9, 15), estado: 'A', cliente: 4),
    // Venció en agosto y la renovó una póliza que arranca en septiembre
    pol(5,
        prima: 700,
        exp: DateTime(2025, 8, 20),
        fin: DateTime(2026, 8, 20),
        cliente: 5),
    pol(6,
        prima: 800,
        exp: DateTime(2026, 8, 25),
        ini: DateTime(2026, 8, 25),
        cliente: 5),
    // Venció en agosto sin renovar
    pol(7,
        prima: 600,
        exp: DateTime(2025, 8, 10),
        fin: DateTime(2026, 8, 10),
        cliente: 6),
  ];
  final abonos = [
    AbonoLite(
        idPoliza: 1, fecha: DateTime(2026, 9, 12), prima: 400, comision: 40),
    AbonoLite(
        idPoliza: 3, fecha: DateTime(2026, 8, 6), prima: 500, comision: 50),
  ];
  final motor = MotorDash(polizas, abonos, hoy: hoy);

  test('totales del mes y exclusión de anuladas', () {
    final f =
        FiltrosDash(desde: DateTime(2026, 9, 1), hasta: DateTime(2026, 9, 30));
    final r = motor.calcular(f);
    expect(r.actual.n, 2);
    expect(r.actual.prima, 4000);
    expect(r.actual.clientes, 2);
    expect(r.actual.recaudo, 400);
    expect(r.actual.comision, 40);
    // Anterior = agosto completo
    expect(r.comp!.desde, DateTime(2026, 8, 1));
    expect(r.comp!.prima, 500 + 800);
  });

  test('incluir anuladas y filtro por aseguradora', () {
    final f = FiltrosDash(
        desde: DateTime(2026, 9, 1),
        hasta: DateTime(2026, 9, 30),
        incluirAnuladas: true);
    expect(motor.calcular(f).actual.prima, 4000 + 9999);
    f.aseg = 'Axa';
    f.incluirAnuladas = false;
    final r = motor.calcular(f);
    expect(r.actual.prima, 3000);
    expect(r.actual.recaudo, 0);
  });

  test('cartera de lo emitido: saldo = prima - pagada', () {
    final f =
        FiltrosDash(desde: DateTime(2026, 9, 1), hasta: DateTime(2026, 9, 30));
    final r = motor.calcular(f);
    expect(r.carteraPrima, 4000);
    expect(r.carteraPagada, 400);
    expect(r.carteraSaldo, 3600);
  });

  test('renovación estimada por cliente y ramo', () {
    final f =
        FiltrosDash(desde: DateTime(2026, 8, 1), hasta: DateTime(2026, 8, 31));
    final r = motor.calcular(f);
    expect(r.renBase, 2); // pólizas 5 y 7 vencieron en agosto
    expect(r.renRenovadas, 1);
    expect(r.tasaRenovacion, 0.5);
    expect(r.sinRenovar90.map((e) => e.p.id), contains(7));
  });

  test('nuevos vs recurrentes', () {
    final f =
        FiltrosDash(desde: DateTime(2026, 9, 1), hasta: DateTime(2026, 9, 30));
    final r = motor.calcular(f);
    expect(r.clientesNuevos, 2);
    expect(r.clientesRecurrentes, 0);
  });

  test('reales del año para metas', () {
    final r = motor.realesAnio(2026);
    expect(r['prima']![8], 4000); // septiembre
    expect(r['polizas']![8], 2);
    expect(r['comision']![7], 50);
    expect(motor.realesAnio(2026, asesorId: 2)['prima']![7], 500);
  });

  test('rango de comparación del año anterior', () {
    final rc = MotorDash.rangoComparacion(
        DateTime(2026, 1, 1), DateTime(2026, 3, 31), Comparar.anioAnterior)!;
    expect(rc.$1, DateTime(2025, 1, 1));
    expect(rc.$2, DateTime(2025, 3, 31));
  });
}
