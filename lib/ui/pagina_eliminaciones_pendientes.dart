import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../datos/repositorio_eliminacion.dart';
import '../datos/sesion.dart';
import '../utils/formatters.dart';
import '../utils/mensajes_error.dart';
import 'theme/app_layout.dart';
import 'theme/app_theme.dart';

/// Bandeja del Administrador: pólizas que alguien marcó para eliminar.
/// Aquí se AUTORIZA (se borran de verdad, con copia en el registro) o se
/// RECHAZA (vuelven a las listas). Solo la ve el Administrador; la base
/// también lo exige, así que no depende de esta pantalla.
class PaginaEliminacionesPendientes extends StatefulWidget {
  const PaginaEliminacionesPendientes({super.key});

  @override
  State<PaginaEliminacionesPendientes> createState() =>
      _PaginaEliminacionesPendientesState();
}

class _PaginaEliminacionesPendientesState
    extends State<PaginaEliminacionesPendientes> {
  final _repo = RepositorioEliminacion();
  final _fecha = DateFormat('dd/MM/yyyy HH:mm');
  final _dia = DateFormat('dd/MM/yyyy');

  bool _verHistorial = false;
  bool _cargando = true;
  bool _trabajando = false;
  String? _error;
  List<SolicitudEliminacion> _pendientes = [];
  List<HistorialEliminacion> _historial = [];
  final Set<int> _sel = {}; // ids de solicitud

  @override
  void initState() {
    super.initState();
    if (Sesion.esAdmin) _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final p = await _repo.pendientes();
      final h = await _repo.historial();
      if (!mounted) return;
      setState(() {
        _pendientes = p;
        _historial = h;
        _sel.removeWhere((id) => !p.any((s) => s.id == id));
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            mensajeAmigable(e, accion: 'No se pudieron cargar las solicitudes');
        _cargando = false;
      });
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.danger : null,
    ));
  }

  // ── Acciones ────────────────────────────────────────────────────────────

  Future<void> _resolver({required bool aprobar}) async {
    final elegidas = _pendientes.where((s) => _sel.contains(s.id)).toList();
    if (elegidas.isEmpty || _trabajando) return;
    final nota = await showDialog<String>(
      context: context,
      builder: (_) =>
          _DialogoResolver(aprobar: aprobar, cantidad: elegidas.length),
    );
    if (nota == null || !mounted) return; // canceló ('' = sin nota)

    setState(() => _trabajando = true);
    try {
      final r = await _repo.resolver(
        elegidas.map((s) => s.id).toList(),
        aprobar: aprobar,
        nota: nota.isEmpty ? null : nota,
      );
      if (!mounted) return;
      _sel.clear();
      await _cargar();
      if (!mounted) return;
      final verbo = aprobar ? 'eliminadas definitivamente' : 'restauradas';
      if (r.omitidas.isEmpty) {
        _snack('${r.hechas} póliza(s) $verbo.');
      } else {
        final porSolicitud = {for (final s in elegidas) s.id: s};
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
                '${r.hechas} $verbo; ${r.omitidas.length} no se pudieron procesar'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final o in r.omitidas)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text.rich(TextSpan(children: [
                          TextSpan(
                              text:
                                  'Cód. ${porSolicitud[o.id]?.polizaId ?? o.id} · ${porSolicitud[o.id]?.nroPoliza ?? 'sin número'}\n',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          TextSpan(text: o.razon),
                        ])),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido')),
            ],
          ),
        );
      }
    } catch (e) {
      _snack(mensajeAmigable(e, accion: 'No se pudo completar la acción'),
          error: true);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  // ── Interfaz ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!Sesion.esAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Eliminaciones por autorizar')),
        body:
            const Center(child: Text('Solo disponible para administradores.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Eliminaciones por autorizar'),
        actions: [
          IconButton(
            tooltip: 'Recargar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando || _trabajando ? null : _cargar,
          ),
        ],
      ),
      body: AppLayout.centered(
        Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Row(children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: false,
                      icon:
                          const Icon(Icons.pending_actions_outlined, size: 18),
                      label: Text('Por autorizar (${_pendientes.length})')),
                  ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.history, size: 18),
                      label: Text('Historial (${_historial.length})')),
                ],
                selected: {_verHistorial},
                onSelectionChanged: (s) =>
                    setState(() => _verHistorial = s.first),
              ),
            ]),
          ),
          if (_cargando) const LinearProgressIndicator(),
          Expanded(
            child: _error != null
                ? _vistaError()
                : (_verHistorial ? _vistaHistorial() : _vistaPendientes()),
          ),
        ]),
      ),
    );
  }

  Widget _vistaError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: AppTheme.inkSoft),
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar')),
          ]),
        ),
      );

  Widget _vistaPendientes() {
    if (!_cargando && _pendientes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle_outline, size: 48, color: AppTheme.green),
            SizedBox(height: 10),
            Text('No hay eliminaciones por autorizar',
                style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 4),
            Text(
              'Cuando alguien marque una póliza para eliminar, aparecerá aquí.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.inkSoft),
            ),
          ]),
        ),
      );
    }

    // Agrupadas por lote (las marcadas juntas), la más reciente primero.
    final lotes = <String, List<SolicitudEliminacion>>{};
    for (final s in _pendientes) {
      (lotes[s.lote] ??= []).add(s);
    }
    final todas = _pendientes.length;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Checkbox(
              tristate: true,
              value:
                  _sel.isEmpty ? false : (_sel.length == todas ? true : null),
              onChanged: _trabajando
                  ? null
                  : (_) => setState(() {
                        if (_sel.length == todas) {
                          _sel.clear();
                        } else {
                          _sel.addAll(_pendientes.map((s) => s.id));
                        }
                      }),
            ),
            Text(_sel.isEmpty
                ? 'Seleccione para autorizar o rechazar varias a la vez'
                : '${_sel.length} seleccionada(s)'),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
              onPressed: _sel.isEmpty || _trabajando
                  ? null
                  : () => _resolver(aprobar: true),
              icon: const Icon(Icons.delete_forever_outlined, size: 18),
              label: Text('Autorizar eliminación (${_sel.length})'),
            ),
            OutlinedButton.icon(
              onPressed: _sel.isEmpty || _trabajando
                  ? null
                  : () => _resolver(aprobar: false),
              icon: const Icon(Icons.restore_from_trash_outlined, size: 18),
              label: Text('Rechazar y restaurar (${_sel.length})'),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            for (final e in lotes.entries) _tarjetaLote(e.value),
          ],
        ),
      ),
    ]);
  }

  Widget _tarjetaLote(List<SolicitudEliminacion> items) {
    final primera = items.first;
    final ids = items.map((s) => s.id).toSet();
    final marcadas = ids.where(_sel.contains).length;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
          child: Row(children: [
            Checkbox(
              tristate: true,
              value: marcadas == 0
                  ? false
                  : (marcadas == ids.length ? true : null),
              onChanged: _trabajando
                  ? null
                  : (_) => setState(() {
                        if (marcadas == ids.length) {
                          _sel.removeAll(ids);
                        } else {
                          _sel.addAll(ids);
                        }
                      }),
            ),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${items.length} póliza(s) · pedido por ${primera.solicitadoPor}'
                      '${primera.solicitadoEn != null ? ' el ${_fecha.format(primera.solicitadoEn!)}' : ''}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    Text('Motivo: ${primera.motivo}',
                        style: const TextStyle(
                            fontSize: 12.5, color: AppTheme.inkSoft)),
                  ]),
            ),
          ]),
        ),
        const Divider(height: 1),
        for (final s in items) _filaSolicitud(s),
      ]),
    );
  }

  Widget _filaSolicitud(SolicitudEliminacion s) {
    final marcada = _sel.contains(s.id);
    final conPagos = s.nPagos > 0;
    return InkWell(
      onTap: _trabajando
          ? null
          : () => setState(() => marcada ? _sel.remove(s.id) : _sel.add(s.id)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
        child: Row(children: [
          Checkbox(
            value: marcada,
            onChanged: _trabajando
                ? null
                : (v) => setState(
                    () => v == true ? _sel.add(s.id) : _sel.remove(s.id)),
          ),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Cód. ${s.polizaId} · ${s.nroPoliza ?? 'sin número'}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              Text(
                [
                  if ((s.cliente ?? '').isNotEmpty) s.cliente!,
                  if ((s.aseguradora ?? '').isNotEmpty) s.aseguradora!,
                  if ((s.ramo ?? '').isNotEmpty) s.ramo!,
                  'Prima \$ ${Fmt.money(s.prima)}',
                  if (s.fini != null && s.ffin != null)
                    '${_dia.format(s.fini!)} – ${_dia.format(s.ffin!)}',
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
              ),
            ]),
          ),
          if (conPagos)
            Tooltip(
              message:
                  'Tiene ${s.nPagos} pago(s) registrados: no se podrá borrar '
                  'hasta moverlos o eliminarlos.',
              child: Chip(
                avatar: const Icon(Icons.payments_outlined,
                    size: 14, color: AppTheme.warning),
                label: Text('${s.nPagos} pago(s)',
                    style: const TextStyle(fontSize: 11.5)),
                backgroundColor: AppTheme.warningContainer,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ]),
      ),
    );
  }

  Widget _vistaHistorial() {
    if (!_cargando && _historial.isEmpty) {
      return const Center(
        child: Text('Todavía no hay eliminaciones resueltas.',
            style: TextStyle(color: AppTheme.inkSoft)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: _historial.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final h = _historial[i];
        final color = h.aprobada ? AppTheme.danger : AppTheme.green;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(
                    h.aprobada
                        ? Icons.delete_forever_outlined
                        : Icons.restore_from_trash_outlined,
                    size: 18,
                    color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'Cód. ${h.polizaId} · ${h.nroPoliza ?? 'sin número'}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                Text(h.aprobada ? 'ELIMINADA' : 'RECHAZADA (restaurada)',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ]),
              const SizedBox(height: 4),
              Text('Motivo: ${h.motivo}',
                  style: const TextStyle(fontSize: 12.5)),
              Text(
                'Pedido por ${h.solicitadoPor}'
                '${h.solicitadoEn != null ? ' el ${_fecha.format(h.solicitadoEn!)}' : ''} · '
                '${h.aprobada ? 'autorizada' : 'rechazada'} por ${h.resueltoPor}'
                '${h.resueltoEn != null ? ' el ${_fecha.format(h.resueltoEn!)}' : ''}',
                style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
              ),
              if ((h.nota ?? '').isNotEmpty)
                Text('Nota: ${h.nota}',
                    style:
                        const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
            ]),
          ),
        );
      },
    );
  }
}

/// Confirmación al autorizar (exige escribir ELIMINAR) o rechazar. Devuelve la
/// nota ('' si no escribió ninguna) o null si cancela.
class _DialogoResolver extends StatefulWidget {
  final bool aprobar;
  final int cantidad;
  const _DialogoResolver({required this.aprobar, required this.cantidad});

  @override
  State<_DialogoResolver> createState() => _DialogoResolverState();
}

class _DialogoResolverState extends State<_DialogoResolver> {
  final _nota = TextEditingController();
  final _confirmar = TextEditingController();

  @override
  void dispose() {
    _nota.dispose();
    _confirmar.dispose();
    super.dispose();
  }

  bool get _valido =>
      !widget.aprobar || _confirmar.text.trim().toUpperCase() == 'ELIMINAR';

  @override
  Widget build(BuildContext context) {
    final n = widget.cantidad;
    final aprobar = widget.aprobar;
    return AlertDialog(
      title: Text(aprobar
          ? 'Autorizar la eliminación de $n póliza(s)'
          : 'Rechazar y restaurar $n póliza(s)'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                aprobar
                    ? 'Se borrarán DEFINITIVAMENTE de la base de datos. Queda una '
                        'copia de sus datos en el registro de eliminaciones. Las que '
                        'tengan pagos registrados no se borran.'
                    : 'Las pólizas vuelven a aparecer en las listas, las estadísticas '
                        'y los dashboards, como estaban.',
                style: const TextStyle(height: 1.35),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nota,
                maxLength: 300,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Nota (opcional)'),
              ),
              if (aprobar) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _confirmar,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      labelText: 'Para confirmar, escriba ELIMINAR'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          style: aprobar
              ? FilledButton.styleFrom(backgroundColor: AppTheme.danger)
              : null,
          onPressed:
              _valido ? () => Navigator.pop(context, _nota.text.trim()) : null,
          child: Text(
              aprobar ? 'Eliminar definitivamente' : 'Rechazar y restaurar'),
        ),
      ],
    );
  }
}
