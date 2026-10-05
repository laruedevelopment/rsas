import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../datos/meta.dart';
import '../../datos/poliza.dart';
import '../../datos/repositorio_casos.dart';
import '../../datos/repositorio_dashboard.dart';
import '../../datos/repositorio_polizas.dart';
import '../../datos/sesion.dart';
import '../pagina_formulario_polizas.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../widgets/selector_fecha.dart';
import 'dashboard_motor.dart';
import 'dashboard_widgets.dart';
import 'dialogo_metas.dart';

/// Dashboard gerencial: KPIs, producción, comercial, cartera, renovaciones y
/// metas, con filtros globales y comparación contra un período anterior.
/// Los gráficos son interactivos: tocar una barra, rebanada o fila filtra
/// todo el tablero.
class PaginaDashboard extends StatefulWidget {
  const PaginaDashboard({super.key});
  @override
  State<PaginaDashboard> createState() => _PaginaDashboardState();
}

class _PaginaDashboardState extends State<PaginaDashboard>
    with SingleTickerProviderStateMixin {
  final _repoPol = RepositorioPolizas();
  final _repoDash = RepositorioDashboard();
  late final TabController _tabs;

  List<Poliza> _polizas = [];
  List<AbonoLite>? _abonos;
  MotorDash? _motor;
  Resultado? _res;
  CalidadDatos? _calidad;
  int? _casos;

  bool _cargando = true;
  int _cargados = 0;
  String? _error;
  String _presetActivo = 'Este año';

  late FiltrosDash _f;
  Dim _dimExplorador = Dim.aseguradora;
  int _anioMetas = DateTime.now().year;
  Timer? _auto;

  bool get _comisiones => Sesion.veComisiones;

  List<String> get _titulosTabs => [
        'Resumen',
        'Producción',
        'Clientes y asesores',
        if (_comisiones) 'Cartera y recaudo',
        'Renovaciones',
        if (_comisiones) 'Metas',
      ];

  @override
  void initState() {
    super.initState();
    final h = DateTime.now();
    _f = FiltrosDash(
        desde: DateTime(h.year, 1, 1), hasta: DateTime(h.year, 12, 31));
    _tabs = TabController(length: _titulosTabs.length, vsync: this);
    _cargar();
    // "Tiempo real": refresca solo cada 5 minutos mientras está abierto.
    _auto = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted && !_cargando) _cargar(forzar: true, silencioso: true);
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool forzar = false, bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _cargados = 0;
        _error = null;
      });
    }
    try {
      final pol = await _repoPol
          .listarTodos(
            forzar: forzar,
            onProgreso: (n) {
              if (mounted && !silencioso) setState(() => _cargados = n);
            },
          )
          .timeout(const Duration(minutes: 3));
      List<AbonoLite>? ab;
      if (_comisiones) {
        try {
          ab = await _repoDash.listarAbonos(forzar: forzar);
        } catch (_) {
          ab = null; // el resto del tablero funciona sin pagos
        }
      }
      int? casos;
      try {
        casos = await RepositorioCasos().contarPendientes();
      } catch (_) {}
      if (!mounted) return;
      _polizas = pol;
      _abonos = ab;
      _motor = MotorDash(pol, ab);
      _calidad = _motor!.calidad();
      _casos = casos;
      _recalcular();
      setState(() => _cargando = false);
    } catch (e) {
      if (mounted && !silencioso) {
        setState(() {
          _cargando = false;
          _error = 'No se pudieron cargar los datos. Intente de nuevo.\n$e';
        });
      }
    }
  }

  void _recalcular() {
    final m = _motor;
    if (m != null) _res = m.calcular(_f);
  }

  void _cambiar(void Function() fn) {
    setState(() {
      fn();
      _recalcular();
    });
  }

  void _toggleDim(Dim d, String valor) => _cambiar(() {
        _f.poner(d, _f.valorDe(d) == valor ? null : valor);
      });

  // ── Períodos ───────────────────────────────────────────────────────────

  void _preset(String nombre) {
    final h = DateTime.now();
    final hoy = DateTime(h.year, h.month, h.day);
    DateTime d, a;
    switch (nombre) {
      case 'Este mes':
        d = DateTime(h.year, h.month, 1);
        a = DateTime(h.year, h.month + 1, 0);
      case 'Mes anterior':
        d = DateTime(h.year, h.month - 1, 1);
        a = DateTime(h.year, h.month, 0);
      case 'Trimestre':
        final q = (h.month - 1) ~/ 3;
        d = DateTime(h.year, q * 3 + 1, 1);
        a = DateTime(h.year, q * 3 + 4, 0);
      case 'Este año':
        d = DateTime(h.year, 1, 1);
        a = DateTime(h.year, 12, 31);
      case 'Año anterior':
        d = DateTime(h.year - 1, 1, 1);
        a = DateTime(h.year - 1, 12, 31);
      case '12 meses':
        d = DateTime(h.year, h.month - 11, 1);
        a = DateTime(h.year, h.month + 1, 0);
      default: // Todo
        final r = _motor?.rangoTotal();
        d = r == null
            ? DateTime(h.year, 1, 1)
            : DateTime(r.$1.year, r.$1.month, 1);
        a = hoy;
    }
    _presetActivo = nombre;
    _cambiar(() {
      _f.desde = d;
      _f.hasta = a;
      if (nombre == 'Todo') _f.comparar = Comparar.ninguno;
    });
  }

  Future<void> _personalizado() async {
    final r = await mostrarSelectorRangoFecha(
      context,
      primera: DateTime(2000),
      ultima: DateTime(2035),
      inicial: DateTimeRange(start: _f.desde, end: _f.hasta),
      titulo: 'Período a analizar',
    );
    if (r == null || !mounted) return;
    _presetActivo = 'Personalizado';
    _cambiar(() {
      _f.desde = soloDia(r.start);
      _f.hasta = soloDia(r.end);
    });
  }

  // ── Opciones de los selectores (respetan los demás filtros) ─────────────

  List<String> _opciones(Dim d) {
    final g = _res?.porDim[d] ?? const [];
    final s = {for (final x in g) x.nombre};
    final act = _f.valorDe(d);
    if (act != null) s.add(act);
    return s.toList()..sort();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard gerencial'),
        bottom: _cargando || _error != null
            ? null
            : TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [for (final t in _titulosTabs) Tab(text: t)],
              ),
        actions: [
          if (!_cargando && RepositorioPolizas.cacheCargadoEn != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(
                  'Actualizado ${DateFormat('HH:mm').format(RepositorioPolizas.cacheCargadoEn!)}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Actualizar datos',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : () => _cargar(forzar: true),
          ),
        ],
      ),
      body: _cargando
          ? _vistaCargando()
          : _error != null
              ? _vistaError()
              : Column(children: [
                  _barraFiltros(),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _pagina(_tabResumen),
                        _pagina(_tabProduccion),
                        _pagina(_tabClientesAsesores),
                        if (_comisiones) _pagina(_tabCartera),
                        _pagina(_tabRenovaciones),
                        if (_comisiones) _pagina(_tabMetas),
                      ],
                    ),
                  ),
                ]),
    );
  }

  Widget _pagina(List<Widget> Function(Resultado r) construir) {
    final r = _res!;
    return SingleChildScrollView(
      padding: AppLayout.pagePadding,
      child: AppLayout.centered(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final w in construir(r)) ...[w, const SizedBox(height: 14)],
          ],
        ),
        maxWidth: 1400,
      ),
    );
  }

  Widget _vistaCargando() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(_cargados == 0
              ? 'Conectando…'
              : '${NumberFormat.decimalPattern('es_CO').format(_cargados)} pólizas cargadas'),
        ]),
      );

  Widget _vistaError() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded,
              size: 56, color: AppTheme.inkSoft),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _cargar(forzar: true),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ]),
      );

  // ── Barra de filtros ────────────────────────────────────────────────────

  Widget _barraFiltros() {
    final df = DateFormat('dd/MM/yy');
    final presets = [
      'Este mes',
      'Mes anterior',
      'Trimestre',
      'Este año',
      'Año anterior',
      '12 meses',
      'Todo'
    ];
    return Material(
      color: AppTheme.surface,
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: AppLayout.centered(
          maxWidth: 1400,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final p in presets)
                    ChoiceChip(
                      label: Text(p, style: const TextStyle(fontSize: 12)),
                      selected: _presetActivo == p,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _preset(p),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.date_range_outlined, size: 14),
                    label: Text(
                        _presetActivo == 'Personalizado'
                            ? '${df.format(_f.desde)} → ${df.format(_f.hasta)}'
                            : 'Personalizado',
                        style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    onPressed: _personalizado,
                  ),
                  const SizedBox(width: 8),
                  const Text('Comparar con:',
                      style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                  SegmentedButton<Comparar>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        textStyle:
                            WidgetStatePropertyAll(TextStyle(fontSize: 11.5))),
                    segments: const [
                      ButtonSegment(
                          value: Comparar.periodoAnterior,
                          label: Text('Período anterior')),
                      ButtonSegment(
                          value: Comparar.anioAnterior,
                          label: Text('Año anterior')),
                      ButtonSegment(
                          value: Comparar.ninguno, label: Text('Nada')),
                    ],
                    selected: {_f.comparar},
                    onSelectionChanged: (s) =>
                        _cambiar(() => _f.comparar = s.first),
                  ),
                ]),
            const SizedBox(height: 8),
            Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final d in Dim.values) _selector(d),
                  FilterChip(
                    label: const Text('Incluir anuladas',
                        style: TextStyle(fontSize: 12)),
                    selected: _f.incluirAnuladas,
                    visualDensity: VisualDensity.compact,
                    onSelected: (v) => _cambiar(() => _f.incluirAnuladas = v),
                  ),
                  for (final e in const {
                    0: 'Todas',
                    1: 'Vigentes',
                    2: 'Vencidas'
                  }.entries)
                    ChoiceChip(
                      label:
                          Text(e.value, style: const TextStyle(fontSize: 12)),
                      selected: _f.estado == e.key,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _cambiar(() => _f.estado = e.key),
                    ),
                  if (_f.nDimensiones > 0 ||
                      _f.estado != 0 ||
                      _f.incluirAnuladas)
                    TextButton.icon(
                      onPressed: () => _cambiar(() {
                        _f.aseg =
                            _f.ramo = _f.prod = _f.asesor = _f.cliente = null;
                        _f.estado = 0;
                        _f.incluirAnuladas = false;
                      }),
                      icon: const Icon(Icons.clear, size: 14),
                      label: const Text('Limpiar filtros',
                          style: TextStyle(fontSize: 12)),
                    ),
                ]),
          ]),
        ),
      ),
    );
  }

  Widget _selector(Dim d) {
    final v = _f.valorDe(d);
    return InputChip(
      avatar: Icon(_iconoDim(d), size: 14),
      label: Text(
        v ?? etiquetaDim(d),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 12,
            fontWeight: v != null ? FontWeight.w700 : FontWeight.w500),
      ),
      selected: v != null,
      visualDensity: VisualDensity.compact,
      onPressed: () async {
        final r = await _elegir(etiquetaDim(d), _opciones(d), v);
        if (r != null && mounted) {
          _cambiar(() => _f.poner(d, r.isEmpty ? null : r));
        }
      },
      onDeleted: v == null ? null : () => _cambiar(() => _f.poner(d, null)),
    );
  }

  IconData _iconoDim(Dim d) => switch (d) {
        Dim.aseguradora => Icons.business_outlined,
        Dim.ramo => Icons.category_outlined,
        Dim.producto => Icons.inventory_2_outlined,
        Dim.asesor => Icons.badge_outlined,
        Dim.cliente => Icons.person_outline,
      };

  /// Selector con búsqueda. Devuelve '' para quitar el filtro.
  Future<String?> _elegir(
      String titulo, List<String> opciones, String? actual) {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        var q = '';
        return StatefulBuilder(builder: (ctx, setD) {
          final lista = opciones
              .where((o) => o.toLowerCase().contains(q.toLowerCase()))
              .take(300)
              .toList();
          return AlertDialog(
            title: Text(titulo),
            content: SizedBox(
              width: 380,
              height: 420,
              child: Column(children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search), hintText: 'Buscar…'),
                  onChanged: (v) => setD(() => q = v),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(children: [
                    if (actual != null)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.clear, size: 18),
                        title: const Text('Quitar filtro'),
                        onTap: () => Navigator.pop(ctx, ''),
                      ),
                    for (final o in lista)
                      ListTile(
                        dense: true,
                        selected: o == actual,
                        title: Text(o),
                        onTap: () => Navigator.pop(ctx, o),
                      ),
                    if (lista.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Sin resultados')),
                  ]),
                ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cerrar')),
            ],
          );
        });
      },
    );
  }

  // ── Utilidades de presentación ──────────────────────────────────────────

  String get _txtPeriodo {
    final df = DateFormat('d MMM yyyy', 'es_CO');
    String f(DateTime d) {
      try {
        return df.format(d);
      } catch (_) {
        return DateFormat('dd/MM/yyyy').format(d);
      }
    }

    return '${f(_f.desde)} – ${f(_f.hasta)}';
  }

  String get _txtComp {
    final c = _res?.comp;
    if (c == null) return '';
    final df = DateFormat('dd/MM/yy');
    return 'vs ${df.format(c.desde)} – ${df.format(c.hasta)}';
  }

  List<String> _etiquetasMeses(List<DateTime> m) {
    final conAnio = m.length > 12;
    return [for (final d in m) mesCorto(d, anio: conAnio)];
  }

  void _irPoliza(Poliza p) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PaginaFormularioPolizas(poliza: p)),
      );

  Widget _encabezado(String titulo, [String? sub]) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          Text(sub ?? '$_txtPeriodo${_txtComp.isEmpty ? '' : '  ·  $_txtComp'}',
              style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
        ]),
      );

  List<FilaRanking> _filasDim(Resultado r, Dim d, {String medida = 'prima'}) {
    return [
      for (final g in r.porDim[d]!)
        FilaRanking(
          g.nombre,
          switch (medida) {
            'n' => g.n.toDouble(),
            'comision' => g.comision.toDouble(),
            _ => g.prima.toDouble(),
          },
          color: DashColors.de(g.nombre),
          detalle:
              '${fmtEntero(g.n)} pólizas · ticket ${fmtCompacto(g.ticket)}',
          valorTexto: medida == 'n' ? fmtEntero(g.n) : null,
        ),
    ]..sort((a, b) => b.valor.compareTo(a.valor));
  }

  // ═══ TAB 1 · RESUMEN ═══════════════════════════════════════════════════

  List<Widget> _tabResumen(Resultado r) {
    final a = r.actual;
    final c = r.comp;
    final tasa = r.tasaRenovacion;
    final etiq = _etiquetasMeses(r.meses);
    final conPagos = _comisiones && _abonos != null;
    final cal = _calidad!;

    final kpis = <Widget>[
      KpiTile(
        etiqueta: 'Prima emitida',
        valor: '\$ ${fmtCompacto(a.prima)}',
        valorExacto: fmtMonto(a.prima),
        icono: Icons.payments_outlined,
        delta: variacion(a.prima, c?.prima),
        spark: a.primaMes,
        pie: c == null ? null : 'ant. \$ ${fmtCompacto(c.prima)}',
      ),
      KpiTile(
        etiqueta: 'Pólizas emitidas',
        valor: fmtEntero(a.n),
        icono: Icons.receipt_long_outlined,
        color: DashColors.serie[0],
        delta: variacion(a.n, c?.n),
        spark: a.nMes,
        pie: c == null ? null : 'ant. ${fmtEntero(c.n)}',
      ),
      KpiTile(
        etiqueta: 'Prima promedio',
        valor: '\$ ${fmtCompacto(a.ticket)}',
        valorExacto: fmtMonto(a.ticket),
        icono: Icons.sell_outlined,
        color: DashColors.serie[6],
        delta: variacion(a.ticket, c?.ticket),
        pie: c == null ? null : 'ant. \$ ${fmtCompacto(c.ticket)}',
      ),
      KpiTile(
        etiqueta: 'Clientes con póliza nueva',
        valor: fmtEntero(a.clientes),
        icono: Icons.groups_outlined,
        color: DashColors.serie[2],
        delta: variacion(a.clientes, c?.clientes),
        pie: '${fmtEntero(r.clientesNuevos)} nuevos',
        onTap: () => _tabs.animateTo(2),
      ),
      if (conPagos) ...[
        KpiTile(
          etiqueta: 'Comisión recibida',
          valor: '\$ ${fmtCompacto(a.comision)}',
          valorExacto: fmtMonto(a.comision),
          icono: Icons.savings_outlined,
          color: AppTheme.green,
          delta: variacion(a.comision, c?.comision),
          spark: a.comisionMes,
          pie: a.recaudo > 0
              ? '${fmtPct(a.comision / a.recaudo * 100)} del recaudo'
              : null,
        ),
        KpiTile(
          etiqueta: 'Recaudo de prima',
          valor: '\$ ${fmtCompacto(a.recaudo)}',
          valorExacto: fmtMonto(a.recaudo),
          icono: Icons.account_balance_wallet_outlined,
          color: DashColors.serie[2],
          delta: variacion(a.recaudo, c?.recaudo),
          spark: a.recaudoMes,
        ),
        KpiTile(
          etiqueta: 'Cartera por recaudar',
          valor: '\$ ${fmtCompacto(r.carteraSaldo)}',
          valorExacto: fmtMonto(r.carteraSaldo),
          icono: Icons.hourglass_bottom_outlined,
          color: AppTheme.warning,
          subirEsBueno: false,
          pie: r.carteraPrima > 0
              ? '${fmtPct(r.carteraPagada / r.carteraPrima * 100, dec: 0)} recaudado'
              : null,
          onTap: () => _tabs.animateTo(3),
        ),
      ],
      KpiTile(
        etiqueta: 'Renovación (estimada)',
        valor: tasa == null ? '—' : fmtPct(tasa * 100, dec: 0),
        icono: Icons.autorenew,
        color: DashColors.serie[3],
        pie: r.renBase == 0
            ? 'sin vencimientos en el período'
            : '${r.renRenovadas} de ${r.renBase} vencidas',
        onTap: () => _tabs.animateTo(_comisiones ? 4 : 3),
      ),
    ];

    final alertas = <Widget>[
      Alerta(
        icono: Icons.event_busy_outlined,
        color: r.vence30.$1 > 0 ? DashColors.alerta : DashColors.bueno,
        titulo: '${fmtEntero(r.vence30.$1)} pólizas vencen en 30 días',
        detalle:
            'Prima en juego: \$ ${fmtCompacto(r.vence30.$2)}. Es la renovación a gestionar ya.',
        onTap: () => _tabs.animateTo(_comisiones ? 4 : 3),
      ),
      Alerta(
        icono: Icons.history_toggle_off,
        color: r.sinRenovar90Tot.$1 > 0 ? DashColors.malo : DashColors.bueno,
        titulo:
            '${fmtEntero(r.sinRenovar90Tot.$1)} vencidas hace menos de 90 días sin renovar',
        detalle:
            'Prima perdida si no se recuperan: \$ ${fmtCompacto(r.sinRenovar90Tot.$2)}.',
        onTap: () => _tabs.animateTo(_comisiones ? 4 : 3),
      ),
      if (_comisiones)
        Alerta(
          icono: Icons.account_balance_wallet_outlined,
          color: (r.aging
                      .where((e) =>
                          e.key == 'Más de 180' || e.key == '91–180 días')
                      .fold<num>(0, (s, e) => s + e.value)) >
                  0
              ? DashColors.malo
              : DashColors.bueno,
          titulo:
              'Cartera con más de 90 días: \$ ${fmtCompacto(r.aging.where((e) => e.key == 'Más de 180' || e.key == '91–180 días').fold<num>(0, (s, e) => s + e.value))}',
          detalle: 'Prima emitida en el período que aún no se recauda.',
          onTap: () => _tabs.animateTo(3),
        ),
      if ((_casos ?? 0) > 0)
        Alerta(
          icono: Icons.fact_check_outlined,
          color: DashColors.alerta,
          titulo: '$_casos casos por revisar',
          detalle:
              'Pagos o pólizas dudosas pendientes de aclarar (menú principal → Casos por revisar).',
        ),
      Alerta(
        icono: cal.problemas == 0
            ? Icons.verified_outlined
            : Icons.rule_folder_outlined,
        color: cal.problemas == 0 ? DashColors.bueno : DashColors.alerta,
        titulo: cal.problemas == 0
            ? 'Datos completos'
            : 'Calidad de datos: ${fmtEntero(cal.problemas)} campos por completar',
        detalle: cal.problemas == 0
            ? 'Todas las pólizas tienen asesor, ramo, cliente, prima y vencimiento.'
            : 'Sin asesor ${fmtEntero(cal.sinAsesor)} · sin ramo ${fmtEntero(cal.sinRamo)} · '
                'sin vencimiento ${fmtEntero(cal.sinVencimiento)} · sin prima ${fmtEntero(cal.sinPrima)} · '
                'sin cliente ${fmtEntero(cal.sinCliente)} (de ${fmtEntero(cal.total)}). '
                'Afectan la precisión de este tablero.',
      ),
    ];

    return [
      _encabezado('Resumen ejecutivo'),
      Rejilla(anchoMinimo: 230, hijos: kpis),
      Rejilla(anchoMinimo: 520, maxColumnas: 2, hijos: [
        DashCard(
          titulo: 'Prima emitida por mes',
          subtitulo: c == null
              ? 'Período seleccionado'
              : 'Período seleccionado vs comparación',
          child: GraficoLineas(
            etiquetas: etiq,
            series: [
              SerieLinea('Actual', a.primaMes, DashColors.real),
              if (c != null)
                SerieLinea('Comparación', c.primaMes, DashColors.comparacion,
                    punteada: true),
            ],
          ),
        ),
        DashCard(
          titulo: 'Atención del día',
          subtitulo: 'Lo que requiere una acción',
          child: Column(children: alertas),
        ),
      ]),
      Rejilla(anchoMinimo: 460, maxColumnas: 3, hijos: [
        DashCard(
          titulo: 'Prima por aseguradora',
          subtitulo: 'Toque una rebanada para filtrar',
          child: GraficoDona(
            datos: [
              for (final g in r.porDim[Dim.aseguradora]!)
                Rebanada(g.nombre, g.prima.toDouble())
            ],
            seleccionado: _f.aseg,
            centro: 'prima total',
            onTap: (n) => _toggleDim(Dim.aseguradora, n),
          ),
        ),
        DashCard(
          titulo: 'Prima por ramo',
          subtitulo: 'Toque una rebanada para filtrar',
          child: GraficoDona(
            datos: [
              for (final g in r.porDim[Dim.ramo]!)
                Rebanada(g.nombre, g.prima.toDouble())
            ],
            seleccionado: _f.ramo,
            centro: 'prima total',
            onTap: (n) => _toggleDim(Dim.ramo, n),
          ),
        ),
        DashCard(
          titulo: 'Top 5 asesores',
          subtitulo: 'Por prima emitida',
          child: RankingBarras(
            filas: _filasDim(r, Dim.asesor),
            maxFilas: 5,
            seleccionado: _f.asesor,
            onTap: (n) => _toggleDim(Dim.asesor, n),
          ),
        ),
      ]),
    ];
  }

  // ═══ TAB 2 · PRODUCCIÓN ════════════════════════════════════════════════

  List<Widget> _tabProduccion(Resultado r) {
    final a = r.actual;
    final c = r.comp;
    final dim = _dimExplorador;
    final grupos = r.porDim[dim]!;
    final totalPrima = a.prima;

    // Año en curso vs anterior (ignora el período; respeta los demás filtros).
    final anio = _f.hasta.year;
    final fy = _f.copia()
      ..desde = DateTime(anio - 1, 1, 1)
      ..hasta = DateTime(anio, 12, 31)
      ..comparar = Comparar.ninguno;
    final ry = _motor!.calcular(fy);
    final mActual =
        List<double>.generate(12, (i) => ry.actual.primaMes[12 + i]);
    final mPrev = List<double>.generate(12, (i) => ry.actual.primaMes[i]);
    final hoy = DateTime.now();
    // El año en curso no se grafica más allá del mes actual.
    final limite = anio == hoy.year ? hoy.month : 12;
    final nMes = List<double>.generate(12, (i) => ry.actual.nMes[12 + i]);
    final nPrev = List<double>.generate(12, (i) => ry.actual.nMes[i]);
    final meses12 = [
      for (var i = 1; i <= 12; i++) mesCorto(DateTime(2000, i, 1))
    ];

    return [
      _encabezado('Producción'),
      Rejilla(anchoMinimo: 520, maxColumnas: 2, hijos: [
        DashCard(
          titulo: 'Prima mensual: $anio vs ${anio - 1}',
          subtitulo: 'Todo el año, con los filtros de arriba (sin el período)',
          child: GraficoLineas(
            etiquetas: meses12,
            series: [
              SerieLinea('$anio', mActual.sublist(0, limite), DashColors.real),
              SerieLinea('${anio - 1}', mPrev, DashColors.comparacion,
                  punteada: true),
            ],
          ),
        ),
        DashCard(
          titulo: 'Pólizas emitidas por mes: $anio vs ${anio - 1}',
          child: GraficoColumnas(
            etiquetas: meses12,
            formato: fmtEntero,
            series: [
              SerieColumna('${anio - 1}', nPrev, DashColors.comparacion),
              SerieColumna(
                  '$anio',
                  [
                    ...nMes.sublist(0, limite),
                    ...List.filled(12 - limite, 0.0)
                  ],
                  DashColors.real),
            ],
          ),
        ),
      ]),
      DashCard(
        titulo: 'Explorador de producción',
        subtitulo:
            'Cambie la dimensión; toque una fila para filtrar todo el tablero'
            '${c == null ? '' : ' · variación contra la comparación'}',
        accion: SegmentedButton<Dim>(
          showSelectedIcon: false,
          style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11.5))),
          segments: [
            for (final d in Dim.values.where((d) => d != Dim.cliente))
              ButtonSegment(value: d, label: Text(etiquetaDim(d))),
          ],
          selected: {dim},
          onSelectionChanged: (s) => setState(() => _dimExplorador = s.first),
        ),
        child: _tablaExplorador(r, dim, grupos, totalPrima),
      ),
      Rejilla(anchoMinimo: 520, maxColumnas: 2, hijos: [
        DashCard(
          titulo: 'Aseguradora × ramo (prima)',
          subtitulo:
              'Los 8 mayores de cada eje. Toque una celda para filtrar por ambos.',
          child: MapaCalor(
            filas: r.matrizFilas,
            columnas: r.matrizCols,
            valores: r.matriz,
            onTap: (f, col) => _cambiar(() {
              _f.aseg = f;
              _f.ramo = col;
            }),
          ),
        ),
        DashCard(
          titulo: 'Top productos',
          subtitulo: 'Por prima emitida',
          child: RankingBarras(
            filas: _filasDim(r, Dim.producto),
            maxFilas: 12,
            seleccionado: _f.prod,
            onTap: (n) => _toggleDim(Dim.producto, n),
          ),
        ),
      ]),
    ];
  }

  Widget _tablaExplorador(Resultado r, Dim dim, List<Grupo> grupos, num total) {
    final comp = r.comp;
    // Prima del período de comparación por grupo
    Map<String, num> prev = {};
    if (comp != null) {
      for (final p in comp.polizas) {
        final k = claveDim(p, dim);
        prev[k] = (prev[k] ?? 0) + p.primaPoliza;
      }
    }
    final filas = grupos.take(25).toList();
    if (filas.isEmpty) return const SinDatos();
    final mx = filas.first.prima == 0 ? 1 : filas.first.prima;
    TextStyle h = const TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.inkSoft);
    Widget celda(String t, double w, {bool der = true, TextStyle? s}) =>
        SizedBox(
          width: w,
          child: Text(t,
              textAlign: der ? TextAlign.right : TextAlign.left,
              overflow: TextOverflow.ellipsis,
              style: s ?? const TextStyle(fontSize: 12)),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 760),
        child: Column(children: [
          Row(children: [
            celda(etiquetaDim(dim), 200, der: false, s: h),
            SizedBox(width: 180, child: Text('Prima', style: h)),
            celda('Pólizas', 64, s: h),
            celda('Prima prom.', 90, s: h),
            celda('% total', 60, s: h),
            if (comp != null) celda('Var.', 70, s: h),
            if (_comisiones && _abonos != null) celda('Comisión', 90, s: h),
          ]),
          const Divider(height: 10),
          for (final g in filas)
            InkWell(
              onTap: () => _toggleDim(dim, g.nombre),
              child: Container(
                color: _f.valorDe(dim) == g.nombre
                    ? AppTheme.navy.withOpacity(0.08)
                    : null,
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
                child: Row(children: [
                  SizedBox(
                    width: 200,
                    child: Row(children: [
                      Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: DashColors.de(g.nombre),
                              shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(g.nombre,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                  SizedBox(
                    width: 180,
                    child: Row(children: [
                      Expanded(
                        child: LayoutBuilder(
                            builder: (_, c) => Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    height: 10,
                                    width: (c.maxWidth * (g.prima / mx))
                                        .clamp(2, c.maxWidth)
                                        .toDouble(),
                                    decoration: BoxDecoration(
                                        color: DashColors.real,
                                        borderRadius: BorderRadius.circular(3)),
                                  ),
                                )),
                      ),
                      const SizedBox(width: 6),
                      Text(fmtCompacto(g.prima),
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 6),
                    ]),
                  ),
                  celda(fmtEntero(g.n), 64),
                  celda(fmtCompacto(g.ticket), 90),
                  celda(total == 0 ? '' : fmtPct(g.prima / total * 100), 60),
                  if (comp != null)
                    Builder(builder: (_) {
                      final v = variacion(g.prima, prev[g.nombre]);
                      return celda(
                        v == null
                            ? 'nuevo'
                            : '${v >= 0 ? '+' : ''}${fmtPct(v, dec: 0)}',
                        70,
                        s: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: v == null
                              ? AppTheme.inkSoft
                              : (v >= 0 ? DashColors.bueno : DashColors.malo),
                        ),
                      );
                    }),
                  if (_comisiones && _abonos != null)
                    celda(fmtCompacto(g.comision), 90),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  // ═══ TAB 3 · CLIENTES Y ASESORES ═══════════════════════════════════════

  List<Widget> _tabClientesAsesores(Resultado r) {
    final a = r.actual;
    final asesores = r.porDim[Dim.asesor]!;
    final totalCli = r.clientesNuevos + r.clientesRecurrentes;
    final cross = _crossSell();

    return [
      _encabezado('Clientes y asesores'),
      Rejilla(anchoMinimo: 230, hijos: [
        KpiTile(
          etiqueta: 'Clientes con póliza en el período',
          valor: fmtEntero(a.clientes),
          icono: Icons.groups_outlined,
          color: DashColors.serie[2],
          pie:
              '${fmtEntero(r.clientesNuevos)} nuevos · ${fmtEntero(r.clientesRecurrentes)} recurrentes',
        ),
        KpiTile(
          etiqueta: 'Concentración top 10 clientes',
          valor: fmtPct(r.concentracionTop10, dec: 0),
          icono: Icons.pie_chart_outline,
          color: r.concentracionTop10 > 50 ? AppTheme.warning : AppTheme.navy,
          subirEsBueno: false,
          pie: r.concentracionTop10 > 50
              ? 'Riesgo: dependencia alta'
              : 'Cartera diversificada',
        ),
        KpiTile(
          etiqueta: 'Prima de clientes nuevos',
          valor: '\$ ${fmtCompacto(r.primaNuevos)}',
          valorExacto: fmtMonto(r.primaNuevos),
          icono: Icons.person_add_alt_1_outlined,
          color: DashColors.serie[0],
          pie: a.prima == 0
              ? null
              : '${fmtPct(r.primaNuevos / a.prima * 100, dec: 0)} de la prima',
        ),
        KpiTile(
          etiqueta: 'Clientes con 1 solo ramo',
          valor:
              cross.$1 == 0 ? '—' : fmtPct(cross.$2 / cross.$1 * 100, dec: 0),
          icono: Icons.hub_outlined,
          color: DashColors.serie[1],
          pie:
              'oportunidad de venta cruzada (${fmtEntero(cross.$2)} de ${fmtEntero(cross.$1)})',
        ),
      ]),
      Rejilla(anchoMinimo: 520, maxColumnas: 2, hijos: [
        DashCard(
          titulo: 'Ranking de asesores',
          subtitulo: 'Prima emitida en el período. Toque para filtrar.',
          child: RankingBarras(
            filas: _filasDim(r, Dim.asesor),
            maxFilas: 15,
            seleccionado: _f.asesor,
            onTap: (n) => _toggleDim(Dim.asesor, n),
          ),
        ),
        DashCard(
          titulo: 'Top 15 clientes',
          subtitulo: 'Por prima emitida en el período',
          child: RankingBarras(
            filas: [
              for (final c in r.clientesTop)
                FilaRanking(c.nombre, c.prima.toDouble(),
                    detalle: '${c.n} pólizas', color: DashColors.real)
            ],
            maxFilas: 15,
            seleccionado: _f.cliente,
            onTap: (n) => _toggleDim(Dim.cliente, n),
          ),
        ),
      ]),
      Rejilla(anchoMinimo: 520, maxColumnas: 2, hijos: [
        DashCard(
          titulo: 'Curva de concentración (Pareto)',
          subtitulo: '% de la prima que explican los N mayores clientes',
          child: r.pareto.length < 2
              ? const SinDatos()
              : GraficoLineas(
                  etiquetas: [for (var i = 1; i <= r.pareto.length; i++) '$i'],
                  series: [
                    SerieLinea('% acumulado', r.pareto, DashColors.real)
                  ],
                  formato: (v) => '${v.round()}%',
                ),
        ),
        DashCard(
          titulo: 'Clientes nuevos vs recurrentes',
          subtitulo:
              'Nuevo = su primera póliza en el sistema cae dentro del período',
          child: GraficoDona(
            datos: [
              Rebanada('Nuevos', r.clientesNuevos.toDouble()),
              Rebanada('Recurrentes', r.clientesRecurrentes.toDouble()),
            ],
            centro: 'clientes ($totalCli)',
            formato: fmtEntero,
          ),
        ),
      ]),
      DashCard(
        titulo: 'Detalle por asesor',
        subtitulo:
            'Producción, ticket y${_comisiones && _abonos != null ? ' comisión recibida' : ' participación'}',
        child: _tablaAsesores(asesores, a.prima),
      ),
    ];
  }

  /// (clientes con pólizas vigentes, de esos cuántos tienen un solo ramo).
  (int, int) _crossSell() {
    final hoy = DateTime.now();
    final h = DateTime(hoy.year, hoy.month, hoy.day);
    final m = <String, Set<int>>{};
    for (final p in _polizas) {
      if (p.estadoPolizaId == 'A' ||
          p.ffinPoliza == null ||
          p.ffinPoliza!.isBefore(h)) continue;
      (m[MotorDash.claveCliente(p)] ??= {}).add(p.ramoId ?? 0);
    }
    return (m.length, m.values.where((s) => s.length == 1).length);
  }

  Widget _tablaAsesores(List<Grupo> g, num total) {
    final conCom = _comisiones && _abonos != null;
    final filas = g.take(30).toList();
    if (filas.isEmpty) return const SinDatos();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 22,
        headingRowHeight: 36,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 38,
        columns: [
          const DataColumn(label: Text('Asesor')),
          const DataColumn(label: Text('Pólizas'), numeric: true),
          const DataColumn(label: Text('Prima'), numeric: true),
          const DataColumn(label: Text('Prima prom.'), numeric: true),
          const DataColumn(label: Text('% total'), numeric: true),
          if (conCom)
            const DataColumn(label: Text('Comisión recibida'), numeric: true),
          if (conCom) const DataColumn(label: Text('Recaudo'), numeric: true),
        ],
        rows: [
          for (final x in filas)
            DataRow(
              selected: _f.asesor == x.nombre,
              onSelectChanged: (_) => _toggleDim(Dim.asesor, x.nombre),
              cells: [
                DataCell(Text(x.nombre)),
                DataCell(Text(fmtEntero(x.n))),
                DataCell(Text(fmtMonto(x.prima))),
                DataCell(Text(fmtMonto(x.ticket))),
                DataCell(Text(total == 0 ? '' : fmtPct(x.prima / total * 100))),
                if (conCom) DataCell(Text(fmtMonto(x.comision))),
                if (conCom) DataCell(Text(fmtMonto(x.recaudo))),
              ],
            ),
        ],
      ),
    );
  }

  // ═══ TAB 4 · CARTERA Y RECAUDO (A / S) ═════════════════════════════════

  List<Widget> _tabCartera(Resultado r) {
    final a = r.actual;
    final c = r.comp;
    final etiq = _etiquetasMeses(r.meses);
    if (_abonos == null) {
      return [
        _encabezado('Cartera y recaudo'),
        const DashCard(
            titulo: 'Sin datos de pagos',
            child: Text(
                'No se pudieron cargar los pagos. Use "Actualizar datos" e intente de nuevo.')),
      ];
    }
    final pctRec =
        r.carteraPrima == 0 ? 0.0 : r.carteraPagada / r.carteraPrima * 100;
    final agingFilas = [
      for (final e in r.aging)
        FilaRanking(e.key, e.value.toDouble(),
            color: (e.key == 'Más de 180' || e.key == '91–180 días')
                ? DashColors.malo
                : (e.key == '61–90 días' ? DashColors.alerta : DashColors.real))
    ];
    return [
      _encabezado(
          'Cartera y recaudo',
          'Cartera = prima emitida en el período − prima ya recaudada (pólizas no anuladas). '
              'Recaudo y comisión = pagos registrados con fecha dentro del período.'),
      Rejilla(anchoMinimo: 230, hijos: [
        KpiTile(
          etiqueta: 'Prima emitida (período)',
          valor: '\$ ${fmtCompacto(r.carteraPrima)}',
          valorExacto: fmtMonto(r.carteraPrima),
          icono: Icons.payments_outlined,
        ),
        KpiTile(
          etiqueta: 'Ya recaudada',
          valor: '\$ ${fmtCompacto(r.carteraPagada)}',
          valorExacto: fmtMonto(r.carteraPagada),
          icono: Icons.task_alt,
          color: AppTheme.green,
          pie: '${fmtPct(pctRec, dec: 0)} de lo emitido',
        ),
        KpiTile(
          etiqueta: 'Por recaudar',
          valor: '\$ ${fmtCompacto(r.carteraSaldo)}',
          valorExacto: fmtMonto(r.carteraSaldo),
          icono: Icons.hourglass_bottom_outlined,
          color: AppTheme.warning,
          subirEsBueno: false,
        ),
        KpiTile(
          etiqueta: 'Comisión recibida',
          valor: '\$ ${fmtCompacto(a.comision)}',
          valorExacto: fmtMonto(a.comision),
          icono: Icons.savings_outlined,
          color: AppTheme.green,
          delta: variacion(a.comision, c?.comision),
          pie: a.recaudo > 0
              ? '${fmtPct(a.comision / a.recaudo * 100)} efectivo'
              : null,
        ),
      ]),
      Rejilla(anchoMinimo: 520, maxColumnas: 2, hijos: [
        DashCard(
          titulo: 'Recaudo y comisión por mes',
          subtitulo: 'Pagos registrados con fecha en el período',
          child: GraficoColumnas(
            etiquetas: etiq,
            series: [
              SerieColumna('Recaudo de prima', a.recaudoMes, DashColors.real),
              SerieColumna('Comisión', a.comisionMes, AppTheme.green),
            ],
          ),
        ),
        DashCard(
          titulo: 'Antigüedad de la cartera por recaudar',
          subtitulo:
              'Días desde el inicio de vigencia de cada póliza con saldo',
          child:
              RankingBarras(filas: agingFilas, mostrarPct: true, maxFilas: 6),
        ),
      ]),
      Rejilla(anchoMinimo: 520, maxColumnas: 2, hijos: [
        DashCard(
          titulo: 'Comisión recibida por aseguradora',
          subtitulo: 'Toque para filtrar',
          child: RankingBarras(
            filas: _filasDim(r, Dim.aseguradora, medida: 'comision'),
            seleccionado: _f.aseg,
            onTap: (n) => _toggleDim(Dim.aseguradora, n),
          ),
        ),
        DashCard(
          titulo: 'Mayores saldos por cliente',
          subtitulo: 'Prima emitida en el período aún sin recaudar',
          child: RankingBarras(
            filas: [
              for (final d in r.deudores)
                FilaRanking(d.nombre, d.prima.toDouble(),
                    color: AppTheme.warning,
                    detalle: '${d.n} pólizas con saldo')
            ],
            seleccionado: _f.cliente,
            onTap: (n) => _toggleDim(Dim.cliente, n),
            mostrarPct: false,
          ),
        ),
      ]),
      DashCard(
        titulo: 'Rentabilidad por aseguradora',
        subtitulo: 'Comisión efectiva = comisión recibida ÷ prima recaudada',
        child: _tablaRentabilidad(r),
      ),
    ];
  }

  Widget _tablaRentabilidad(Resultado r) {
    final g = r.porDim[Dim.aseguradora]!.where((x) => x.recaudo > 0).toList()
      ..sort((a, b) => b.comision.compareTo(a.comision));
    if (g.isEmpty) return const SinDatos();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 26,
        headingRowHeight: 36,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 36,
        columns: const [
          DataColumn(label: Text('Aseguradora')),
          DataColumn(label: Text('Prima recaudada'), numeric: true),
          DataColumn(label: Text('Comisión'), numeric: true),
          DataColumn(label: Text('Comisión efectiva'), numeric: true),
        ],
        rows: [
          for (final x in g.take(20))
            DataRow(
              onSelectChanged: (_) => _toggleDim(Dim.aseguradora, x.nombre),
              cells: [
                DataCell(Text(x.nombre)),
                DataCell(Text(fmtMonto(x.recaudo))),
                DataCell(Text(fmtMonto(x.comision))),
                DataCell(Text(fmtPct(x.comision / x.recaudo * 100))),
              ],
            ),
        ],
      ),
    );
  }

  // ═══ TAB 5 · RENOVACIONES ══════════════════════════════════════════════

  List<Widget> _tabRenovaciones(Resultado r) {
    final df = DateFormat('dd/MM/yyyy');
    final tasa = r.tasaRenovacion;
    final ren = r.renPorAseg.where((g) => g.n >= 3).toList()
      ..sort((a, b) => (b.prima / b.n).compareTo(a.prima / a.n));
    final renAsesor = r.renPorAsesor.where((g) => g.n >= 3).toList()
      ..sort((a, b) => (b.prima / b.n).compareTo(a.prima / a.n));

    List<FilaRanking> filasTasa(List<Grupo> l) => [
          for (final g in l.take(10))
            FilaRanking(g.nombre, g.prima / g.n * 100,
                valorTexto: fmtPct(g.prima / g.n * 100, dec: 0),
                detalle: '${g.prima.round()} de ${g.n} renovadas',
                color: (g.prima / g.n) >= 0.7
                    ? DashColors.bueno
                    : ((g.prima / g.n) >= 0.5
                        ? DashColors.alerta
                        : DashColors.malo))
        ];

    Widget tabla(List<FilaPoliza> filas, String colDias) {
      if (filas.isEmpty) return const SinDatos();
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 20,
          headingRowHeight: 34,
          dataRowMinHeight: 32,
          dataRowMaxHeight: 36,
          columns: [
            const DataColumn(label: Text('Póliza')),
            const DataColumn(label: Text('Cliente')),
            const DataColumn(label: Text('Aseguradora')),
            const DataColumn(label: Text('Asesor')),
            const DataColumn(label: Text('Vence')),
            DataColumn(label: Text(colDias), numeric: true),
            const DataColumn(label: Text('Prima'), numeric: true),
          ],
          rows: [
            for (final f in filas)
              DataRow(
                onSelectChanged: (_) => _irPoliza(f.p),
                cells: [
                  DataCell(Text(f.p.nroPoliza ?? '—')),
                  DataCell(SizedBox(
                      width: 200,
                      child: Text(f.p.nombreCliente ?? '—',
                          overflow: TextOverflow.ellipsis))),
                  DataCell(Text(f.p.nombreAseg ?? '—')),
                  DataCell(Text(f.p.nombreAsesor ?? '—')),
                  DataCell(Text(f.p.ffinPoliza == null
                      ? '—'
                      : df.format(f.p.ffinPoliza!))),
                  DataCell(Text('${f.dias}')),
                  DataCell(Text(fmtMonto(f.valor))),
                ],
              ),
          ],
        ),
      );
    }

    return [
      _encabezado(
          'Renovaciones',
          'Vencimientos futuros desde hoy (respetan los filtros). La tasa de renovación es una estimación: '
              'se cuenta como renovada la póliza vencida en el período si el cliente tiene otra del mismo ramo que arranca cerca de su fin.'),
      Rejilla(anchoMinimo: 230, hijos: [
        KpiTile(
          etiqueta: 'Vencen en 0–30 días',
          valor: fmtEntero(r.vence30.$1),
          icono: Icons.warning_amber_outlined,
          color: DashColors.malo,
          pie: '\$ ${fmtCompacto(r.vence30.$2)} en prima',
        ),
        KpiTile(
          etiqueta: 'Vencen en 31–60 días',
          valor: fmtEntero(r.vence60.$1),
          icono: Icons.access_time_outlined,
          color: DashColors.alerta,
          pie: '\$ ${fmtCompacto(r.vence60.$2)} en prima',
        ),
        KpiTile(
          etiqueta: 'Vencen en 61–90 días',
          valor: fmtEntero(r.vence90.$1),
          icono: Icons.event_outlined,
          color: DashColors.serie[3],
          pie: '\$ ${fmtCompacto(r.vence90.$2)} en prima',
        ),
        KpiTile(
          etiqueta: 'Tasa de renovación (estimada)',
          valor: tasa == null ? '—' : fmtPct(tasa * 100, dec: 0),
          icono: Icons.autorenew,
          color: tasa == null
              ? AppTheme.inkSoft
              : (tasa >= 0.7
                  ? AppTheme.green
                  : (tasa >= 0.5 ? AppTheme.warning : AppTheme.danger)),
          pie: r.renBase == 0
              ? 'ninguna venció en el período'
              : '${r.renRenovadas} de ${r.renBase} vencidas en el período',
        ),
      ]),
      Rejilla(anchoMinimo: 520, maxColumnas: 2, hijos: [
        DashCard(
          titulo: 'Vencimientos de los próximos 12 meses',
          subtitulo:
              'Prima de las pólizas que vencen cada mes (la renovación de mañana)',
          child: GraficoColumnas(
            etiquetas: _etiquetasMeses(r.mesesFuturos),
            series: [
              SerieColumna('Prima que vence', r.vencePrima, DashColors.real)
            ],
          ),
        ),
        DashCard(
          titulo: 'Cantidad que vence por mes',
          child: GraficoColumnas(
            etiquetas: _etiquetasMeses(r.mesesFuturos),
            formato: fmtEntero,
            series: [SerieColumna('Pólizas', r.venceN, DashColors.serie[3])],
          ),
        ),
      ]),
      Rejilla(anchoMinimo: 520, maxColumnas: 2, hijos: [
        DashCard(
          titulo: 'Renovación por aseguradora',
          subtitulo: 'Mínimo 3 pólizas vencidas en el período',
          child: RankingBarras(filas: filasTasa(ren), mostrarPct: false),
        ),
        DashCard(
          titulo: 'Renovación por asesor',
          subtitulo: 'Mínimo 3 pólizas vencidas en el período',
          child: RankingBarras(filas: filasTasa(renAsesor), mostrarPct: false),
        ),
      ]),
      DashCard(
        titulo: 'A renovar en los próximos 30 días',
        subtitulo:
            'Ordenadas por fecha de vencimiento · toque para abrir la póliza',
        child: tabla(r.porRenovar30, 'Días'),
      ),
      DashCard(
        titulo: 'Vencidas en los últimos 90 días sin renovar',
        subtitulo:
            'Oportunidad de recuperación, mayor prima primero · toque para abrir la póliza',
        child: tabla(r.sinRenovar90, 'Días vencida'),
      ),
    ];
  }

  // ═══ TAB 6 · METAS (A / S) ═════════════════════════════════════════════

  List<Meta>? _metas;
  bool _metasCargando = false;
  String? _metasError;
  int _metasAnioCargado = 0;

  Future<void> _cargarMetas() async {
    if (_metasCargando) return;
    _metasCargando = true;
    try {
      final m = await _repoDash.listarMetas(_anioMetas);
      if (!mounted) return;
      setState(() {
        _metas = m;
        _metasError = null;
        _metasAnioCargado = _anioMetas;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _metas = [];
        _metasError = e.toString();
        _metasAnioCargado = _anioMetas;
      });
    } finally {
      _metasCargando = false;
    }
  }

  List<Widget> _tabMetas(Resultado r) {
    if (_metasAnioCargado != _anioMetas && !_metasCargando) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _cargarMetas());
    }
    final metas = _metas;
    final hoy = DateTime.now();
    final motor = _motor!;
    final asesorSel = _f.asesor == null
        ? null
        : _polizas
            .firstWhere((p) => p.nombreAsesor == _f.asesor,
                orElse: () => _polizas.first)
            .asesorId;
    final real = motor.realesAnio(_anioMetas, asesorId: asesorSel);

    double metaDe(String ind, int mes) {
      if (metas == null) return 0;
      return metas
          .where((m) =>
              m.indicador == ind &&
              m.mes == mes &&
              m.asesorId == (asesorSel ?? 0))
          .fold<double>(0, (s, m) => s + m.valor.toDouble());
    }

    final indicadores = kIndicadoresMeta
        .where((i) => !i.soloComisiones || _comisiones)
        .toList();
    final esActual = _anioMetas == hoy.year;
    final mesRef = esActual ? hoy.month : (_anioMetas < hoy.year ? 12 : 1);
    final diasMes = DateTime(_anioMetas, mesRef + 1, 0).day;
    final fracMes =
        esActual ? hoy.day / diasMes : (_anioMetas < hoy.year ? 1.0 : 0.0);
    final fracAnio = esActual
        ? (hoy.difference(DateTime(hoy.year, 1, 1)).inDays + 1) /
            (DateTime(hoy.year, 12, 31)
                    .difference(DateTime(hoy.year, 1, 1))
                    .inDays +
                1)
        : (_anioMetas < hoy.year ? 1.0 : 0.0);

    final tarjetas = <Widget>[];
    for (final i in indicadores) {
      final fmt = i.monetario
          ? (num v) => '\$ ${fmtCompacto(v)}'
          : (num v) => fmtEntero(v);
      final realMes = real[i.clave]![mesRef - 1];
      final metaMes = metaDe(i.clave, mesRef);
      final realAnio = real[i.clave]!.fold<double>(0, (s, v) => s + v);
      final metaAnio = List.generate(12, (k) => metaDe(i.clave, k + 1))
          .fold<double>(0, (s, v) => s + v);
      final proy =
          fracAnio > 0 && fracAnio < 1 ? realAnio / fracAnio : realAnio;
      tarjetas.add(DashCard(
        titulo: i.nombre,
        subtitulo:
            asesorSel == null ? 'Toda la agencia' : 'Asesor: ${_f.asesor}',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          BarraMeta(
            titulo:
                'Mes: ${mesCorto(DateTime(_anioMetas, mesRef, 1), anio: true)}',
            real: realMes,
            meta: metaMes,
            esperado: fracMes,
            formato: fmt,
          ),
          const SizedBox(height: 14),
          BarraMeta(
            titulo: 'Año $_anioMetas acumulado',
            real: realAnio,
            meta: metaAnio,
            esperado: fracAnio,
            formato: fmt,
          ),
          if (metaAnio > 0 && esActual) ...[
            const SizedBox(height: 8),
            Text(
              'Al ritmo actual cerraría en ${fmt(proy)} (${fmtPct(proy / metaAnio * 100, dec: 0)} de la meta).',
              style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
            ),
          ],
        ]),
      ));
    }

    final etiq = [for (var m = 1; m <= 12; m++) mesCorto(DateTime(2000, m, 1))];
    final primaReal = real['prima']!;
    final primaMeta = [for (var m = 1; m <= 12; m++) metaDe('prima', m)];

    return [
      Row(children: [
        Expanded(
            child: _encabezado('Metas y cumplimiento',
                'La marca negra indica dónde debería ir el avance según los días transcurridos.')),
        IconButton(
          tooltip: 'Año anterior',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => setState(() => _anioMetas--),
        ),
        Text('$_anioMetas',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        IconButton(
          tooltip: 'Año siguiente',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => setState(() => _anioMetas++),
        ),
        if (Sesion.esAdmin)
          FilledButton.icon(
            onPressed: () async {
              final guardo = await mostrarDialogoMetas(
                context,
                anio: _anioMetas,
                metasActuales: _metas ?? [],
                asesores: _asesoresDeDatos(),
              );
              if (guardo == true) {
                _metasAnioCargado = 0;
                await _cargarMetas();
              }
            },
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text('Configurar metas'),
          ),
      ]),
      if (_metasError != null)
        DashCard(
          titulo: 'Metas no disponibles',
          child: Text(
            _metasError!.contains('metas_comerciales')
                ? 'Falta crear la tabla de metas. Ejecute la migración 20261005090000_metas_comerciales.sql en Supabase.'
                : 'No se pudieron leer las metas: $_metasError',
          ),
        )
      else if (metas != null && metas.isEmpty)
        DashCard(
          titulo: 'Aún no hay metas para $_anioMetas',
          child: Text(Sesion.esAdmin
              ? 'Use "Configurar metas" para definir la meta mensual de cada indicador (agencia o por asesor).'
              : 'Un administrador debe configurar las metas del año.'),
        ),
      Rejilla(anchoMinimo: 380, maxColumnas: 2, hijos: tarjetas),
      DashCard(
        titulo: 'Prima emitida: real vs meta por mes',
        child: GraficoColumnas(
          etiquetas: etiq,
          series: [
            SerieColumna('Meta', primaMeta, DashColors.comparacion),
            SerieColumna('Real', primaReal, DashColors.real),
          ],
        ),
      ),
      if (asesorSel == null)
        DashCard(
          titulo: 'Cumplimiento de prima por asesor (mes de referencia)',
          subtitulo: 'Meta individual del mes vs prima emitida',
          child: _tablaMetasAsesor(mesRef, fracMes),
        ),
    ];
  }

  List<({int id, String nombre})> _asesoresDeDatos() {
    final m = <int, String>{};
    for (final p in _polizas) {
      if (p.asesorId != null && p.nombreAsesor != null) {
        m[p.asesorId!] = p.nombreAsesor!;
      }
    }
    final l = [for (final e in m.entries) (id: e.key, nombre: e.value)];
    l.sort((a, b) => a.nombre.compareTo(b.nombre));
    return l;
  }

  Widget _tablaMetasAsesor(int mes, double frac) {
    final metas = _metas ?? [];
    final porAsesor = metas
        .where((m) =>
            m.indicador == 'prima' &&
            m.mes == mes &&
            m.asesorId != 0 &&
            m.valor > 0)
        .toList();
    if (porAsesor.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No hay metas individuales de prima para este mes.',
            style: TextStyle(color: AppTheme.inkSoft, fontSize: 12)),
      );
    }
    final nombres = {for (final a in _asesoresDeDatos()) a.id: a.nombre};
    return Column(children: [
      for (final m in porAsesor)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: BarraMeta(
            titulo: nombres[m.asesorId] ?? 'Asesor ${m.asesorId}',
            real: _motor!.realesAnio(_anioMetas,
                asesorId: m.asesorId)['prima']![mes - 1],
            meta: m.valor.toDouble(),
            esperado: frac,
            formato: (v) => '\$ ${fmtCompacto(v)}',
          ),
        ),
    ]);
  }
}
