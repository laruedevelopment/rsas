// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../datos/abono_poliza.dart';
import '../datos/matching_reporte_pago.dart';
import '../datos/poliza.dart';
import '../datos/repositorio_catalogos.dart';
import '../datos/repositorio_pagos.dart';
import '../datos/repositorio_polizas.dart';
import '../utils/formatters.dart';
import '../utils/numeros_co.dart';
import 'theme/app_layout.dart';
import 'theme/app_theme.dart';
import 'widgets/buscador_dropdown.dart';
import 'widgets/selector_fecha.dart';
import '../utils/mensajes_error.dart';

bool _mismoDia(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Factura/recibo comparable: sin espacios ni separadores ni ceros a la
/// izquierda ("000123" = "123", "FE-12" = "FE12").
String _normalizarFactura(String? s) =>
    normalizarDoc(s ?? '').replaceFirst(RegExp(r'^0+(?=.)'), '');

/// Una línea del documento importado, ya con sus controllers de edición.
class _LineaRevision {
  bool incluir;
  Poliza? poliza;
  final ResultadoMatch match;

  /// El usuario eligió la póliza a mano (reemplaza el estado automático).
  bool manual = false;

  /// Motivo si parece un abono ya cargado antes.
  String? duplicado;

  /// La comisión no venía en el reporte: se calculó con abono × %.
  bool comisionCalculada;

  /// Error al guardar esta línea (queda en pantalla para reintentar).
  String? errorGuardado;

  final String nroExtraido;
  final String anexoExtraido;
  final String docExtraido;
  final String clienteExtraido;
  final TextEditingController primaCtrl;
  final TextEditingController abonoCtrl;
  final TextEditingController porcComCtrl;
  final TextEditingController vlrComCtrl;
  final TextEditingController porcComAdCtrl;
  final TextEditingController vlrComAdCtrl;
  final TextEditingController facturaCtrl;
  DateTime? fechaPago;

  _LineaRevision({
    required this.incluir,
    required this.poliza,
    required this.match,
    required this.comisionCalculada,
    required this.nroExtraido,
    required this.anexoExtraido,
    required this.docExtraido,
    required this.clienteExtraido,
    required this.primaCtrl,
    required this.abonoCtrl,
    required this.porcComCtrl,
    required this.vlrComCtrl,
    required this.porcComAdCtrl,
    required this.vlrComAdCtrl,
    required this.facturaCtrl,
    required this.fechaPago,
  });

  num? get abono => parseNumCO(abonoCtrl.text);
  bool get sinValor => (abono ?? 0) == 0;
  bool get lista => !manual && match.seIncluyeSolo && duplicado == null && !sinValor;

  void dispose() {
    for (final c in [
      primaCtrl, abonoCtrl, porcComCtrl, vlrComCtrl,
      porcComAdCtrl, vlrComAdCtrl, facturaCtrl,
    ]) {
      c.dispose();
    }
  }
}

/// Pantalla de revisión de la importación masiva de un reporte de
/// comisiones: matchea cada línea extraída contra una póliza real y deja
/// todo editable antes de crear los abonos. Nunca guarda solo, y solo
/// deja tildadas de entrada las líneas con coincidencia exacta.
class PaginaRevisionReportePago extends StatefulWidget {
  final int idReporte;
  final List<Map<String, dynamic>> lineas;

  /// Aseguradora del reporte — descarta pólizas de otra aseguradora que
  /// casualmente tengan el mismo número.
  final int? aseguradoraId;

  const PaginaRevisionReportePago({
    super.key,
    required this.idReporte,
    required this.lineas,
    this.aseguradoraId,
  });

  @override
  State<PaginaRevisionReportePago> createState() =>
      _PaginaRevisionReportePagoState();
}

class _PaginaRevisionReportePagoState
    extends State<PaginaRevisionReportePago> {
  final _repoPolizas = RepositorioPolizas();
  final _repoPagos = RepositorioPagos();
  final _repoCat = RepositorioCatalogos();
  final _df = DateFormat('dd/MM/yyyy');

  bool _cargando = true;
  bool _guardando = false;
  bool _creoAlgo = false;
  final List<_LineaRevision> _filas = [];
  final Map<int, List<AbonoPoliza>> _abonosPorPoliza = {};

  /// Abonos que el reporte ya tenía antes de esta importación.
  int _abonosPrevios = 0;

  @override
  void initState() {
    super.initState();
    _matchearTodas();
  }

  @override
  void dispose() {
    for (final f in _filas) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _matchearTodas() async {
    try {
      _abonosPrevios = (await _repoPagos.listarAbonosPorReporte(widget.idReporte)).length;
    } catch (_) {}

    // Las líneas de un mismo cliente o número comparten consultas.
    final cacheCliente = <String, Future<List<Poliza>>>{};
    final cacheNumero = <String, Future<List<Poliza>>>{};
    final resultados = await Future.wait(widget.lineas.map((linea) {
      final nro = (linea['nro_poliza'] as String?)?.trim() ?? '';
      final anexo = linea['anexo']?.toString().trim() ?? '';
      final doc = (linea['doc_cliente'] as String?)?.trim() ?? '';
      return _resolver(nro, anexo, doc, linea['vlrprima_poliza'] as num?, cacheCliente, cacheNumero);
    }));

    for (var i = 0; i < widget.lineas.length; i++) {
      final linea = widget.lineas[i];
      final match = resultados[i];
      final poliza = match.poliza;

      final primaLinea = linea['vlrprima_poliza'] as num?;
      // El abono sale SOLO del reporte. Si no lo trae, la línea queda sin
      // valor (antes se llenaba con la prima completa de la póliza y se
      // registraba un pago que nadie reportó).
      final abono = linea['vlrabono_prima'] as num? ?? primaLinea;
      final porcCom = linea['porccomision'] as num? ?? poliza?.porccomPoliza;
      var vlrCom = linea['vlrcomision'] as num?;
      var comisionCalculada = false;
      if (vlrCom == null && abono != null && porcCom != null) {
        vlrCom = (abono * porcCom / 100 * 100).round() / 100;
        comisionCalculada = true;
      }

      _filas.add(_LineaRevision(
        incluir: match.seIncluyeSolo && (abono ?? 0) != 0,
        poliza: poliza,
        match: match,
        comisionCalculada: comisionCalculada,
        nroExtraido: (linea['nro_poliza'] as String?)?.trim() ?? '',
        anexoExtraido: linea['anexo']?.toString().trim() ?? '',
        docExtraido: (linea['doc_cliente'] as String?)?.trim() ?? '',
        clienteExtraido: (linea['nombre_cliente'] as String?)?.trim() ?? '',
        primaCtrl: TextEditingController(text: formatearNumCO(primaLinea ?? poliza?.primaPoliza)),
        abonoCtrl: TextEditingController(text: formatearNumCO(abono)),
        porcComCtrl: TextEditingController(text: formatearNumCO(porcCom, maxDecimales: 5)),
        vlrComCtrl: TextEditingController(text: formatearNumCO(vlrCom)),
        porcComAdCtrl: TextEditingController(text: formatearNumCO(linea['porccomad'] as num?, maxDecimales: 5)),
        vlrComAdCtrl: TextEditingController(text: formatearNumCO(linea['vlrcomad'] as num?)),
        facturaCtrl: TextEditingController(text: (linea['num_factura'] as String?)?.trim() ?? ''),
        fechaPago: _parseFechaISO(linea['fecha_pago']),
      ));
    }

    for (final f in _filas) {
      await _verificarDuplicado(f);
    }
    if (mounted) setState(() => _cargando = false);
  }

  DateTime? _parseFechaISO(dynamic v) {
    if (v is! String || v.trim().isEmpty) return null;
    try {
      final d = DateTime.parse(v.trim());
      return DateTime(d.year, d.month, d.day);
    } catch (_) {
      return null;
    }
  }

  /// Trae de la base las pólizas que podrían corresponder (por número y por
  /// documento del cliente) y deja que [resolverMatch] decida con precisión.
  Future<ResultadoMatch> _resolver(
    String nro,
    String anexo,
    String doc,
    num? prima,
    Map<String, Future<List<Poliza>>> cacheCliente,
    Map<String, Future<List<Poliza>>> cacheNumero,
  ) async {
    var porNumero = <Poliza>[];
    var delCliente = <Poliza>[];
    try {
      final busqueda = normalizarDoc(nro).replaceFirst(RegExp(r'^0+'), '');
      if (busqueda.isNotEmpty) {
        porNumero = await (cacheNumero[busqueda] ??= _repoPolizas.listarPorNroContiene(busqueda));
      }
      final docNorm = normalizarDoc(doc);
      if (docNorm.isNotEmpty) {
        delCliente = await (cacheCliente[docNorm] ??= _polizasDelDocumento(docNorm));
      }
    } catch (e) {
      return ResultadoMatch(EstadoMatch.noEncontrada,
          motivo: 'No se pudo consultar la base. Asígnela a mano o reintente la importación.');
    }
    if (nro.isEmpty) {
      return ResultadoMatch(EstadoMatch.noEncontrada,
          candidatos: delCliente,
          motivo: 'Esta línea del reporte no trae número de póliza.');
    }
    return resolverMatch(
      nucleo: nro,
      anexo: anexo.isEmpty ? null : anexo,
      docCliente: doc,
      aseguradoraId: widget.aseguradoraId,
      primaLinea: prima,
      candidatos: [...porNumero, ...delCliente],
      polizasDelCliente: delCliente,
    );
  }

  Future<List<Poliza>> _polizasDelDocumento(String docNorm) async {
    final cliente = await _repoCat.buscarClientePorDocExacto(docNorm);
    if (cliente == null) return [];
    return _repoPolizas.listarPorCliente(cliente.id);
  }

  /// Marca la línea si ya existe en la base un abono igual (misma póliza,
  /// mismo valor y misma factura — o misma fecha si no hay factura). Evita
  /// cargar dos veces el mismo pago si se importa el reporte de nuevo.
  ///
  /// No compara contra otras líneas del mismo reporte: ahí líneas con igual
  /// póliza, valor y transacción son movimientos distintos (ej. Mundial:
  /// emisión +, reversión −, re-emisión + con distinto certificado).
  Future<void> _verificarDuplicado(_LineaRevision f, {bool ajustarIncluir = true}) async {
    f.duplicado = null;
    final p = f.poliza;
    if (p == null) return;
    final abono = f.abono ?? 0;
    final factura = _normalizarFactura(f.facturaCtrl.text);

    bool igual(num valor, String? fac, DateTime? fecha) {
      if ((valor - abono).abs() >= 0.01) return false;
      if (factura.isNotEmpty) return _normalizarFactura(fac) == factura;
      return f.fechaPago != null && fecha != null && _mismoDia(f.fechaPago!, fecha);
    }

    try {
      final existentes =
          _abonosPorPoliza[p.id] ??= await _repoPagos.listarAbonosPorPoliza(p.id);
      for (final a in existentes) {
        if (igual(a.vlrabonoprima, a.numFactura, a.fechaPago)) {
          f.duplicado = 'Ya existe un abono igual para esta póliza '
              '(factura ${a.numFactura ?? '—'}'
              '${a.fechaPago != null ? ', ${_df.format(a.fechaPago!)}' : ''}). '
              'Parece un reporte ya cargado.';
          break;
        }
      }
    } catch (_) {}
    if (f.duplicado != null && ajustarIncluir) f.incluir = false;
  }

  Future<void> _asignar(_LineaRevision f, Poliza? p) async {
    setState(() {
      f.poliza = p;
      f.manual = true;
      f.incluir = p != null && !f.sinValor;
    });
    await _verificarDuplicado(f);
    if (mounted) setState(() {});
  }

  /// Al editar abono, % o factura: recalcula la comisión si era calculada y
  /// vuelve a revisar si quedó igual a un abono ya cargado.
  Future<void> _alEditarValores(_LineaRevision f) async {
    if (f.comisionCalculada) {
      final abono = f.abono;
      final pct = parseNumCO(f.porcComCtrl.text);
      if (abono != null && pct != null) {
        f.vlrComCtrl.text = formatearNumCO((abono * pct / 100 * 100).round() / 100);
      }
    }
    await _verificarDuplicado(f, ajustarIncluir: false);
    if (mounted) setState(() {});
  }

  int get _incluidas => _filas.where((f) => f.incluir).length;

  Future<void> _guardar() async {
    final aGuardar = _filas.where((f) => f.incluir).toList();
    final sinPoliza = aGuardar.where((f) => f.poliza == null).length;
    final sinValor = aGuardar.where((f) => f.sinValor).length;
    if (sinPoliza > 0 || sinValor > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text([
          if (sinPoliza > 0) '$sinPoliza línea(s) incluida(s) sin póliza asignada.',
          if (sinValor > 0) '$sinValor línea(s) incluida(s) sin valor de abono.',
          'Corríjalas o destíldelas.',
        ].join(' ')),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }
    if (aGuardar.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No hay líneas para guardar.'),
      ));
      return;
    }

    setState(() => _guardando = true);
    final guardadas = <_LineaRevision>[];
    for (final f in aGuardar) {
      try {
        f.errorGuardado = null;
        // Lo pagado de la póliza y su paso a COMPLETA los recalcula la base
        // en la misma operación (trigger), no la app.
        await _repoPagos.crearAbono({
          'idrep_pago': widget.idReporte,
          'id_poliza': f.poliza!.id,
          'fecha_pago': f.fechaPago?.toIso8601String().substring(0, 10),
          'vlrprima_poliza': parseNumCO(f.primaCtrl.text) ?? 0,
          'vlrabono_prima': f.abono ?? 0,
          'porccomision': parseNumCO(f.porcComCtrl.text) ?? 0,
          'vlrcomision': parseNumCO(f.vlrComCtrl.text) ?? 0,
          'porccomad': parseNumCO(f.porcComAdCtrl.text) ?? 0,
          'vlrcomad': parseNumCO(f.vlrComAdCtrl.text) ?? 0,
          'num_factura': f.facturaCtrl.text.trim().isEmpty ? null : f.facturaCtrl.text.trim(),
          'estado_pago': 'I',
        });
        guardadas.add(f);
      } catch (e) {
        f.errorGuardado = mensajeAmigable(e, accion: 'No se guardó');
      }
    }

    if (guardadas.isNotEmpty) {
      _creoAlgo = true;
      await _repoPolizas.refrescarEnCache(guardadas.map((f) => f.poliza!.id));
    }
    if (!mounted) return;

    final fallidas = aGuardar.length - guardadas.length;
    setState(() {
      _guardando = false;
      // Las guardadas salen de la lista: si algo falló, quedan solo las
      // pendientes para corregir y reintentar (antes se cerraba la
      // pantalla y esas líneas se perdían).
      for (final f in guardadas) {
        _filas.remove(f);
        f.dispose();
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(fallidas == 0
          ? 'Se crearon ${guardadas.length} abono(s).'
          : 'Se crearon ${guardadas.length} abono(s). $fallidas no se pudieron guardar: '
              'siguen en la lista para reintentar.'),
      backgroundColor: fallidas == 0 ? null : AppTheme.warning,
    ));
    if (fallidas == 0) Navigator.pop(context, _creoAlgo);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final listas = _filas.where((f) => f.lista).length;
    final sinPoliza = _filas.where((f) => f.poliza == null).length;
    final porRevisar = _filas.length - listas - sinPoliza;
    final incluidas = _filas.where((f) => f.incluir);
    final sumaAbonos = sumarDinero(incluidas.map((f) => f.abono ?? 0));
    final sumaComision = sumarDinero(incluidas.map(
        (f) => (parseNumCO(f.vlrComCtrl.text) ?? 0) + (parseNumCO(f.vlrComAdCtrl.text) ?? 0)));

    return PopScope(
      canPop: !_guardando,
      onPopInvokedWithResult: (didPop, _) {},
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => Navigator.pop(context, _creoAlgo)),
          title: Text('Revisar importación (${_filas.length} línea(s))'),
          actions: [
            if (_guardando)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              TextButton.icon(
                onPressed: _cargando ? null : _guardar,
                icon: const Icon(Icons.save_outlined),
                label: Text('Guardar $_incluidas abono(s)'),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : AppLayout.centered(ListView(
                padding: AppLayout.pagePadding,
                children: [
                  if (_abonosPrevios > 0)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.warningContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Este reporte ya tiene $_abonosPrevios abono(s) cargados. Si ya había '
                        'importado este archivo, guardar de nuevo duplicaría los pagos.',
                        style: const TextStyle(color: AppTheme.onWarningContainer, fontSize: 13),
                      ),
                    ),
                  Text(
                    'Revise cada línea antes de guardar. Solo quedan tildadas de entrada las que '
                    'coinciden exacto (número de póliza + anexo). Las demás necesitan que elija '
                    'la póliza o las deje por fuera.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    _chip('$listas coinciden exacto', cs.secondaryContainer, cs.onSecondaryContainer),
                    _chip('$porRevisar por revisar', AppTheme.warningContainer, AppTheme.onWarningContainer),
                    _chip('$sinPoliza sin póliza', cs.errorContainer, cs.onErrorContainer),
                    _chip('Incluidas: abonos \$ ${Fmt.money(sumaAbonos, dec: 2)} · '
                        'comisión \$ ${Fmt.money(sumaComision, dec: 2)}',
                        cs.surfaceContainerHighest, cs.onSurface),
                  ]),
                  const SizedBox(height: 16),
                  for (int i = 0; i < _filas.length; i++) ...[
                    _filaCard(_filas[i]),
                    const SizedBox(height: 10),
                  ],
                ],
              )),
      ),
    );
  }

  Widget _chip(String texto, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
        child: Text(texto, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
      );

  (String, Color, Color) _estadoVisual(_LineaRevision f) {
    final cs = Theme.of(context).colorScheme;
    if (f.manual) {
      return f.poliza == null
          ? ('Sin póliza', cs.errorContainer, cs.onErrorContainer)
          : ('Asignada a mano', cs.primaryContainer, cs.onPrimaryContainer);
    }
    return switch (f.match.estado) {
      EstadoMatch.exacta => ('Coincide exacto', cs.secondaryContainer, cs.onSecondaryContainer),
      EstadoMatch.unicaSinAnexo =>
        ('Coincide (reporte sin anexo)', cs.secondaryContainer, cs.onSecondaryContainer),
      EstadoMatch.revisar => ('Revisar', AppTheme.warningContainer, AppTheme.onWarningContainer),
      EstadoMatch.ambigua => ('Varias opciones', AppTheme.warningContainer, AppTheme.onWarningContainer),
      EstadoMatch.anexoNoRegistrado =>
        ('Anexo no registrado', AppTheme.warningContainer, AppTheme.onWarningContainer),
      EstadoMatch.noEncontrada => ('No encontrada', cs.errorContainer, cs.onErrorContainer),
    };
  }

  Widget _filaCard(_LineaRevision f) {
    final cs = Theme.of(context).colorScheme;
    final (etiqueta, bg, fg) = _estadoVisual(f);
    final mostrarMotivo = !f.manual && f.match.motivo.isNotEmpty && !f.match.seIncluyeSolo;
    final opciones = f.match.candidatos;

    final extraido = [
      'Póliza ${f.nroExtraido.isEmpty ? '—' : f.nroExtraido}',
      'anexo ${f.anexoExtraido.isEmpty ? '—' : f.anexoExtraido}',
      if (f.docExtraido.isNotEmpty) 'doc ${f.docExtraido}',
      if (f.clienteExtraido.isNotEmpty) f.clienteExtraido,
    ].join('  ·  ');

    final avisos = [
      if (f.errorGuardado != null) f.errorGuardado!,
      if (f.duplicado != null) f.duplicado!,
      if (f.sinValor) 'El reporte no trae el valor abonado de esta línea: escríbalo o déjela por fuera.',
      if (mostrarMotivo) f.match.motivo,
    ];
    final avisoRojo = f.errorGuardado != null || f.duplicado != null || f.sinValor;

    return Card(
      color: f.incluir ? null : cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Checkbox(
                value: f.incluir,
                onChanged: (v) => setState(() => f.incluir = v ?? false),
              ),
              _chip(etiqueta, bg, fg),
              if (f.duplicado != null) ...[
                const SizedBox(width: 6),
                _chip('Posible duplicado', cs.errorContainer, cs.onErrorContainer),
              ],
              if (f.comisionCalculada) ...[
                const SizedBox(width: 6),
                _chip('Comisión calculada', cs.surfaceContainerHighest, cs.onSurfaceVariant),
              ],
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Reporte: $extraido',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            if (avisos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 48, top: 2, bottom: 6),
                child: Text(
                  avisos.join('\n'),
                  style: TextStyle(
                    fontSize: 12,
                    color: avisoRojo ? cs.error : AppTheme.onWarningContainer,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            if (f.poliza != null)
              Padding(
                padding: const EdgeInsets.only(left: 48, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Póliza ${f.poliza!.nroPoliza ?? f.poliza!.id} — ${f.poliza!.nombreCliente ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    Text(
                      '${f.poliza!.nombreAseg ?? '—'} · ${f.poliza!.nombreRamo ?? '—'} · '
                      '${f.poliza!.nombreProd ?? '—'}  ·  Prima póliza: \$ ${Fmt.money(f.poliza!.primaPoliza)}',
                      style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            if (opciones.isNotEmpty && !f.match.seIncluyeSolo)
              Padding(
                padding: const EdgeInsets.only(left: 48, bottom: 8),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final c in opciones)
                    ChoiceChip(
                      label: Text(
                        '${c.nroPoliza ?? c.id} — ${c.nombreCliente ?? ''} '
                        '(\$ ${Fmt.money(c.primaPoliza)})',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      selected: f.poliza?.id == c.id,
                      onSelected: (_) => _asignar(f, c),
                    ),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 48, bottom: 8),
              child: BuscadorDropdown<Poliza>(
                label: f.poliza == null ? 'Asignar póliza manualmente' : 'Cambiar póliza',
                value: f.poliza,
                items: f.poliza != null ? [f.poliza!] : [],
                itemLabel: (p) => '${p.nroPoliza ?? p.id}  –  ${p.nombreCliente ?? ''}',
                itemsLoader: (q) => _repoPolizas.listar(busqueda: q, limite: 60),
                onChanged: (p) => _asignar(f, p),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Wrap(spacing: 10, runSpacing: 10, children: [
                _campoFecha(f),
                _campo('Prima', f.primaCtrl),
                _campo('Abono', f.abonoCtrl, alCambiar: () => _alEditarValores(f)),
                _campo('% Com.', f.porcComCtrl, decimales: 5, alCambiar: () => _alEditarValores(f)),
                _campo('Vlr Com.', f.vlrComCtrl, alCambiar: () {
                  f.comisionCalculada = false;
                  setState(() {});
                }),
                _campo('% Com. Ad.', f.porcComAdCtrl, decimales: 5),
                _campo('Vlr Com. Ad.', f.vlrComAdCtrl),
                _campo('Factura', f.facturaCtrl, numero: false, alCambiar: () => _alEditarValores(f)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo(
    String label,
    TextEditingController ctrl, {
    bool numero = true,
    int decimales = 2,
    VoidCallback? alCambiar,
  }) {
    return SizedBox(
      width: 140,
      child: TextFormField(
        controller: ctrl,
        keyboardType: numero
            ? const TextInputType.numberWithOptions(signed: true, decimal: true)
            : TextInputType.text,
        inputFormatters: numero ? [NumeroCOInputFormatter(maxDecimales: decimales)] : null,
        onChanged: alCambiar == null ? null : (_) => alCambiar(),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _campoFecha(_LineaRevision f) {
    return SizedBox(
      width: 140,
      child: InkWell(
        onTap: () async {
          final d = await mostrarSelectorFecha(
            context,
            inicial: f.fechaPago,
            primera: DateTime(2000),
            ultima: DateTime(2100),
          );
          if (d != null) {
            f.fechaPago = d;
            await _alEditarValores(f);
          }
        },
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Fecha pago',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          child: Text(
            f.fechaPago != null ? _df.format(f.fechaPago!) : '—',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    );
  }
}
