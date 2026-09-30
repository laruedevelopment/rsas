// ignore_for_file: use_build_context_synchronously

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../datos/abono_poliza.dart';
import '../datos/repositorio_pagos.dart';
import '../utils/filtros_busqueda.dart';
import '../utils/formatters.dart';
import '../utils/numeros_co.dart';
import '../utils/generador_pdf.dart';
import 'theme/app_layout.dart';
import 'theme/app_theme.dart';
import 'widgets/tabla_ancho_completo.dart';
import 'widgets/stat_card.dart';

/// Pantalla de estado de cuenta.
/// Modos:
///   - [PaginaEstadoCuenta.poliza]  → todos los abonos de una póliza
///   - [PaginaEstadoCuenta.reporte] → todos los abonos de un reporte
class PaginaEstadoCuenta extends StatefulWidget {
  final int? idPoliza;
  final int? idReporte;

  const PaginaEstadoCuenta._({this.idPoliza, this.idReporte});

  factory PaginaEstadoCuenta.poliza({required int idPoliza}) =>
      PaginaEstadoCuenta._(idPoliza: idPoliza);

  factory PaginaEstadoCuenta.reporte({required int idReporte}) =>
      PaginaEstadoCuenta._(idReporte: idReporte);

  bool get esModoPoliza => idPoliza != null;

  @override
  State<PaginaEstadoCuenta> createState() => _PaginaEstadoCuentaState();
}

class _PaginaEstadoCuentaState extends State<PaginaEstadoCuenta> {
  final _repo = RepositorioPagos();
  final _df = DateFormat('dd/MM/yyyy');

  bool _cargando = false;
  bool _exportando = false;
  List<AbonoPoliza> _abonos = [];
  ReportePago? _reporte;

  // Buscador de la tabla (solo en el estado de cuenta de un reporte): por
  // código de póliza, número de póliza o cliente.
  final _ctrlFiltro = TextEditingController();

  List<AbonoPoliza> get _abonosFiltrados {
    final q = _ctrlFiltro.text.trim();
    if (q.isEmpty) return _abonos;
    final codigo = int.tryParse(q.replaceFirst('#', ''));
    final norm = normalizarAlfanumerico(q);
    final texto = q.toUpperCase();
    return _abonos
        .where((a) =>
            a.idPoliza == codigo ||
            (norm.isNotEmpty &&
                normalizarAlfanumerico(a.nroPoliza ?? '').contains(norm)) ||
            (a.nombreCliente ?? '').toUpperCase().contains(texto))
        .toList();
  }

  @override
  void dispose() {
    _ctrlFiltro.dispose();
    super.dispose();
  }

  // Totales
  // Los abonos anulados (estado A) no suman, igual que en la base. Suma
  // exacta en centavos (sin error de redondeo de doubles).
  Iterable<AbonoPoliza> get _vigentes =>
      _abonos.where((a) => a.estadoPago != 'A');
  num get _totalAbonado => sumarDinero(_vigentes.map((a) => a.vlrabonoprima));
  num get _totalComision =>
      sumarDinero(_vigentes.map((a) => a.vlrcomision + a.vlrcomad));
  num get _primaPoliza =>
      _abonos.isNotEmpty ? (_abonos.first.primaPoliza ?? 0) : 0;
  num get _saldo => widget.esModoPoliza ? _primaPoliza - _totalAbonado : 0;
  // Póliza en estado ANULADA (A): el saldo pendiente no aplica.
  bool get _polizaAnulada =>
      widget.esModoPoliza &&
      _abonos.isNotEmpty &&
      _abonos.first.estadoPolizaId == 'A';
  // Sin tope en 100%: si se pagó de más, se tiene que ver.
  double get _porcPagado =>
      _primaPoliza > 0 ? (_totalAbonado / _primaPoliza * 100).toDouble() : 0;

  // Encabezado para mostrar
  String get _titulo => widget.esModoPoliza
      ? 'Estado de Cuenta – Póliza'
      : 'Estado de Cuenta – Reporte #${widget.idReporte}';

  String get _subtitulo {
    if (widget.esModoPoliza && _abonos.isNotEmpty) {
      final a = _abonos.first;
      return '${a.nroPoliza ?? ''} · ${a.nombreCliente ?? ''}';
    }
    if (!widget.esModoPoliza && _reporte != null) {
      return '${_reporte!.nombreAseg ?? ''}  |  '
          '${_df.format(_reporte!.fechaRep)}';
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      if (widget.esModoPoliza) {
        _abonos = await _repo.listarAbonosPorPoliza(widget.idPoliza!);
      } else {
        _abonos = await _repo.listarAbonosPorReporte(widget.idReporte!);
        _reporte = await _repo.obtenerReporte(widget.idReporte!);
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al cargar: $e'),
              backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _exportarPdf() async {
    setState(() => _exportando = true);
    try {
      Uint8List bytes;
      if (widget.esModoPoliza) {
        bytes = await GeneradorPdf.estadoCuentaPoliza(
          abonos: _abonos,
          totalAbonado: _totalAbonado,
          totalComision: _totalComision,
          primaPoliza: _primaPoliza,
          saldo: _saldo,
        );
      } else {
        bytes = await GeneradorPdf.estadoCuentaReporte(
          abonos: _abonos,
          reporte: _reporte,
          totalAbonado: _totalAbonado,
          totalComision: _totalComision,
        );
      }
      await GeneradorPdf.descargar(
        bytes: bytes,
        nombre: widget.esModoPoliza
            ? 'estado_cuenta_poliza_${widget.idPoliza}'
            : 'estado_cuenta_reporte_${widget.idReporte}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF generado y descargado')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al generar PDF: $e'),
              backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Future<void> _verFactura(AbonoPoliza abono) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _PaginaFactura(abono: abono)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_titulo),
        actions: [
          if (_exportando)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Descargar PDF',
              onPressed: _abonos.isEmpty ? null : _exportarPdf,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
            onPressed: _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _abonos.isEmpty
              ? AppLayout.centered(Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined,
                          size: 52, color: cs.outlineVariant),
                      const SizedBox(height: 12),
                      Text('Sin abonos registrados',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ))
              : AppLayout.centered(
                  CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: AppLayout.pagePadding,
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            // ── Encabezado informativo ───────────────────────
                            if (_subtitulo.isNotEmpty)
                              Card(
                                color: cs.primaryContainer,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(children: [
                                    Icon(
                                      widget.esModoPoliza
                                          ? Icons.receipt_long_outlined
                                          : Icons.folder_open_outlined,
                                      color: cs.onPrimaryContainer,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _subtitulo,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: cs.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                    if (_polizaAnulada)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppTheme.danger,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: const Text(
                                          'ANULADA',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                  ]),
                                ),
                              ),
                            const SizedBox(height: 12),

                            // ── Info póliza (modo póliza) ────────────────────
                            if (widget.esModoPoliza && _abonos.isNotEmpty)
                              _InfoPolizaCard(abono: _abonos.first, df: _df),

                            // ── Info reporte (modo reporte) ──────────────────
                            if (!widget.esModoPoliza && _reporte != null)
                              _InfoReporteCard(reporte: _reporte!, df: _df),

                            const SizedBox(height: 16),

                            // ── Tarjetas de resumen ──────────────────────────
                            _SeccionTitle(
                                icon: Icons.summarize_outlined,
                                title: 'Resumen de Cuenta'),
                            const SizedBox(height: 10),
                            _ResumenCards(
                              totalAbonado: _totalAbonado,
                              totalComision: _totalComision,
                              primaPoliza:
                                  widget.esModoPoliza ? _primaPoliza : null,
                              saldo: widget.esModoPoliza ? _saldo : null,
                              polizaAnulada: _polizaAnulada,
                              porcPagado:
                                  widget.esModoPoliza ? _porcPagado : null,
                              numAbonos: _abonos.length,
                            ),
                            const SizedBox(height: 20),

                            // ── Historial de abonos ──────────────────────────
                            _SeccionTitle(
                                icon: Icons.history_outlined,
                                title: 'Historial de Pagos'),
                            const SizedBox(height: 10),
                            if (!widget.esModoPoliza) ...[
                              TextField(
                                controller: _ctrlFiltro,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  hintText:
                                      'Buscar por código de póliza, número de póliza o cliente...',
                                  prefixIcon: const Icon(Icons.search),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  helperText: _ctrlFiltro.text.trim().isEmpty
                                      ? null
                                      : 'Mostrando ${_abonosFiltrados.length} de ${_abonos.length} pagos',
                                  suffixIcon: _ctrlFiltro.text.isEmpty
                                      ? null
                                      : IconButton(
                                          icon: const Icon(Icons.clear),
                                          onPressed: () =>
                                              setState(_ctrlFiltro.clear),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            _TablaHistorial(
                              abonos: _abonosFiltrados,
                              df: _df,
                              modoPoliza: widget.esModoPoliza,
                              onVerFactura: _verFactura,
                            ),
                            const SizedBox(height: 40),
                          ]),
                        ),
                      ),
                    ],
                  ),
                  maxWidth: AppLayout.maxTableWidth),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card de info de póliza
// ─────────────────────────────────────────────────────────────────────────────

class _InfoPolizaCard extends StatelessWidget {
  final AbonoPoliza abono;
  final DateFormat df;
  const _InfoPolizaCard({required this.abono, required this.df});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Row2('N° Póliza', abono.nroPoliza ?? '—'),
          _Row2('Aseguradora', abono.nombreAseg ?? '—'),
          _Row2('Ramo', abono.nombreRamo ?? '—'),
          _Row2('Producto', abono.nombreProd ?? '—'),
          _Row2('Bien asegurado', abono.bienAsegurado ?? '—'),
          if (abono.finiPoliza != null && abono.ffinPoliza != null)
            _Row2('Vigencia',
                '${df.format(abono.finiPoliza!)} – ${df.format(abono.ffinPoliza!)}'),
          _Row2('Prima total', '\$ ${Fmt.money(abono.primaPoliza ?? 0)}'),
        ]),
      ),
    );
  }
}

class _InfoReporteCard extends StatelessWidget {
  final ReportePago reporte;
  final DateFormat df;
  const _InfoReporteCard({required this.reporte, required this.df});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Row2('Reporte #', '${reporte.id}'),
          _Row2('Fecha', df.format(reporte.fechaRep)),
          _Row2('Aseguradora', reporte.nombreAseg ?? '—'),
          _Row2('Intermediario', reporte.nombreInterm ?? '—'),
          if (reporte.finiRep != null && reporte.ffinRep != null)
            _Row2('Período',
                '${df.format(reporte.finiRep!)} – ${df.format(reporte.ffinRep!)}'),
          _Row2('Estado', labelEstadoPago(reporte.estadoRep)),
        ]),
      ),
    );
  }
}

class _Row2 extends StatelessWidget {
  final String label;
  final String value;
  const _Row2(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
          width: 130,
          child: Text('$label:',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tarjetas de resumen
// ─────────────────────────────────────────────────────────────────────────────

class _ResumenCards extends StatelessWidget {
  final num totalAbonado;
  final num totalComision;
  final num? primaPoliza;
  final num? saldo;
  final bool polizaAnulada;
  final double? porcPagado;
  final int numAbonos;

  const _ResumenCards({
    required this.totalAbonado,
    required this.totalComision,
    this.primaPoliza,
    this.saldo,
    this.polizaAnulada = false,
    this.porcPagado,
    required this.numAbonos,
  });

  @override
  Widget build(BuildContext context) {
    final items = <(String, String, IconData, Color)>[
      if (primaPoliza != null)
        (
          'Prima total',
          '\$ ${Fmt.money(primaPoliza)}',
          Icons.monetization_on_outlined,
          AppTheme.navy
        ),
      (
        'Total abonado',
        '\$ ${Fmt.money(totalAbonado)}',
        Icons.payments_outlined,
        AppTheme.green
      ),
      if (saldo != null)
        polizaAnulada
            ? (
                'Saldo pendiente',
                '—',
                Icons.pending_actions_outlined,
                AppTheme.inkSoft
              )
            : (
                saldo! < 0 ? 'Saldo a favor' : 'Saldo pendiente',
                '\$ ${Fmt.money(saldo!.abs())}',
                Icons.pending_actions_outlined,
                saldo! > 0 ? AppTheme.warning : AppTheme.green
              ),
      (
        'Total comisión',
        '\$ ${Fmt.money(totalComision)}',
        Icons.percent,
        const Color(0xFF6A1B9A)
      ),
      if (porcPagado != null)
        (
          '% Pagado',
          '${porcPagado!.toStringAsFixed(1)}%',
          Icons.pie_chart_outline,
          porcPagado! >= 100 ? AppTheme.green : AppTheme.warning
        ),
      (
        'Número de pagos',
        '$numAbonos',
        Icons.receipt_long_outlined,
        const Color(0xFF00838F)
      ),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items.map((t) {
        final (label, value, icon, color) = t;
        return StatCard(label: label, value: value, icon: icon, color: color);
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tabla de historial de pagos
// ─────────────────────────────────────────────────────────────────────────────

class _TablaHistorial extends StatelessWidget {
  final List<AbonoPoliza> abonos;
  final DateFormat df;
  final bool modoPoliza;
  final void Function(AbonoPoliza) onVerFactura;

  const _TablaHistorial({
    required this.abonos,
    required this.df,
    required this.modoPoliza,
    required this.onVerFactura,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hScroll = ScrollController();

    // Totales para el pie
    final vigentes = abonos.where((a) => a.estadoPago != 'A');
    final totPrima = sumarDinero(vigentes.map((a) => a.vlrabonoprima));
    final totCom = sumarDinero(vigentes.map((a) => a.vlrcomision));
    final totComAd = sumarDinero(vigentes.map((a) => a.vlrcomad));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        controller: hScroll,
        thumbVisibility: true,
        trackVisibility: true,
        child: TablaAnchoCompleto(
          controller: hScroll,
          padding: const EdgeInsets.only(bottom: 10),
          child: DataTable(
            headingRowColor:
                WidgetStateProperty.all(cs.surfaceContainerHighest),
            dataRowMinHeight: 48,
            dataRowMaxHeight: 68,
            columnSpacing: 12,
            columns: [
              const DataColumn(label: Text('Fecha Pago')),
              if (!modoPoliza) const DataColumn(label: Text('N° Póliza')),
              if (!modoPoliza) const DataColumn(label: Text('Cliente')),
              if (modoPoliza) const DataColumn(label: Text('Reporte #')),
              const DataColumn(label: Text('Ramo / Producto')),
              const DataColumn(label: Text('Bien Asegurado')),
              const DataColumn(label: Text('Abono'), numeric: true),
              const DataColumn(label: Text('% Com'), numeric: true),
              const DataColumn(label: Text('Vlr Com'), numeric: true),
              const DataColumn(label: Text('Com Adic'), numeric: true),
              const DataColumn(label: Text('N° Factura')),
              const DataColumn(label: Text('Estado')),
              const DataColumn(label: Text('Factura')),
            ],
            rows: [
              ...abonos.map((a) => DataRow(cells: [
                    DataCell(Text(
                      a.fechaPago != null ? df.format(a.fechaPago!) : '—',
                      style: const TextStyle(fontSize: 12),
                    )),
                    if (!modoPoliza)
                      DataCell(Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CeldaAnchoFijo(a.nroPoliza ?? '—',
                              ancho: 200,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12)),
                          Text('Cód. ${a.idPoliza}',
                              style: TextStyle(
                                  fontSize: 10, color: AppTheme.inkSoft)),
                        ],
                      )),
                    if (!modoPoliza)
                      DataCell(CeldaAnchoFijo(a.nombreCliente ?? '—',
                          ancho: 300, style: const TextStyle(fontSize: 12))),
                    if (modoPoliza)
                      DataCell(Text(
                        a.idrepPago != null ? '#${a.idrepPago}' : '—',
                        style: const TextStyle(fontSize: 12),
                      )),
                    DataCell(Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.nombreRamo ?? '—',
                            style: const TextStyle(fontSize: 12)),
                        if (a.nombreProd != null)
                          Text(a.nombreProd!,
                              style: TextStyle(
                                  fontSize: 10, color: AppTheme.inkSoft)),
                      ],
                    )),
                    DataCell(SizedBox(
                      width: 130,
                      child: Text(a.bienAsegurado ?? '—',
                          style: const TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis),
                    )),
                    DataCell(Text('\$ ${Fmt.money(a.vlrabonoprima)}',
                        style: TextStyle(
                            fontFamily: AppTheme.monoFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.bold))),
                    DataCell(Text(Fmt.percent(a.porccomision, dec: 1))),
                    DataCell(Text('\$ ${Fmt.money(a.vlrcomision)}',
                        style: TextStyle(
                            fontFamily: AppTheme.monoFamily, fontSize: 12))),
                    DataCell(Text('\$ ${Fmt.money(a.vlrcomad)}',
                        style: TextStyle(
                            fontFamily: AppTheme.monoFamily, fontSize: 12))),
                    DataCell(Text(a.numFactura ?? '—',
                        style: const TextStyle(fontSize: 12))),
                    DataCell(_ChipEstado(a.estadoPago)),
                    DataCell(IconButton(
                      icon: const Icon(Icons.receipt_outlined, size: 18),
                      tooltip: 'Ver / descargar factura',
                      onPressed: () => onVerFactura(a),
                    )),
                  ])),
              // Fila de totales
              DataRow(
                color: WidgetStateProperty.all(cs.surfaceContainerHighest),
                cells: [
                  const DataCell(Text('TOTALES',
                      style: TextStyle(fontWeight: FontWeight.bold))),
                  if (!modoPoliza) const DataCell(Text('')),
                  if (!modoPoliza) const DataCell(Text('')),
                  if (modoPoliza) const DataCell(Text('')),
                  const DataCell(Text('')),
                  const DataCell(Text('')),
                  DataCell(Text('\$ ${Fmt.money(totPrima)}',
                      style: TextStyle(
                          fontFamily: AppTheme.monoFamily,
                          fontWeight: FontWeight.bold))),
                  const DataCell(Text('')),
                  DataCell(Text('\$ ${Fmt.money(totCom)}',
                      style: TextStyle(
                          fontFamily: AppTheme.monoFamily,
                          fontWeight: FontWeight.bold))),
                  DataCell(Text('\$ ${Fmt.money(totComAd)}',
                      style: TextStyle(
                          fontFamily: AppTheme.monoFamily,
                          fontWeight: FontWeight.bold))),
                  const DataCell(Text('')),
                  const DataCell(Text('')),
                  const DataCell(Text('')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chip de estado
// ─────────────────────────────────────────────────────────────────────────────

class _ChipEstado extends StatelessWidget {
  final String estado;
  const _ChipEstado(this.estado);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = switch (estado) {
      'C' => (cs.secondaryContainer, cs.onSecondaryContainer),
      'R' => (cs.primaryContainer, cs.onPrimaryContainer),
      'I' => (AppTheme.warningContainer, AppTheme.onWarningContainer),
      'V' => (cs.errorContainer, cs.onErrorContainer),
      _ => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(labelEstadoPago(estado),
          style:
              TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
    );
  }
}

class _SeccionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SeccionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(icon, size: 18, color: cs.primary),
      const SizedBox(width: 8),
      Text(title,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.bold, color: cs.primary)),
      const SizedBox(width: 8),
      Expanded(child: Divider(color: cs.primary.withOpacity(0.3))),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pantalla de Factura individual
// ─────────────────────────────────────────────────────────────────────────────

class _PaginaFactura extends StatefulWidget {
  final AbonoPoliza abono;
  const _PaginaFactura({required this.abono});

  @override
  State<_PaginaFactura> createState() => _PaginaFacturaState();
}

class _PaginaFacturaState extends State<_PaginaFactura> {
  bool _exportando = false;
  final _df = DateFormat('dd/MM/yyyy');

  Future<void> _descargarPdf() async {
    setState(() => _exportando = true);
    try {
      final bytes = await GeneradorPdf.factura(abono: widget.abono);
      await GeneradorPdf.descargar(
        bytes: bytes,
        nombre:
            'factura_${(widget.abono.numFactura ?? '${widget.abono.id}').replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '_')}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Factura descargada como PDF')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = widget.abono;
    final totalCom = a.vlrcomision + a.vlrcomad;

    return Scaffold(
      appBar: AppBar(
        title: Text('Factura ${a.numFactura ?? '#${a.id}'}'),
        actions: [
          if (_exportando)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            FilledButton.icon(
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Descargar PDF'),
              onPressed: _descargarPdf,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Encabezado ────────────────────────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Rueda Serrano Asesores de Seguros',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: cs.primary)),
                              Text('Asesoría y Gestión de Seguros',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('COMPROBANTE DE PAGO',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: cs.onPrimaryContainer)),
                              if (a.numFactura != null)
                                Text('N° ${a.numFactura}',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: cs.onPrimaryContainer)),
                              Text(
                                a.fechaPago != null
                                    ? _df.format(a.fechaPago!)
                                    : '—',
                                style: TextStyle(
                                    fontSize: 12, color: cs.onPrimaryContainer),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),

                    // ── Datos cliente + póliza ────────────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _SeccionFactura(
                            titulo: 'DATOS DEL CLIENTE',
                            filas: [
                              ('Nombre', a.nombreCliente ?? '—'),
                              if (a.tipodocCliente != null ||
                                  a.docCliente != null)
                                (
                                  'Documento',
                                  '${a.tipodocCliente ?? ''} ${Fmt.doc(a.docCliente)}'
                                ),
                              if (a.telCliente != null)
                                ('Teléfono', a.telCliente!),
                              if (a.correoCliente != null)
                                ('Correo', a.correoCliente!),
                              if (a.dirCliente != null)
                                ('Dirección', a.dirCliente!),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _SeccionFactura(
                            titulo: 'DATOS DE LA PÓLIZA',
                            filas: [
                              ('N° Póliza', a.nroPoliza ?? '—'),
                              ('Código', '${a.idPoliza}'),
                              ('Aseguradora', a.nombreAseg ?? '—'),
                              ('Ramo', a.nombreRamo ?? '—'),
                              ('Producto', a.nombreProd ?? '—'),
                              ('Bien asegurado', a.bienAsegurado ?? '—'),
                              if (a.finiPoliza != null && a.ffinPoliza != null)
                                (
                                  'Vigencia',
                                  '${_df.format(a.finiPoliza!)} – ${_df.format(a.ffinPoliza!)}'
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ── Tabla de detalle del pago ─────────────────────────
                    Text('DETALLE DEL PAGO',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: cs.primary)),
                    const SizedBox(height: 8),
                    Table(
                      columnWidths: const {
                        0: FlexColumnWidth(3),
                        1: FlexColumnWidth(2),
                        2: FlexColumnWidth(2),
                      },
                      border: TableBorder.all(
                          color: AppTheme.outlineVariant, width: 1),
                      children: [
                        _filaTabla(
                          ['Concepto', 'Vlr Prima Póliza', 'Abono / Comisión'],
                          isHeader: true,
                          cs: cs,
                        ),
                        _filaTabla([
                          'Prima de póliza',
                          '\$ ${Fmt.money(a.vlrprimaPoliza)}',
                          '\$ ${Fmt.money(a.vlrabonoprima)}',
                        ], cs: cs),
                        if (a.porccomision > 0)
                          _filaTabla([
                            'Comisión (${Fmt.percent(a.porccomision, dec: 1)})',
                            '',
                            '\$ ${Fmt.money(a.vlrcomision)}',
                          ], cs: cs),
                        if (a.porccomad > 0)
                          _filaTabla([
                            'Com. Adicional (${Fmt.percent(a.porccomad, dec: 1)})',
                            '',
                            '\$ ${Fmt.money(a.vlrcomad)}',
                          ], cs: cs),
                        _filaTabla([
                          'TOTAL COMISIÓN',
                          '',
                          '\$ ${Fmt.money(totalCom)}',
                        ], isTotals: true, cs: cs),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Estado + reporte + obs ────────────────────────────
                    Row(children: [
                      _PillInfo(
                        label: 'Estado',
                        value: labelEstadoPago(a.estadoPago),
                        color: _colorEstado(a.estadoPago),
                      ),
                      const SizedBox(width: 12),
                      if (a.idrepPago != null)
                        _PillInfo(
                            label: 'Reporte',
                            value: '#${a.idrepPago}',
                            color: cs.secondary),
                    ]),
                    if (a.obsPago != null && a.obsPago!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Observaciones:',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(a.obsPago!,
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 8),
                    if (a.apodoUsuario != null)
                      Text(
                        'Registrado por: ${a.apodoUsuario} '
                        '– ${a.fcreado != null ? _df.format(a.fcreado!) : ''}',
                        style:
                            TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TableRow _filaTabla(List<String> celdas,
      {bool isHeader = false, bool isTotals = false, required ColorScheme cs}) {
    return TableRow(
      decoration: BoxDecoration(
        color: isHeader
            ? cs.primaryContainer
            : isTotals
                ? cs.surfaceContainerHighest
                : null,
      ),
      children: celdas
          .map((c) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(c,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: (isHeader || isTotals)
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontFamily: (!isHeader && c.startsWith('\$'))
                            ? AppTheme.monoFamily
                            : null)),
              ))
          .toList(),
    );
  }

  Color _colorEstado(String e) {
    return switch (e) {
      'C' => AppTheme.green,
      'R' => AppTheme.navy,
      'I' => AppTheme.warning,
      'V' => AppTheme.danger,
      _ => AppTheme.inkSoft,
    };
  }
}

class _SeccionFactura extends StatelessWidget {
  final String titulo;
  final List<(String, String)> filas;
  const _SeccionFactura({required this.titulo, required this.filas});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6), topRight: Radius.circular(6)),
        ),
        child: Text(titulo,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: cs.onPrimaryContainer)),
      ),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.outlineVariant),
          borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(6), bottomRight: Radius.circular(6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: filas
              .map((f) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      SizedBox(
                        width: 90,
                        child: Text('${f.$1}:',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                          child: Text(f.$2,
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis)),
                    ]),
                  ))
              .toList(),
        ),
      ),
    ]);
  }
}

class _PillInfo extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _PillInfo(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label: ',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        Text(value,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }
}
