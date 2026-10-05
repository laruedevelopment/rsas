import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento_polizas/ui/dashboard/dashboard_widgets.dart';

Widget envolver(Widget w, double ancho) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(child: SizedBox(width: ancho, child: w)),
        ),
      ),
    );

void main() {
  final meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun'];
  final v1 = [1e8, 2.5e8, 1.2e8, 3e8, 2e8, 0.0];
  final v2 = [9e7, 2e8, 1.5e8, 2.2e8, 1e8, 5e7];

  for (final ancho in [1100.0, 380.0]) {
    testWidgets('widgets del dashboard se dibujan sin errores a $ancho px',
        (t) async {
      await t.pumpWidget(envolver(
        Column(children: [
          Rejilla(anchoMinimo: 230, hijos: [
            KpiTile(
                etiqueta: 'Prima emitida',
                valor: '\$ 1.2 M',
                icono: Icons.payments,
                delta: 12.5,
                spark: v1,
                pie: 'ant. 1 M'),
            const KpiTile(
                etiqueta: 'Cartera',
                valor: '\$ 3 M',
                icono: Icons.hourglass_bottom,
                delta: -4,
                subirEsBueno: false),
          ]),
          DashCard(
              titulo: 'Líneas',
              child: GraficoLineas(etiquetas: meses, series: [
                SerieLinea('Actual', v1, DashColors.real),
                SerieLinea('Comp', v2, DashColors.comparacion, punteada: true),
              ])),
          DashCard(
              titulo: 'Columnas',
              child: GraficoColumnas(etiquetas: meses, series: [
                SerieColumna('A', v1, DashColors.real),
                SerieColumna('B', v2, DashColors.comparacion),
              ])),
          DashCard(
              titulo: 'Dona',
              child: GraficoDona(datos: [
                for (var i = 0; i < 10; i++) Rebanada('Aseg $i', 100.0 - i * 7)
              ], centro: 'total')),
          DashCard(
              titulo: 'Ranking',
              child: RankingBarras(filas: [
                for (var i = 0; i < 6; i++)
                  FilaRanking('Nombre largo de asesor $i', 100.0 - i * 10)
              ])),
          const DashCard(
              titulo: 'Meta',
              child: BarraMeta(
                  titulo: 'Mes',
                  real: 60,
                  meta: 100,
                  esperado: 0.5,
                  formato: fmtCompacto)),
          DashCard(
              titulo: 'Mapa',
              child: MapaCalor(
                  filas: const ['Sura', 'Axa'],
                  columnas: const ['Autos', 'Vida'],
                  valores: const {'Sura||Autos': 5e6, 'Axa||Vida': 1e6})),
          const DashCard(titulo: 'Vacío', child: GraficoDona(datos: [])),
        ]),
        ancho,
      ));
      await t.pumpAndSettle();
      expect(tester(t), isNull);
    });
  }

  test('formatos compactos', () {
    expect(fmtCompacto(1500000), '1,5 M');
    expect(fmtCompacto(2500000000), '2,5 mil M');
    expect(fmtCompacto(850000), '850 mil');
    expect(variacion(120, 100), 20);
    expect(variacion(1, 0), isNull);
  });
}

Object? tester(WidgetTester t) => t.takeException();
