// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../datos/abono_poliza.dart';
import '../datos/catalogos.dart';
import '../datos/poliza.dart';
import '../datos/repositorio_catalogos.dart';
import '../datos/repositorio_ia.dart';
import '../datos/repositorio_pagos.dart';
import '../datos/repositorio_polizas.dart';
import '../datos/sesion.dart';
import '../utils/formatters.dart';
import '../utils/numeros_co.dart';
import 'theme/app_layout.dart';
import 'theme/app_theme.dart';
import 'widgets/tabla_ancho_completo.dart';
import 'widgets/stat_card.dart';
import 'pagina_estado_cuenta.dart';
import 'pagina_revision_reporte_pago.dart';
import 'widgets/buscador_dropdown.dart';
import 'widgets/selector_fecha.dart';

extension _FirstOrNull<E> on Iterable<E> {
  E? firstOrNull(bool Function(E) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FormularioReportePago
// ─────────────────────────────────────────────────────────────────────────────

class FormularioReportePago extends StatefulWidget {
  final ReportePago? reporte;
  const FormularioReportePago({super.key, this.reporte});

  @override
  State<FormularioReportePago> createState() => _FormularioReporteState();
}

class _FormularioReporteState extends State<FormularioReportePago> {
  final _formKey = GlobalKey<FormState>();
  final _repoPagos = RepositorioPagos();
  final _repoCatalogos = RepositorioCatalogos();
  final _repoIA = RepositorioIA();
  final _df = DateFormat('dd/MM/yyyy');

  bool _guardando = false;
  bool _cargandoCatalogos = false;
  bool _cargandoAbonos = false;
  bool _importando = false;
  List<Map<String, dynamic>> _lineasPendientes = [];

  // Aprendizaje de correcciones IA para el Intermediario (ver
  // ia_aprendizaje_intermediario_reporte): el texto de cabecera del
  // documento casi nunca coincide en forma con el nombre guardado, así que
  // si el usuario termina eligiendo un Intermediario distinto (o eligiendo
  // uno cuando la IA no sugirió ninguno) para este mismo texto/aseguradora,
  // se guarda la corrección para la próxima vez.
  int? _intermSugeridoPorIA;
  String? _textoIntermParaAprendizaje;
  int? _asegIdEnSugerenciaInterm;

  List<AbonoPoliza> _abonos = [];
  List<Aseguradora> _aseguradoras = [];
  List<Intermediario> _intermediarios = [];

  // Campos del formulario
  late DateTime _fechaRep;
  DateTime? _finiRep;
  DateTime? _ffinRep;
  String _estadoRep = 'I';
  Aseguradora? _aseguradora;
  Intermediario? _intermediario;

  final _ctrlPrimaManual = TextEditingController();
  final _ctrlComManual = TextEditingController();
  final _ctrlObs = TextEditingController();

  bool get _esNuevo => widget.reporte == null;
  int? get _idReporte => widget.reporte?.id;

  // Totales calculados de los abonos cargados
  // Anulados (estado A) no suman, igual que en la base.
  Iterable<AbonoPoliza> get _abonosVigentes =>
      _abonos.where((a) => a.estadoPago != 'A');
  num get _sumaPrima =>
      sumarDinero(_abonosVigentes.map((a) => a.vlrabonoprima));
  num get _sumaCom =>
      sumarDinero(_abonosVigentes.map((a) => a.vlrcomision + a.vlrcomad));

  @override
  void initState() {
    super.initState();
    final r = widget.reporte;
    _fechaRep = r?.fechaRep ?? DateTime.now();
    _finiRep = r?.finiRep;
    _ffinRep = r?.ffinRep;
    _estadoRep = r?.estadoRep ?? 'I';
    _ctrlPrimaManual.text = r != null ? Fmt.money(r.vlrprimaRep) : '';
    _ctrlComManual.text = r != null ? Fmt.money(r.vlrcomRep) : '';
    _ctrlObs.text = r?.obsRep ?? '';
    _cargarCatalogos();
    if (!_esNuevo) _cargarAbonos();
  }

  @override
  void dispose() {
    _ctrlPrimaManual.dispose();
    _ctrlComManual.dispose();
    _ctrlObs.dispose();
    super.dispose();
  }

  // ── Carga de catálogos ────────────────────────────────────────────────────
  Future<void> _cargarCatalogos() async {
    setState(() => _cargandoCatalogos = true);
    try {
      final res = await Future.wait([
        _repoCatalogos.listarAseguradoras(),
        _repoCatalogos.listarIntermediarios(),
      ]);
      if (!mounted) return;
      setState(() {
        _aseguradoras = res[0] as List<Aseguradora>;
        _intermediarios = res[1] as List<Intermediario>;
        final r = widget.reporte;
        if (r?.asegId != null) {
          _aseguradora = _aseguradoras.firstOrNull((a) => a.id == r!.asegId);
        }
        if (r?.intermId != null) {
          _intermediario =
              _intermediarios.firstOrNull((i) => i.id == r!.intermId);
        }
      });
    } catch (e) {
      if (mounted) {
        _snack('No se pudieron cargar aseguradoras/intermediarios: $e',
            error: true);
      }
    }
    if (mounted) setState(() => _cargandoCatalogos = false);
  }

  // ── Carga de abonos ───────────────────────────────────────────────────────
  Future<void> _cargarAbonos() async {
    if (_idReporte == null) return;
    setState(() => _cargandoAbonos = true);
    try {
      final data = await _repoPagos.listarAbonosPorReporte(_idReporte!);
      if (mounted) setState(() => _abonos = data);
    } catch (e) {
      if (mounted) _snack('No se pudieron cargar los abonos: $e', error: true);
    }
    if (mounted) setState(() => _cargandoAbonos = false);
  }

  // ── Guardar reporte ───────────────────────────────────────────────────────
  Future<void> _guardar() async {
    if (_guardando) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      // Los totales calculados (suma de abonos) ya no se mandan: los
      // calcula la vista vw_reportes_resumen desde los abonos, así no pueden
      // quedar desfasados ni pisar lo que agregó otro usuario.
      final data = {
        'fecha_rep': _fechaRep.toIso8601String().substring(0, 10),
        'aseg_id': _aseguradora?.id,
        'interm_id': _intermediario?.id,
        'fini_rep': _finiRep?.toIso8601String().substring(0, 10),
        'ffin_rep': _ffinRep?.toIso8601String().substring(0, 10),
        'vlrprima_rep': parseNumCO(_ctrlPrimaManual.text) ?? 0,
        'vlrcom_rep': parseNumCO(_ctrlComManual.text) ?? 0,
        'estado_rep': _estadoRep,
        'obs_rep': _ctrlObs.text.trim().isEmpty ? null : _ctrlObs.text.trim(),
        'usuario_id': Sesion.usuarioId,
      };
      final int idGuardado;
      if (_esNuevo) {
        idGuardado = await _repoPagos.crearReporte(data);
      } else {
        idGuardado = _idReporte!;
        await _repoPagos.actualizarReporte(idGuardado, data);
      }

      // Aprendizaje, solo con el reporte ya guardado (antes corría antes y,
      // si el guardado fallaba y se reintentaba, contaba doble): si para
      // este texto de cabecera el usuario dejó un Intermediario distinto al
      // sugerido (o eligió uno cuando no se sugirió ninguno), se registra.
      if (_textoIntermParaAprendizaje != null &&
          _asegIdEnSugerenciaInterm != null &&
          _intermediario != null &&
          _intermediario!.id != _intermSugeridoPorIA &&
          _aseguradora?.id == _asegIdEnSugerenciaInterm) {
        final texto = _textoIntermParaAprendizaje!;
        _textoIntermParaAprendizaje = null;
        unawaited(_repoCatalogos.registrarAprendizajeIntermediario(
          _asegIdEnSugerenciaInterm!,
          texto,
          _intermediario!.id,
        ));
      }

      if (_esNuevo) {
        final id = idGuardado;
        if (!mounted) return;

        // Si se había importado un documento antes de guardar, las líneas
        // quedaron pendientes esperando un id real — ahora que existe, se
        // revisan/confirman antes de volver.
        if (_lineasPendientes.isNotEmpty) {
          final lineas = _lineasPendientes;
          setState(() => _lineasPendientes = []);
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaginaRevisionReportePago(
                idReporte: id,
                lineas: lineas,
                aseguradoraId: _aseguradora?.id,
              ),
            ),
          );
          if (!mounted) return;
        }

        // Reemplaza la pantalla con la del reporte recién creado
        final nuevo = await _repoPagos.obtenerReporte(id);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => FormularioReportePago(reporte: nuevo)),
        );
      } else if (mounted) {
        _snack('Reporte actualizado');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ── Acciones de abono ─────────────────────────────────────────────────────
  Future<void> _abrirDialogoAbono({AbonoPoliza? abono}) async {
    if (_idReporte == null) {
      _snack('Guarde primero el reporte y luego añada pólizas', error: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogAbono(
        idReporte: _idReporte!,
        abono: abono,
        repo: _repoPagos,
      ),
    );
    if (ok == true) await _cargarAbonos();
  }

  Future<void> _importarDesdeArchivo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'xlsx', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final bytes = file.bytes;
    final ext = (file.extension ?? '').toLowerCase();
    final mimeType = switch (ext) {
      'pdf' => 'application/pdf',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
    if (bytes == null || mimeType == null) {
      _snack('No se pudo leer el archivo. Use PDF, XLSX, JPG, PNG o WEBP.',
          error: true);
      return;
    }

    setState(() => _importando = true);
    try {
      final extraido = await _repoIA.extraerReportePago(bytes, mimeType);
      if (!mounted) return;

      // Cabecera: solo se aplica lo que efectivamente se reconoció.
      final nombreAseg = extraido.cabecera['nombre_aseguradora'] as String?;
      final matchAseg =
          _matchPorNombre(_aseguradoras, (a) => a.nombreAseg, nombreAseg);
      final asegParaAprendizaje = matchAseg ?? _aseguradora;
      final dRep = _parseFechaISO(extraido.cabecera['fecha_reporte']);
      final dIni = _parseFechaISO(extraido.cabecera['fecha_inicio_periodo']);
      final dFin = _parseFechaISO(extraido.cabecera['fecha_fin_periodo']);
      final vComTotal = extraido.cabecera['vlr_comision_total'];
      // Prima total: si el documento no trae una fila de total general (le
      // pasa a varios formatos de "cuenta corriente"), se calcula sumando
      // lo que sí se logró extraer de las líneas — mejor una suma real que
      // dejarlo en blanco.
      final vPrimaTotalCabecera = extraido.cabecera['vlr_prima_total'];
      final vPrimaTotal = vPrimaTotalCabecera is num
          ? vPrimaTotalCabecera
          : extraido.lineas.fold<num>(0, (s, l) {
              final v = l['vlrprima_poliza'] ?? l['vlrabono_prima'];
              return s + (v is num ? v : 0);
            });

      // Intermediario: el texto de cabecera casi nunca coincide en forma
      // con el nombre guardado (trae código + nombre reordenado) — primero
      // se prueba lo aprendido de correcciones anteriores para esta misma
      // aseguradora, y si no hay, el matcheo difuso de siempre.
      final textoInterm = extraido.cabecera['nombre_intermediario'] as String?;
      final textoIntermNorm =
          textoInterm != null ? _normalizarTexto(textoInterm) : '';
      Intermediario? matchInterm;
      if (textoIntermNorm.isNotEmpty && asegParaAprendizaje != null) {
        try {
          final idAprendido = await _repoCatalogos.buscarIntermediarioAprendido(
              asegParaAprendizaje.id, textoIntermNorm);
          if (idAprendido != null) {
            matchInterm =
                _intermediarios.firstOrNull((i) => i.id == idAprendido);
          }
        } catch (_) {}
      }
      matchInterm ??=
          _matchPorNombre(_intermediarios, (i) => i.nombreInterm, textoInterm);
      if (textoIntermNorm.isNotEmpty && asegParaAprendizaje != null) {
        _intermSugeridoPorIA = matchInterm?.id;
        _textoIntermParaAprendizaje = textoIntermNorm;
        _asegIdEnSugerenciaInterm = asegParaAprendizaje.id;
      }

      setState(() {
        if (matchAseg != null) _aseguradora = matchAseg;
        if (matchInterm != null) _intermediario = matchInterm;
        if (dRep != null) _fechaRep = dRep;
        if (dIni != null) _finiRep = dIni;
        if (dFin != null) _ffinRep = dFin;
        if (vPrimaTotal > 0) _ctrlPrimaManual.text = Fmt.money(vPrimaTotal);
        if (vComTotal is num) _ctrlComManual.text = Fmt.money(vComTotal);
      });

      if (extraido.lineas.isEmpty) {
        _snack(
            'Se completó la cabecera. No se encontraron líneas de pólizas en el documento.');
        return;
      }

      if (_idReporte != null) {
        // El reporte ya existe: se revisan las líneas de una.
        final creoAlgo = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => PaginaRevisionReportePago(
              idReporte: _idReporte!,
              lineas: extraido.lineas,
              aseguradoraId: _aseguradora?.id,
            ),
          ),
        );
        if (creoAlgo == true) {
          await _cargarAbonos();
        }
      } else {
        // Reporte nuevo, todavía sin id: las líneas quedan pendientes hasta
        // que se guarde — recién ahí se pueden crear los abonos.
        setState(() => _lineasPendientes = extraido.lineas);
        _snack(
            'Se completó la cabecera y se detectaron ${extraido.lineas.length} línea(s). '
            'Guarde el reporte para revisarlas y crear los abonos.');
      }
    } catch (e) {
      _snack('Error al importar: $e', error: true);
    } finally {
      if (mounted) setState(() => _importando = false);
    }
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

  T? _matchPorNombre<T>(
      List<T> lista, String Function(T) nombre, String? candidato) {
    if (candidato == null || candidato.trim().isEmpty) return null;
    final norm = _normalizarTexto(candidato);
    for (final item in lista) {
      if (_normalizarTexto(nombre(item)) == norm) return item;
    }
    for (final item in lista) {
      final n = _normalizarTexto(nombre(item));
      if (n.isNotEmpty && (n.contains(norm) || norm.contains(n))) return item;
    }
    return null;
  }

  String _normalizarTexto(String s) {
    var r = s.trim().toUpperCase();
    const acentos = {
      'Á': 'A',
      'É': 'E',
      'Í': 'I',
      'Ó': 'O',
      'Ú': 'U',
      'Ñ': 'N',
    };
    acentos.forEach((k, v) => r = r.replaceAll(k, v));
    return r;
  }

  Future<void> _confirmarEliminarAbono(AbonoPoliza a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar abono'),
        content: Text(
            '¿Eliminar el abono de ${a.nombreCliente ?? 'Póliza ${a.idPoliza}'}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repoPagos.eliminarAbono(a.id);
      await _cargarAbonos();
      await RepositorioPolizas().refrescarEnCache([a.idPoliza]);
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.danger : null,
    ));
  }

  Future<DateTime?> _pickDate(DateTime? initial) => mostrarSelectorFecha(
        context,
        inicial: initial,
        primera: DateTime(2000),
        ultima: DateTime(2100),
      );

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_esNuevo ? 'Nuevo Reporte' : 'Reporte #$_idReporte'),
        actions: [
          if (_importando)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton.icon(
              onPressed: _importarDesdeArchivo,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Importar desde PDF/imagen'),
            ),
          if (!_esNuevo)
            IconButton(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              tooltip: 'Estado de cuenta del reporte',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      PaginaEstadoCuenta.reporte(idReporte: _idReporte!),
                ),
              ),
            ),
          if (_guardando)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar'),
              onPressed: _guardar,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: AppLayout.centered(
            CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: AppLayout.pagePadding,
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // ── 1. Cabecera del reporte ──────────────────────────────
                      _SeccionHeader(
                          icon: Icons.description_outlined,
                          title: 'Datos del Reporte'),
                      const SizedBox(height: 12),

                      // Fecha + Estado
                      Row(children: [
                        Expanded(
                          child: _DateField(
                            label: 'Fecha del reporte *',
                            value: _fechaRep,
                            df: _df,
                            onTap: () async {
                              final d = await _pickDate(_fechaRep);
                              if (d != null) setState(() => _fechaRep = d);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _estadoRep,
                            decoration: const InputDecoration(
                              labelText: 'Estado',
                              border: OutlineInputBorder(),
                            ),
                            items: kEstadoPagoLabels.entries
                                .map((e) => DropdownMenuItem(
                                    value: e.key, child: Text(e.value)))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _estadoRep = v ?? 'I'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),

                      // Aseguradora + Intermediario
                      if (_cargandoCatalogos)
                        const LinearProgressIndicator()
                      else ...[
                        BuscadorDropdown<Aseguradora>(
                          label: 'Aseguradora *',
                          value: _aseguradora,
                          items: _aseguradoras,
                          itemLabel: (a) => a.nombreAseg,
                          onChanged: (a) => setState(() => _aseguradora = a),
                          validator: (v) => v == null ? 'Requerido' : null,
                        ),
                        const SizedBox(height: 12),
                        BuscadorDropdown<Intermediario>(
                          label: 'Intermediario',
                          value: _intermediario,
                          items: _intermediarios,
                          itemLabel: (i) => i.nombreInterm,
                          onChanged: (i) => setState(() => _intermediario = i),
                        ),
                      ],
                      const SizedBox(height: 12),

                      // Período inicio – fin
                      Row(children: [
                        Expanded(
                          child: _DateField(
                            label: 'Inicio período',
                            value: _finiRep,
                            df: _df,
                            onTap: () async {
                              final d = await _pickDate(_finiRep);
                              if (d != null) setState(() => _finiRep = d);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DateField(
                            label: 'Fin período',
                            value: _ffinRep,
                            df: _df,
                            onTap: () async {
                              final d = await _pickDate(_ffinRep);
                              if (d != null) setState(() => _ffinRep = d);
                            },
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),

                      // Valores manuales
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: _ctrlPrimaManual,
                            inputFormatters: const [NumeroCOInputFormatter()],
                            keyboardType: const TextInputType.numberWithOptions(
                                signed: true),
                            decoration: const InputDecoration(
                              labelText: 'Vlr Prima (manual)',
                              border: OutlineInputBorder(),
                              prefixText: '\$ ',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _ctrlComManual,
                            inputFormatters: const [NumeroCOInputFormatter()],
                            keyboardType: const TextInputType.numberWithOptions(
                                signed: true),
                            decoration: const InputDecoration(
                              labelText: 'Vlr Comisión (manual)',
                              border: OutlineInputBorder(),
                              prefixText: '\$ ',
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _ctrlObs,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Observaciones',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── 2. Resumen calculado (solo si no es nuevo) ───────────
                      if (!_esNuevo) ...[
                        _SeccionHeader(
                            icon: Icons.calculate_outlined,
                            title: 'Resumen Calculado'),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: StatCard(
                              width: null,
                              label: 'Prima total (calculada)',
                              value: '\$ ${Fmt.money(_sumaPrima)}',
                              icon: Icons.attach_money,
                              color: AppTheme.navy,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: StatCard(
                              width: null,
                              label: 'Comisión total (calculada)',
                              value: '\$ ${Fmt.money(_sumaCom)}',
                              icon: Icons.percent,
                              color: AppTheme.green,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: StatCard(
                              width: null,
                              label: 'Pólizas en reporte',
                              value: '${_abonos.length}',
                              icon: Icons.receipt_long,
                              color: AppTheme.warning,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 24),

                        // ── 3. Tabla de abonos ───────────────────────────────
                        Row(children: [
                          Expanded(
                            child: _SeccionHeader(
                                icon: Icons.list_alt_outlined,
                                title: 'Pólizas en este Reporte'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Añadir póliza'),
                            onPressed: () => _abrirDialogoAbono(),
                          ),
                        ]),
                        const SizedBox(height: 10),

                        if (_cargandoAbonos)
                          const Center(
                              child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: CircularProgressIndicator()))
                        else if (_abonos.isEmpty)
                          Card(
                            color: cs.surfaceContainerLow,
                            child: const Padding(
                              padding: EdgeInsets.all(28),
                              child: Center(
                                child: Text(
                                  'Sin pólizas en este reporte.\nPresione "Añadir póliza" para comenzar.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          )
                        else
                          _TablaAbonos(
                            abonos: _abonos,
                            onEdit: (a) => _abrirDialogoAbono(abono: a),
                            onDelete: _confirmarEliminarAbono,
                            onEstadoCuenta: (a) => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PaginaEstadoCuenta.poliza(
                                    idPoliza: a.idPoliza),
                              ),
                            ),
                          ),
                      ],
                    ]),
                  ),
                ),
              ],
            ),
            maxWidth: AppLayout.maxTableWidth),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tabla embebida de abonos
// ─────────────────────────────────────────────────────────────────────────────

class _TablaAbonos extends StatelessWidget {
  final List<AbonoPoliza> abonos;
  final void Function(AbonoPoliza) onEdit;
  final void Function(AbonoPoliza) onDelete;
  final void Function(AbonoPoliza) onEstadoCuenta;

  const _TablaAbonos({
    required this.abonos,
    required this.onEdit,
    required this.onDelete,
    required this.onEstadoCuenta,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hScroll = ScrollController();

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
            dataRowMinHeight: 52,
            dataRowMaxHeight: 68,
            columnSpacing: 12,
            columns: const [
              DataColumn(label: Text('N° Póliza')),
              DataColumn(label: Text('Cliente')),
              DataColumn(label: Text('Ramo / Producto')),
              DataColumn(label: Text('Bien asegurado')),
              DataColumn(label: Text('Vlr Prima'), numeric: true),
              DataColumn(label: Text('Abono'), numeric: true),
              DataColumn(label: Text('% Com'), numeric: true),
              DataColumn(label: Text('Vlr Com'), numeric: true),
              DataColumn(label: Text('Estado')),
              DataColumn(label: Text('Acciones')),
            ],
            rows: abonos.map((a) {
              return DataRow(cells: [
                DataCell(CeldaAnchoFijo(
                  a.nroPoliza ?? '${a.idPoliza}',
                  ancho: 200,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12),
                )),
                DataCell(Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CeldaAnchoFijo(a.nombreCliente ?? '—',
                        ancho: 300, style: const TextStyle(fontSize: 12)),
                    if (a.docCliente != null)
                      Text(
                        '${a.tipodocCliente ?? ''} ${Fmt.doc(a.docCliente)}',
                        style: TextStyle(fontSize: 10, color: AppTheme.inkSoft),
                      ),
                  ],
                )),
                DataCell(Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.nombreRamo ?? '—',
                        style: const TextStyle(fontSize: 12)),
                    if (a.nombreProd != null)
                      Text(a.nombreProd!,
                          style:
                              TextStyle(fontSize: 10, color: AppTheme.inkSoft)),
                  ],
                )),
                DataCell(SizedBox(
                  width: 140,
                  child: Text(
                    a.bienAsegurado ?? '—',
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
                DataCell(Text('\$ ${Fmt.money(a.vlrprimaPoliza)}',
                    style: TextStyle(
                        fontFamily: AppTheme.monoFamily, fontSize: 12))),
                DataCell(Text('\$ ${Fmt.money(a.vlrabonoprima)}',
                    style: TextStyle(
                        fontFamily: AppTheme.monoFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.bold))),
                DataCell(Text(Fmt.percent(a.porccomision, dec: 1))),
                DataCell(Text('\$ ${Fmt.money(a.vlrcomision)}',
                    style: TextStyle(
                        fontFamily: AppTheme.monoFamily, fontSize: 12))),
                DataCell(_ChipEstadoAbono(a.estadoPago)),
                DataCell(Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 17),
                      tooltip: 'Editar',
                      onPressed: () => onEdit(a),
                    ),
                    IconButton(
                      icon: const Icon(Icons.account_balance_wallet_outlined,
                          size: 17),
                      tooltip: 'Estado de cuenta',
                      color: AppTheme.navy,
                      onPressed: () => onEstadoCuenta(a),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 17),
                      tooltip: 'Eliminar',
                      color: AppTheme.danger,
                      onPressed: () => onDelete(a),
                    ),
                  ],
                )),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }
}

/// Abre el mismo diálogo "Editar abono" de los reportes, para corregir un
/// abono desde fuera (p. ej. desde "Casos por revisar"). Devuelve true si
/// se guardó. No cambia nada por su cuenta: guardar pasa por el mismo
/// camino de siempre (la base recalcula lo pagado de la póliza).
Future<bool?> mostrarDialogoEditarAbono(
  BuildContext context,
  AbonoPoliza abono,
) {
  final idReporte = abono.idrepPago;
  if (idReporte == null) return Future.value(false);
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DialogAbono(
      idReporte: idReporte,
      abono: abono,
      repo: RepositorioPagos(),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Diálogo añadir / editar abono
// ─────────────────────────────────────────────────────────────────────────────

class _DialogAbono extends StatefulWidget {
  final int idReporte;
  final AbonoPoliza? abono;
  final RepositorioPagos repo;

  const _DialogAbono({
    required this.idReporte,
    this.abono,
    required this.repo,
  });

  @override
  State<_DialogAbono> createState() => _DialogAbonoState();
}

class _DialogAbonoState extends State<_DialogAbono> {
  final _formKey = GlobalKey<FormState>();
  final _repoPolizas = RepositorioPolizas();
  final _df = DateFormat('dd/MM/yyyy');

  bool _guardando = false;
  bool _cargandoPoliza = false;

  Poliza? _poliza;
  DateTime? _fechaPago;
  String _estadoPago = 'R';

  final _ctrlPrima = TextEditingController();
  final _ctrlAbono = TextEditingController();
  final _ctrlPorcCom = TextEditingController();
  final _ctrlVlrCom = TextEditingController();
  final _ctrlPorcAd = TextEditingController();
  final _ctrlVlrAd = TextEditingController();
  final _ctrlFactura = TextEditingController();
  final _ctrlObs = TextEditingController();

  bool get _esNuevo => widget.abono == null;

  // Si el usuario escribió la comisión (ej. la cifra exacta del reporte
  // de la aseguradora), cambiar el abono o el % ya no la pisa.
  bool _comEditadaAMano = false;
  bool _comAdEditadaAMano = false;

  @override
  void initState() {
    super.initState();
    _fechaPago = DateTime.now();
    final a = widget.abono;
    if (a != null) {
      _fechaPago = a.fechaPago ?? DateTime.now();
      _estadoPago = a.estadoPago;
      // Con decimales: antes se redondeaba a pesos y al volver a
      // guardar el abono quedaba cambiado.
      _ctrlPrima.text = formatearNumCO(a.vlrprimaPoliza);
      _ctrlAbono.text = formatearNumCO(a.vlrabonoprima);
      _ctrlPorcCom.text = formatearNumCO(a.porccomision, maxDecimales: 5);
      _ctrlVlrCom.text = formatearNumCO(a.vlrcomision);
      _ctrlPorcAd.text = formatearNumCO(a.porccomad, maxDecimales: 5);
      _ctrlVlrAd.text = formatearNumCO(a.vlrcomad);
      _comEditadaAMano = true;
      _comAdEditadaAMano = true;
      _ctrlFactura.text = a.numFactura ?? '';
      _ctrlObs.text = a.obsPago ?? '';
      _cargarPolizaInicial(a.idPoliza);
    }
  }

  @override
  void dispose() {
    _ctrlPrima.dispose();
    _ctrlAbono.dispose();
    _ctrlPorcCom.dispose();
    _ctrlVlrCom.dispose();
    _ctrlPorcAd.dispose();
    _ctrlVlrAd.dispose();
    _ctrlFactura.dispose();
    _ctrlObs.dispose();
    super.dispose();
  }

  Future<void> _cargarPolizaInicial(int id) async {
    setState(() => _cargandoPoliza = true);
    try {
      final p = await _repoPolizas.obtenerPoliza(id);
      if (mounted && p != null) setState(() => _poliza = p);
    } catch (_) {}
    if (mounted) setState(() => _cargandoPoliza = false);
  }

  void _onPolizaSeleccionada(Poliza p) {
    setState(() {
      _poliza = p;
      _ctrlPrima.text = formatearNumCO(p.primaPoliza);
      // Sugiere lo que falta por pagar, no la prima completa: con
      // pagos previos, la prima completa sería un sobrepago.
      final saldo = p.primaPoliza - (p.vlrprimapagadaPoliza ?? 0);
      _ctrlAbono.text = saldo > 0 ? formatearNumCO(saldo) : '';
      _ctrlPorcCom.text = formatearNumCO(p.porccomPoliza ?? 0, maxDecimales: 5);
      _recalcular();
    });
  }

  void _recalcular() {
    final abono = (parseNumCO(_ctrlAbono.text) ?? 0);
    final pCom = (parseNumCO(_ctrlPorcCom.text) ?? 0);
    final pComAd = (parseNumCO(_ctrlPorcAd.text) ?? 0);
    if (!_comEditadaAMano) {
      _ctrlVlrCom.text = formatearNumCO(abono * pCom / 100);
    }
    if (!_comAdEditadaAMano) {
      _ctrlVlrAd.text = formatearNumCO(abono * pComAd / 100);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_poliza == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Seleccione una póliza'),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }
    setState(() => _guardando = true);
    try {
      final data = {
        'idrep_pago': widget.idReporte,
        'id_poliza': _poliza!.id,
        'fecha_pago': _fechaPago?.toIso8601String().substring(0, 10),
        'vlrprima_poliza': (parseNumCO(_ctrlPrima.text) ?? 0),
        'vlrabono_prima': (parseNumCO(_ctrlAbono.text) ?? 0),
        'porccomision': (parseNumCO(_ctrlPorcCom.text) ?? 0),
        'vlrcomision': (parseNumCO(_ctrlVlrCom.text) ?? 0),
        'porccomad': (parseNumCO(_ctrlPorcAd.text) ?? 0),
        'vlrcomad': (parseNumCO(_ctrlVlrAd.text) ?? 0),
        'num_factura':
            _ctrlFactura.text.trim().isEmpty ? null : _ctrlFactura.text.trim(),
        'estado_pago': _estadoPago,
        'obs_pago': _ctrlObs.text.trim().isEmpty ? null : _ctrlObs.text.trim(),
      };
      if (_esNuevo) {
        await widget.repo.crearAbono(data);
      } else {
        await widget.repo.actualizarAbono(widget.abono!.id, data);
      }
      // Lo pagado y el estado de la póliza los recalcula la base.
      await _repoPolizas.refrescarEnCache([_poliza!.id]);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(_esNuevo ? 'Añadir póliza al reporte' : 'Editar abono'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Búsqueda de póliza (solo al crear) ──────────────────────
                if (_esNuevo) ...[
                  BuscadorDropdown<Poliza>(
                    label: 'Buscar y seleccionar póliza *',
                    value: _poliza,
                    items: _poliza != null ? [_poliza!] : [],
                    itemLabel: (p) =>
                        '${p.nroPoliza ?? p.id}  –  ${p.nombreCliente ?? ''}',
                    itemSubtitle: (p) =>
                        '${p.nombreRamo ?? ''}  |  ${p.bienAsegurado ?? ''}',
                    itemsLoader: (q) =>
                        _repoPolizas.listar(busqueda: q, limite: 60),
                    onChanged: (p) {
                      if (p != null) _onPolizaSeleccionada(p);
                    },
                    validator: (v) =>
                        v == null ? 'Seleccione una póliza' : null,
                  ),
                  const SizedBox(height: 10),
                ],
                // ── Info póliza seleccionada ─────────────────────────────────
                if (_cargandoPoliza)
                  const LinearProgressIndicator()
                else if (_poliza != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cs.primaryContainer),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.receipt_long_outlined,
                              size: 14, color: cs.primary),
                          const SizedBox(width: 6),
                          Text('Póliza seleccionada',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: cs.primary,
                                  fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 6),
                        _InfoRow('Cliente', _poliza!.nombreCliente ?? '—'),
                        _InfoRow('Ramo', _poliza!.nombreRamo ?? '—'),
                        _InfoRow('Producto', _poliza!.nombreProd ?? '—'),
                        _InfoRow(
                            'Bien asegurado', _poliza!.bienAsegurado ?? '—'),
                        _InfoRow('Prima póliza',
                            '\$ ${Fmt.money(_poliza!.primaPoliza)}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // ── Fecha de pago + Estado ──────────────────────────────────
                Row(children: [
                  Expanded(
                    child: _DateField(
                      label: 'Fecha de pago *',
                      value: _fechaPago,
                      df: _df,
                      onTap: () async {
                        final d = await mostrarSelectorFecha(
                          context,
                          inicial: _fechaPago,
                          primera: DateTime(2000),
                          ultima: DateTime(2100),
                        );
                        if (d != null) setState(() => _fechaPago = d);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _estadoPago,
                      decoration: const InputDecoration(
                          labelText: 'Estado', border: OutlineInputBorder()),
                      items: kEstadoPagoLabels.entries
                          .map((e) => DropdownMenuItem(
                              value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: (v) => setState(() => _estadoPago = v ?? 'R'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                // ── Valores ─────────────────────────────────────────────────
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ctrlPrima,
                      inputFormatters: const [NumeroCOInputFormatter()],
                      keyboardType:
                          const TextInputType.numberWithOptions(signed: true),
                      decoration: const InputDecoration(
                          labelText: 'Vlr Prima Póliza',
                          border: OutlineInputBorder(),
                          prefixText: '\$ '),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Requerido' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _ctrlAbono,
                      inputFormatters: const [NumeroCOInputFormatter()],
                      keyboardType:
                          const TextInputType.numberWithOptions(signed: true),
                      onChanged: (_) => _recalcular(),
                      decoration: InputDecoration(
                        labelText: 'Vlr Abono Prima *',
                        border: const OutlineInputBorder(),
                        prefixText: '\$ ',
                        filled: true,
                        fillColor: cs.primaryContainer.withOpacity(0.15),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Requerido' : null,
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                // Comisión principal
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ctrlPorcCom,
                      inputFormatters: const [
                        NumeroCOInputFormatter(maxDecimales: 5)
                      ],
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _recalcular(),
                      decoration: const InputDecoration(
                          labelText: '% Comisión',
                          border: OutlineInputBorder(),
                          suffixText: '%'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _ctrlVlrCom,
                      inputFormatters: const [NumeroCOInputFormatter()],
                      onChanged: (_) => _comEditadaAMano = true,
                      keyboardType:
                          const TextInputType.numberWithOptions(signed: true),
                      decoration: const InputDecoration(
                          labelText: 'Vlr Comisión',
                          border: OutlineInputBorder(),
                          prefixText: '\$ '),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                // Comisión adicional
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ctrlPorcAd,
                      inputFormatters: const [
                        NumeroCOInputFormatter(maxDecimales: 5)
                      ],
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _recalcular(),
                      decoration: const InputDecoration(
                          labelText: '% Com. Adicional',
                          border: OutlineInputBorder(),
                          suffixText: '%'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _ctrlVlrAd,
                      inputFormatters: const [NumeroCOInputFormatter()],
                      onChanged: (_) => _comAdEditadaAMano = true,
                      keyboardType:
                          const TextInputType.numberWithOptions(signed: true),
                      decoration: const InputDecoration(
                          labelText: 'Vlr Com. Adicional',
                          border: OutlineInputBorder(),
                          prefixText: '\$ '),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                // N° Factura + obs
                TextFormField(
                  controller: _ctrlFactura,
                  decoration: const InputDecoration(
                    labelText: 'N° Factura',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.receipt, size: 18),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _ctrlObs,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Observaciones', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          icon: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save, size: 18),
          label: Text(_esNuevo ? 'Añadir' : 'Actualizar'),
          onPressed: _guardando ? null : _guardar,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets auxiliares compartidos
// ─────────────────────────────────────────────────────────────────────────────

class _ChipEstadoAbono extends StatelessWidget {
  final String estado;
  const _ChipEstadoAbono(this.estado);

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
      child: Text(
        labelEstadoPago(estado),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}

class _SeccionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SeccionHeader({required this.icon, required this.title});

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

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final DateFormat df;
  final VoidCallback onTap;
  const _DateField(
      {required this.label,
      required this.value,
      required this.df,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today, size: 16),
        ),
        child: Text(value != null ? df.format(value!) : '—'),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(children: [
        SizedBox(
          width: 110,
          child: Text('$label:',
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ),
        Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}
