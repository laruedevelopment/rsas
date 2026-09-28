import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../datos/repositorio_casos.dart';
import '../datos/repositorio_polizas.dart';
import '../datos/sesion.dart';
import 'pagina_estado_cuenta.dart';
import 'pagina_formulario_polizas.dart';
import 'theme/app_layout.dart';
import 'theme/app_theme.dart';

/// Bandeja "Casos por revisar": situaciones dudosas que el equipo debe
/// aclarar. Cada caso dice qué se sabe y qué hay que averiguar; quien lo
/// aclara escribe la respuesta y lo marca como resuelto. No corrige nada
/// solo — ver supabase/migrations/20260928120100_casos_revision.sql.
class PaginaCasosRevision extends StatefulWidget {
  const PaginaCasosRevision({super.key});

  @override
  State<PaginaCasosRevision> createState() => _PaginaCasosRevisionState();
}

class _PaginaCasosRevisionState extends State<PaginaCasosRevision> {
  final _repo = RepositorioCasos();
  final _repoPol = RepositorioPolizas();
  final _df = DateFormat('dd/MM/yyyy HH:mm');

  String _estado = 'P';
  bool _cargando = true;
  String? _error;
  List<CasoRevision> _casos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final casos = await _repo.listar(estado: _estado);
      if (mounted) setState(() => _casos = casos);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.danger : null,
    ));
  }

  Future<void> _abrirPoliza(int id) async {
    try {
      final p = await _repoPol.obtenerPoliza(id);
      if (!mounted) return;
      if (p == null) {
        _snack('No se encontró la póliza cód. $id', error: true);
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PaginaFormularioPolizas(poliza: p)),
      );
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  Future<void> _resolver(CasoRevision c) async {
    final ctrl = TextEditingController();
    final respuesta = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marcar como resuelto'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.titulo,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (c.pregunta != null) ...[
                const SizedBox(height: 8),
                Text(c.pregunta!,
                    style: TextStyle(color: AppTheme.inkSoft, fontSize: 13)),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '¿Qué se encontró y qué se hizo?',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (respuesta == null) return;
    try {
      await _repo.resolver(c.id, respuesta);
      _snack('Caso resuelto');
      _cargar();
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  Future<void> _reabrir(CasoRevision c) async {
    try {
      await _repo.reabrir(c.id);
      _snack('Caso reabierto');
      _cargar();
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Casos por revisar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: AppLayout.centered(Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(
              children: [
                for (final (id, nombre) in const [
                  ('P', 'Pendientes'),
                  ('R', 'Resueltos')
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(nombre),
                      selected: _estado == id,
                      onSelected: (_) {
                        setState(() => _estado = id);
                        _cargar();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text('Error: $_error',
                            style: TextStyle(color: AppTheme.danger)))
                    : _casos.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_outline,
                                    size: 52, color: AppTheme.green),
                                const SizedBox(height: 12),
                                Text(
                                  _estado == 'P'
                                      ? 'No hay casos pendientes.'
                                      : 'No hay casos resueltos.',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          )
                        : ListView(
                            padding: AppLayout.pagePadding,
                            children: [
                              for (final c in _casos) ...[
                                _casoCard(c),
                                const SizedBox(height: 12),
                              ],
                            ],
                          ),
          ),
        ],
      )),
    );
  }

  Widget _casoCard(CasoRevision c) {
    final colorTipo = switch (c.tipo) {
      'PAGO_SIN_POLIZA' => AppTheme.warning,
      'POSIBLE_DUPLICADO' => AppTheme.danger,
      'COMISION_RARA' => AppTheme.navy,
      _ => AppTheme.inkSoft,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorTipo.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(c.nombreTipo,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorTipo)),
                ),
                const SizedBox(width: 8),
                Text('Caso #${c.id}',
                    style: TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
              ],
            ),
            const SizedBox(height: 8),
            Text(c.titulo,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(c.descripcion,
                style: const TextStyle(fontSize: 13, height: 1.35)),
            if (c.pregunta != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.warningContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Qué hay que averiguar: ${c.pregunta}',
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.onWarningContainer,
                        height: 1.35)),
              ),
            ],
            if (c.resuelto) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Respuesta: ${c.respuesta ?? ''}',
                        style: const TextStyle(fontSize: 13, height: 1.35)),
                    const SizedBox(height: 4),
                    Text(
                      'Resuelto por ${c.resueltoPor ?? '—'}'
                      '${c.fresuelto != null ? ' el ${_df.format(c.fresuelto!)}' : ''}',
                      style: TextStyle(fontSize: 11, color: AppTheme.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final id in c.polizas) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.description_outlined, size: 16),
                    label: Text('Póliza cód. $id'),
                    onPressed: () => _abrirPoliza(id),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.account_balance_wallet_outlined,
                        size: 16),
                    label: Text('Pagos cód. $id'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              PaginaEstadoCuenta.poliza(idPoliza: id)),
                    ),
                  ),
                ],
                if (c.reporteId != null && Sesion.veComisiones)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.request_quote_outlined, size: 16),
                    label: Text('Reporte #${c.reporteId}'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => PaginaEstadoCuenta.reporte(
                              idReporte: c.reporteId!)),
                    ),
                  ),
                if (!c.resuelto)
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Marcar resuelto'),
                    onPressed: () => _resolver(c),
                  )
                else
                  TextButton(
                      onPressed: () => _reabrir(c),
                      child: const Text('Reabrir')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
