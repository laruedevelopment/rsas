import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

// ── Color y formato ─────────────────────────────────────────────────────────

/// Paleta categórica validada (8 tonos, orden fijo: nunca se cicla). El color
/// sigue a la ENTIDAD, no a su posición: "Sura" conserva su color aunque un
/// filtro cambie el ranking. Pasado el 8.º se usa gris ("Otros").
class DashColors {
  DashColors._();

  static const List<Color> serie = [
    Color(0xFF2A78D6),
    Color(0xFFEB6834),
    Color(0xFF1BAF7A),
    Color(0xFFEDA100),
    Color(0xFFE87BA4),
    Color(0xFF008300),
    Color(0xFF4A3AA7),
    Color(0xFFE34948),
  ];
  static const Color otros = Color(0xFF9AA5B1);
  static const Color real = AppTheme.navy;
  static const Color comparacion = Color(0xFFA9B4BF);
  static const Color bueno = AppTheme.green;
  static const Color alerta = AppTheme.warning;
  static const Color malo = AppTheme.danger;

  /// Rampa secuencial de un solo tono (navy), de claro a oscuro.
  static Color secuencial(double t) =>
      Color.lerp(const Color(0xFFE3EBF3), AppTheme.navyDark, t.clamp(0, 1))!;

  static final Map<String, int> _registro = {};

  static Color de(String nombre) {
    final i = _registro.putIfAbsent(nombre, () => _registro.length);
    return i < serie.length ? serie[i] : otros;
  }
}

final _nf = NumberFormat.decimalPattern('es_CO');
final _nf1 = NumberFormat('#,##0.0', 'es_CO');

String fmtEntero(num n) => _nf.format(n.round());

/// Monto completo: $ 1.234.567
String fmtMonto(num n) => '\$ ${_nf.format(n.round())}';

/// Monto compacto para tarjetas y ejes: 1,2 M · 3,4 mil M · 850 mil.
String fmtCompacto(num n, {bool signo = false}) {
  final a = n.abs();
  final s = n < 0 ? '-' : (signo && n > 0 ? '+' : '');
  if (a >= 1e9) return '$s${_nf1.format(a / 1e9)} mil M';
  if (a >= 1e6) return '$s${_nf1.format(a / 1e6)} M';
  if (a >= 1e3) return '$s${_nf.format((a / 1e3).round())} mil';
  return '$s${_nf.format(a.round())}';
}

String fmtPct(num n, {int dec = 1}) =>
    '${NumberFormat('#,##0.${'0' * dec}', 'es_CO').format(n)}%';

const _mesesCortos = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic'
];
String mesCorto(DateTime d, {bool anio = false}) =>
    '${_mesesCortos[d.month - 1]}${anio ? " ${d.year % 100}" : ""}';

/// Variación porcentual; null si no hay base de comparación.
double? variacion(num actual, num? previo) {
  if (previo == null || previo == 0) return null;
  return (actual - previo) / previo.abs() * 100;
}

// ── Contenedores ────────────────────────────────────────────────────────────

class DashCard extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final Widget child;
  final Widget? accion;
  final EdgeInsets padding;

  const DashCard({
    super.key,
    required this.titulo,
    required this.child,
    this.subtitulo,
    this.accion,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 16),
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo,
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      if (subtitulo != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitulo!,
                              style: tt.bodySmall
                                  ?.copyWith(color: AppTheme.inkSoft)),
                        ),
                    ],
                  ),
                ),
                if (accion != null) accion!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Reparte [hijos] en columnas iguales según el ancho disponible.
class Rejilla extends StatelessWidget {
  final List<Widget> hijos;
  final double anchoMinimo;
  final double espacio;
  final int? maxColumnas;

  const Rejilla({
    super.key,
    required this.hijos,
    this.anchoMinimo = 300,
    this.espacio = 12,
    this.maxColumnas,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      var cols = ((c.maxWidth + espacio) / (anchoMinimo + espacio)).floor();
      cols = cols.clamp(1, maxColumnas ?? hijos.length.clamp(1, 12));
      final w = (c.maxWidth - espacio * (cols - 1)) / cols;
      return Wrap(
        spacing: espacio,
        runSpacing: espacio,
        children: [for (final h in hijos) SizedBox(width: w, child: h)],
      );
    });
  }
}

// ── KPI ─────────────────────────────────────────────────────────────────────

class KpiTile extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final String? valorExacto;
  final IconData icono;
  final Color color;

  /// Variación % contra el período de comparación (null = sin base).
  final double? delta;

  /// false si subir es malo (p. ej. cartera pendiente).
  final bool subirEsBueno;
  final List<double>? spark;
  final String? pie;
  final VoidCallback? onTap;

  const KpiTile({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.icono,
    this.color = AppTheme.navy,
    this.valorExacto,
    this.delta,
    this.subirEsBueno = true,
    this.spark,
    this.pie,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    Widget? chipDelta;
    if (delta != null) {
      final sube = delta! >= 0;
      final bueno = delta!.abs() < 0.05 ? null : (sube == subirEsBueno);
      final c = bueno == null
          ? AppTheme.inkSoft
          : (bueno ? DashColors.bueno : DashColors.malo);
      chipDelta = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: c.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(sube ? Icons.arrow_upward : Icons.arrow_downward,
              size: 12, color: c),
          const SizedBox(width: 2),
          Text(fmtPct(delta!.abs()),
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: c)),
        ]),
      );
    }
    return Tooltip(
      message: valorExacto ?? valor,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icono, size: 16, color: color),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(etiqueta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            tt.labelMedium?.copyWith(color: AppTheme.inkSoft)),
                  ),
                  if (onTap != null)
                    const Icon(Icons.chevron_right,
                        size: 16, color: AppTheme.inkSoft),
                ]),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(valor,
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink)),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  if (chipDelta != null) chipDelta,
                  if (chipDelta != null && pie != null)
                    const SizedBox(width: 6),
                  if (pie != null)
                    Expanded(
                      child: Text(pie!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              tt.bodySmall?.copyWith(color: AppTheme.inkSoft)),
                    ),
                ]),
                if (spark != null && spark!.length > 1) ...[
                  const SizedBox(height: 8),
                  SizedBox(height: 28, child: _Spark(spark!, color)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Spark extends StatelessWidget {
  final List<double> v;
  final Color color;
  const _Spark(this.v, this.color);

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        minY: 0,
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < v.length; i++) FlSpot(i.toDouble(), v[i])
            ],
            isCurved: true,
            curveSmoothness: 0.25,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData:
                BarAreaData(show: true, color: color.withOpacity(0.08)),
          ),
        ],
      ),
    );
  }
}

// ── Gráficos ────────────────────────────────────────────────────────────────

class SerieLinea {
  final String nombre;
  final List<double> valores;
  final Color color;
  final bool punteada;
  const SerieLinea(this.nombre, this.valores, this.color,
      {this.punteada = false});
}

/// Líneas (hasta 2 series, misma unidad) con crosshair y tooltip.
class GraficoLineas extends StatelessWidget {
  final List<String> etiquetas;
  final List<SerieLinea> series;
  final String Function(num) formato;
  final double alto;

  const GraficoLineas({
    super.key,
    required this.etiquetas,
    required this.series,
    this.formato = fmtCompacto,
    this.alto = 240,
  });

  @override
  Widget build(BuildContext context) {
    final maxV = series
        .expand((s) => s.valores)
        .fold<double>(0, (m, v) => math.max(m, v));
    final techo = _techo(maxV);
    final paso = math.max(1, (etiquetas.length / 8).ceil());
    return Column(children: [
      if (series.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 14, children: [
            for (final s in series)
              _Leyenda(s.color, s.nombre, punteada: s.punteada)
          ]),
        ),
      SizedBox(
        height: alto,
        child: LineChart(LineChartData(
          minY: 0,
          maxY: techo,
          minX: 0,
          maxX: math.max(1, etiquetas.length - 1).toDouble(),
          gridData: _grid(techo),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: _ejeY(techo, formato),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 1,
                getTitlesWidget: (v, _) {
                  final i = v.round();
                  if (i < 0 || i >= etiquetas.length || i % paso != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(etiquetas[i], style: _ejeStyle),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppTheme.ink,
              getTooltipItems: (spots) {
                final i = spots.first.x.round();
                return [
                  for (var k = 0; k < spots.length; k++)
                    LineTooltipItem(
                      k == 0 ? '${etiquetas[i]}\n' : '',
                      const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                      children: [
                        TextSpan(
                          text:
                              '${series[spots[k].barIndex].nombre}: ${formato(spots[k].y)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                ];
              },
            ),
          ),
          lineBarsData: [
            for (var si = 0; si < series.length; si++)
              LineChartBarData(
                spots: [
                  for (var i = 0; i < series[si].valores.length; i++)
                    FlSpot(i.toDouble(), series[si].valores[i])
                ],
                isCurved: true,
                curveSmoothness: 0.2,
                preventCurveOverShooting: true,
                color: series[si].color,
                barWidth: 2.5,
                dashArray: series[si].punteada ? [6, 4] : null,
                dotData: FlDotData(show: series[si].valores.length <= 14),
                belowBarData: BarAreaData(
                  show: si == 0,
                  color: series[si].color.withOpacity(0.08),
                ),
              ),
          ],
        )),
      ),
    ]);
  }
}

class SerieColumna {
  final String nombre;
  final List<double> valores;
  final Color color;
  const SerieColumna(this.nombre, this.valores, this.color);
}

/// Columnas agrupadas (1–2 series) con tooltip por barra.
class GraficoColumnas extends StatelessWidget {
  final List<String> etiquetas;
  final List<SerieColumna> series;
  final String Function(num) formato;
  final double alto;
  final void Function(int indice)? onTapColumna;

  const GraficoColumnas({
    super.key,
    required this.etiquetas,
    required this.series,
    this.formato = fmtCompacto,
    this.alto = 240,
    this.onTapColumna,
  });

  @override
  Widget build(BuildContext context) {
    final maxV = series
        .expand((s) => s.valores)
        .fold<double>(0, (m, v) => math.max(m, v));
    final techo = _techo(maxV);
    final paso = math.max(1, (etiquetas.length / 12).ceil());
    final ancho =
        etiquetas.length > 24 ? 6.0 : (series.length > 1 ? 9.0 : 14.0);
    return Column(children: [
      if (series.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
              spacing: 14,
              children: [for (final s in series) _Leyenda(s.color, s.nombre)]),
        ),
      SizedBox(
        height: alto,
        child: BarChart(BarChartData(
          maxY: techo,
          alignment: BarChartAlignment.spaceAround,
          gridData: _grid(techo),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: _ejeY(techo, formato),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, _) {
                  final i = v.round();
                  if (i < 0 || i >= etiquetas.length || i % paso != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(etiquetas[i], style: _ejeStyle),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchCallback: (e, r) {
              if (onTapColumna != null &&
                  e is FlTapUpEvent &&
                  r?.spot != null) {
                onTapColumna!(r!.spot!.touchedBarGroupIndex);
              }
            },
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppTheme.ink,
              getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                '${etiquetas[gi]}\n',
                const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
                children: [
                  TextSpan(
                    text: '${series[ri].nombre}: ${formato(rod.toY)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < etiquetas.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 2,
                barRods: [
                  for (final s in series)
                    BarChartRodData(
                      toY: i < s.valores.length ? s.valores[i] : 0,
                      width: ancho,
                      color: s.color,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                ],
              ),
          ],
        )),
      ),
    ]);
  }
}

class Rebanada {
  final String nombre;
  final double valor;
  const Rebanada(this.nombre, this.valor);
}

/// Dona con leyenda clicable (la leyenda también filtra). Muestra hasta
/// [max] entidades con su color fijo y agrupa el resto en "Otros".
class GraficoDona extends StatefulWidget {
  final List<Rebanada> datos;
  final String? seleccionado;
  final void Function(String nombre)? onTap;
  final String centro;
  final String Function(num) formato;
  final int max;

  const GraficoDona({
    super.key,
    required this.datos,
    this.seleccionado,
    this.onTap,
    this.centro = '',
    this.formato = fmtCompacto,
    this.max = 7,
  });

  @override
  State<GraficoDona> createState() => _GraficoDonaState();
}

class _GraficoDonaState extends State<GraficoDona> {
  int _hover = -1;

  @override
  Widget build(BuildContext context) {
    final datos = widget.datos.where((d) => d.valor > 0).toList();
    if (datos.isEmpty) return const _SinDatos();
    final visibles = datos.take(widget.max).toList();
    final resto = datos.skip(widget.max).fold<double>(0, (s, d) => s + d.valor);
    if (resto > 0) visibles.add(Rebanada('Otros', resto));
    final total = visibles.fold<double>(0, (s, d) => s + d.valor);
    Color color(Rebanada r) =>
        r.nombre == 'Otros' ? DashColors.otros : DashColors.de(r.nombre);

    final dona = SizedBox(
      width: 190,
      height: 190,
      child: Stack(alignment: Alignment.center, children: [
        PieChart(PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 58,
          pieTouchData: PieTouchData(
            touchCallback: (e, r) {
              final i = r?.touchedSection?.touchedSectionIndex ?? -1;
              if (e is FlTapUpEvent && i >= 0 && i < visibles.length) {
                final n = visibles[i].nombre;
                if (n != 'Otros') widget.onTap?.call(n);
              }
              final nuevo =
                  (e is FlPointerExitEvent || e is FlLongPressEnd) ? -1 : i;
              if (nuevo != _hover) setState(() => _hover = nuevo);
            },
          ),
          sections: [
            for (var i = 0; i < visibles.length; i++)
              PieChartSectionData(
                value: visibles[i].valor,
                color: color(visibles[i]),
                radius: i == _hover ? 34 : 28,
                showTitle: false,
              ),
          ],
        )),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              _hover >= 0 && _hover < visibles.length
                  ? widget.formato(visibles[_hover].valor)
                  : widget.formato(total),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            Text(
              _hover >= 0 && _hover < visibles.length
                  ? fmtPct(visibles[_hover].valor / total * 100)
                  : widget.centro,
              style: const TextStyle(fontSize: 10, color: AppTheme.inkSoft),
            ),
          ]),
        ),
      ]),
    );

    final leyenda = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < visibles.length; i++)
          _FilaLeyenda(
            color: color(visibles[i]),
            nombre: visibles[i].nombre,
            valor: widget.formato(visibles[i].valor),
            pct: visibles[i].valor / total * 100,
            activo: widget.seleccionado == visibles[i].nombre,
            resaltado: i == _hover,
            onTap: visibles[i].nombre == 'Otros' || widget.onTap == null
                ? null
                : () => widget.onTap!(visibles[i].nombre),
          ),
      ],
    );

    return LayoutBuilder(builder: (_, c) {
      if (c.maxWidth < 430) {
        return Column(children: [dona, const SizedBox(height: 8), leyenda]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        dona,
        const SizedBox(width: 12),
        Expanded(child: leyenda),
      ]);
    });
  }
}

class _FilaLeyenda extends StatelessWidget {
  final Color color;
  final String nombre, valor;
  final double pct;
  final bool activo, resaltado;
  final VoidCallback? onTap;
  const _FilaLeyenda({
    required this.color,
    required this.nombre,
    required this.valor,
    required this.pct,
    required this.activo,
    required this.resaltado,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: activo
              ? AppTheme.navy.withOpacity(0.10)
              : (resaltado ? AppTheme.surfaceContainerHighest : null),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(nombre,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: activo ? FontWeight.w700 : FontWeight.w500)),
          ),
          Text(valor,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          SizedBox(
            width: 46,
            child: Text(fmtPct(pct),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
          ),
        ]),
      ),
    );
  }
}

class FilaRanking {
  final String nombre;
  final double valor;
  final String? detalle;
  final String? valorTexto;
  final Color? color;
  const FilaRanking(this.nombre, this.valor,
      {this.detalle, this.valorTexto, this.color});
}

/// Ranking de barras horizontales; cada fila se puede tocar para filtrar.
class RankingBarras extends StatelessWidget {
  final List<FilaRanking> filas;
  final String? seleccionado;
  final void Function(String nombre)? onTap;
  final String Function(num) formato;
  final bool mostrarPct;
  final int maxFilas;

  const RankingBarras({
    super.key,
    required this.filas,
    this.seleccionado,
    this.onTap,
    this.formato = fmtCompacto,
    this.mostrarPct = true,
    this.maxFilas = 10,
  });

  @override
  Widget build(BuildContext context) {
    final lista = filas.where((f) => f.valor > 0).take(maxFilas).toList();
    if (lista.isEmpty) return const _SinDatos();
    final total = filas.fold<double>(0, (s, f) => s + f.valor);
    final maxV = lista.first.valor == 0
        ? 1.0
        : lista.map((f) => f.valor).reduce(math.max);
    return Column(children: [
      for (final f in lista)
        Tooltip(
          message:
              '${f.nombre}\n${f.valorTexto ?? formato(f.valor)}${f.detalle != null ? "\n${f.detalle}" : ""}',
          child: InkWell(
            onTap: onTap == null ? null : () => onTap!(f.nombre),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: seleccionado == f.nombre
                    ? AppTheme.navy.withOpacity(0.08)
                    : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(children: [
                SizedBox(
                  width: 150,
                  child: Text(f.nombre,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: seleccionado == f.nombre
                              ? FontWeight.w700
                              : FontWeight.w500)),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, c) => Stack(children: [
                      Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Container(
                        height: 14,
                        width: math.max(3, c.maxWidth * (f.valor / maxV)),
                        decoration: BoxDecoration(
                          color: f.color ?? DashColors.real,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 78,
                  child: Text(f.valorTexto ?? formato(f.valor),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                if (mostrarPct)
                  SizedBox(
                    width: 46,
                    child: Text(total == 0 ? '' : fmtPct(f.valor / total * 100),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.inkSoft)),
                  ),
              ]),
            ),
          ),
        ),
    ]);
  }
}

/// Avance contra una meta, con marca del ritmo esperado.
class BarraMeta extends StatelessWidget {
  final String titulo;
  final double real;
  final double meta;

  /// Fracción del período ya transcurrida (0–1) para marcar el ritmo.
  final double esperado;
  final String Function(num) formato;

  const BarraMeta({
    super.key,
    required this.titulo,
    required this.real,
    required this.meta,
    required this.esperado,
    required this.formato,
  });

  @override
  Widget build(BuildContext context) {
    final pct = meta <= 0 ? 0.0 : real / meta;
    final ritmo = meta <= 0 || esperado <= 0 ? null : pct / esperado;
    final Color c;
    final IconData ic;
    final String txt;
    if (meta <= 0) {
      c = AppTheme.inkSoft;
      ic = Icons.horizontal_rule;
      txt = 'Sin meta';
    } else if (pct >= 1) {
      c = DashColors.bueno;
      ic = Icons.check_circle;
      txt = 'Meta cumplida';
    } else if (ritmo! >= 0.95) {
      c = DashColors.bueno;
      ic = Icons.trending_up;
      txt = 'En ritmo';
    } else if (ritmo >= 0.75) {
      c = DashColors.alerta;
      ic = Icons.warning_amber_rounded;
      txt = 'Atención';
    } else {
      c = DashColors.malo;
      ic = Icons.trending_down;
      txt = 'Rezagado';
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text(titulo,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700))),
        Icon(ic, size: 14, color: c),
        const SizedBox(width: 4),
        Text(txt,
            style:
                TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
      ]),
      const SizedBox(height: 6),
      LayoutBuilder(builder: (_, box) {
        final w = box.maxWidth;
        return SizedBox(
          height: 16,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            Container(
              width: w * pct.clamp(0, 1),
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            if (meta > 0 && esperado > 0 && esperado < 1)
              Positioned(
                left: w * esperado - 1,
                top: -3,
                bottom: -3,
                child: Container(width: 2, color: AppTheme.ink),
              ),
          ]),
        );
      }),
      const SizedBox(height: 4),
      Row(children: [
        Text('${formato(real)} de ${meta <= 0 ? "—" : formato(meta)}',
            style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
        const Spacer(),
        Text(meta <= 0 ? '' : fmtPct(pct * 100, dec: 0),
            style:
                TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
      ]),
    ]);
  }
}

/// Mapa de calor aseguradora × ramo (una sola rampa navy; la celda se
/// toca para filtrar por ambas).
class MapaCalor extends StatelessWidget {
  final List<String> filas;
  final List<String> columnas;
  final Map<String, num> valores;
  final void Function(String fila, String columna)? onTap;
  const MapaCalor({
    super.key,
    required this.filas,
    required this.columnas,
    required this.valores,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (filas.isEmpty || columnas.isEmpty) return const _SinDatos();
    final maxV = valores.values.fold<num>(0, (m, v) => math.max(m, v));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const FixedColumnWidth(86),
        columnWidths: const {0: FixedColumnWidth(140)},
        children: [
          TableRow(children: [
            const SizedBox(),
            for (final c in columnas)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
                child: Text(c,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.inkSoft)),
              ),
          ]),
          for (final f in filas)
            TableRow(children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(f,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              for (final c in columnas) _celda(f, c, maxV),
            ]),
        ],
      ),
    );
  }

  TableCell _celda(String f, String c, num maxV) {
    final v = valores['$f||$c'] ?? 0;
    final t = maxV == 0 ? 0.0 : (v / maxV).toDouble();
    final fondo = v == 0
        ? AppTheme.surfaceContainerHighest.withOpacity(0.5)
        : DashColors.secuencial(0.12 + t * 0.88);
    final claro = t < 0.5 || v == 0;
    return TableCell(
      child: Tooltip(
        message: '$f · $c\n${fmtMonto(v)}',
        child: InkWell(
          onTap: onTap == null ? null : () => onTap!(f, c),
          child: Container(
            height: 34,
            margin: const EdgeInsets.all(1.5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fondo,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(v == 0 ? '' : fmtCompacto(v),
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: claro ? AppTheme.ink : Colors.white)),
          ),
        ),
      ),
    );
  }
}

/// Fila de alerta/insight con ícono, texto y acción opcional.
class Alerta extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String detalle;
  final VoidCallback? onTap;
  const Alerta({
    super.key,
    required this.icono,
    required this.color,
    required this.titulo,
    required this.detalle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icono, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              Text(detalle,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.inkSoft, height: 1.3)),
            ]),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right, size: 18, color: AppTheme.inkSoft),
        ]),
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  final Color color;
  final String texto;
  final bool punteada;
  const _Leyenda(this.color, this.texto, {this.punteada = false});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 14,
        height: punteada ? 0 : 8,
        decoration: punteada
            ? BoxDecoration(
                border: Border(top: BorderSide(color: color, width: 2)))
            : BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 6),
      Text(texto,
          style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft)),
    ]);
  }
}

class _SinDatos extends StatelessWidget {
  const _SinDatos();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text('Sin datos para los filtros elegidos',
              style: TextStyle(color: AppTheme.inkSoft, fontSize: 12)),
        ),
      );
}

class SinDatos extends StatelessWidget {
  const SinDatos({super.key});
  @override
  Widget build(BuildContext context) => const _SinDatos();
}

// ── Helpers de ejes ─────────────────────────────────────────────────────────

const _ejeStyle = TextStyle(fontSize: 10.5, color: AppTheme.inkSoft);

/// Techo "redondo" para el eje (1, 2, 2.5, 5, 10 × potencia de 10).
double _techo(double maxV) {
  if (maxV <= 0) return 1;
  final e = math.pow(10, (math.log(maxV) / math.ln10).floor()).toDouble();
  for (final m in [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0]) {
    if (m * e >= maxV * 1.05) return m * e;
  }
  return 10 * e;
}

FlGridData _grid(double techo) => FlGridData(
      drawVerticalLine: false,
      horizontalInterval: techo / 4,
      getDrawingHorizontalLine: (_) =>
          const FlLine(color: AppTheme.outlineVariant, strokeWidth: 1),
    );

AxisTitles _ejeY(double techo, String Function(num) f) => AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 54,
        interval: techo / 4,
        getTitlesWidget: (v, meta) => v > techo + 0.001
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(f(v), textAlign: TextAlign.right, style: _ejeStyle),
              ),
      ),
    );
