import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../datos/poliza.dart';
import '../datos/repositorio_polizas.dart';
import '../utils/formatters.dart';
import 'dialogos/anular_poliza.dart';
import 'pagina_estado_cuenta.dart';
import 'pagina_formulario_polizas.dart';
import 'theme/app_layout.dart';
import 'theme/app_theme.dart';

/// Cómo se parecen las pólizas activas de un grupo con el mismo número.
enum _TipoGrupo { identicas, distintaPrimaOVigencia, distintoCliente }

extension on _TipoGrupo {
  String get etiqueta => switch (this) {
        _TipoGrupo.identicas => 'Idénticas',
        _TipoGrupo.distintaPrimaOVigencia => 'Distinta prima o vigencia',
        _TipoGrupo.distintoCliente => 'Distinto cliente',
      };

  String get ayuda => switch (this) {
        _TipoGrupo.identicas =>
          'Mismo cliente, prima y vigencia: casi seguro la misma póliza cargada dos veces.',
        _TipoGrupo.distintaPrimaOVigencia =>
          'Mismo cliente pero distinta prima o vigencia: puede ser una renovación, un anexo o un error.',
        _TipoGrupo.distintoCliente =>
          'Clientes distintos con el mismo número: probablemente un número o un cliente mal digitado.',
      };

  Color get color => switch (this) {
        _TipoGrupo.identicas => AppTheme.green,
        _TipoGrupo.distintaPrimaOVigencia => AppTheme.warning,
        _TipoGrupo.distintoCliente => AppTheme.danger,
      };
}

/// Agrupa las pólizas cuyo número, ignorando espacios/guiones/separadores,
/// coincide dentro de la misma aseguradora — para que el usuario decida qué
/// hacer con cada grupo: ver los pagos de cada póliza, corregir una o anular
/// la que sobra (con el mismo diálogo de Casos por revisar, que además deja
/// decidir qué hacer con sus pagos). No borra ni modifica nada solo.
class PaginaPolizasDuplicadas extends StatefulWidget {
  const PaginaPolizasDuplicadas({super.key});

  @override
  State<PaginaPolizasDuplicadas> createState() =>
      _PaginaPolizasDuplicadasState();
}

class _PaginaPolizasDuplicadasState extends State<PaginaPolizasDuplicadas> {
  final _repo = RepositorioPolizas();
  final _dia = DateFormat('dd/MM/yyyy');
  bool _cargando = true;
  String? _error;
  List<List<Poliza>> _grupos = [];

  _TipoGrupo? _filtro;
  bool _incluirResueltos = false;

  /// Números (normalizados) que el usuario tiene desplegados — se preserva
  /// entre recargas para que revisar una póliza y volver no vuelva a
  /// compactar todo el listado.
  final Set<String> _expandidos = {};

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
      // vw_polizas_duplicadas ya filtra en la base — solo trae las pólizas
      // cuyo número está repetido, no el catálogo completo (mucho más
      // rápido que el listarTodos() que se usaba antes acá).
      final todas = await _repo.listarDuplicados();
      final porNumero = <String, List<Poliza>>{};
      for (final p in todas) {
        final nro = (p.nroPoliza ?? '').trim();
        if (nro.isEmpty) continue;
        final norm = RepositorioPolizas.normalizarNroPoliza(nro);
        if (norm.isEmpty) continue;
        // Mismo número en aseguradoras distintas no es un duplicado.
        porNumero.putIfAbsent('${p.asegId ?? 0}|$norm', () => []).add(p);
      }
      final grupos = porNumero.values.where((g) => g.length > 1).toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      if (!mounted) return;
      setState(() => _grupos = grupos);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  bool _anulada(Poliza p) => p.estadoPolizaId == 'A';

  List<Poliza> _activas(List<Poliza> g) =>
      g.where((p) => !_anulada(p)).toList();

  /// Resuelto = ya quedó una sola póliza activa (las demás están anuladas).
  bool _resuelto(List<Poliza> g) => _activas(g).length < 2;

  _TipoGrupo _tipoDe(List<Poliza> g) {
    final activas = _activas(g);
    final base = activas.length >= 2 ? activas : g;
    if (base.map((p) => p.clienteId).toSet().length > 1) {
      return _TipoGrupo.distintoCliente;
    }
    final primas = base.map((p) => p.primaPoliza).toSet();
    final vigencias =
        base.map((p) => '${p.finiPoliza}|${p.ffinPoliza}').toSet();
    if (primas.length > 1 || vigencias.length > 1) {
      return _TipoGrupo.distintaPrimaOVigencia;
    }
    return _TipoGrupo.identicas;
  }

  Future<void> _editar(Poliza p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PaginaFormularioPolizas(poliza: p)),
    );
    // vw_polizas_duplicadas es una consulta chica (solo las pólizas
    // repetidas), así que recargar acá siempre — haya cambiado algo o no —
    // ya es rápido, sin necesitar un caché propio.
    _cargar();
  }

  Future<void> _anular(Poliza p) async {
    final cambio = await anularPolizaConPagos(context, p.id);
    if (cambio && mounted) _cargar();
  }

  void _verPagos(Poliza p) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => PaginaEstadoCuenta.poliza(idPoliza: p.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final pendientes = _grupos.where((g) => !_resuelto(g)).toList();
    final resueltos = _grupos.length - pendientes.length;
    final base = _incluirResueltos ? _grupos : pendientes;
    final conteo = {
      for (final t in _TipoGrupo.values)
        t: base.where((g) => _tipoDe(g) == t).length,
    };
    final visibles =
        base.where((g) => _filtro == null || _tipoDe(g) == _filtro).toList();
    final totalPolizas = visibles.fold<int>(0, (s, g) => s + g.length);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pólizas con número repetido'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text('Error: $_error',
                      style: TextStyle(color: AppTheme.danger)))
              : _grupos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 52, color: AppTheme.green),
                          const SizedBox(height: 12),
                          const Text('No hay números de póliza repetidos.'),
                        ],
                      ),
                    )
                  : AppLayout.centered(ListView(
                      padding: AppLayout.pagePadding,
                      children: [
                        Text(
                          '${visibles.length} número(s) repetido(s) — $totalPolizas póliza(s). '
                          'Se ignoran espacios y guiones al comparar y solo cuenta la misma '
                          'aseguradora. Aquí puede ver los pagos de cada póliza, corregirla o '
                          'anular la que sobra; nada se borra ni cambia solo.',
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ChoiceChip(
                              label: Text('Todos (${base.length})'),
                              selected: _filtro == null,
                              onSelected: (_) => setState(() => _filtro = null),
                            ),
                            for (final t in _TipoGrupo.values)
                              Tooltip(
                                message: t.ayuda,
                                child: ChoiceChip(
                                  label: Text('${t.etiqueta} (${conteo[t]})'),
                                  selected: _filtro == t,
                                  onSelected: (_) => setState(
                                      () => _filtro = _filtro == t ? null : t),
                                ),
                              ),
                            FilterChip(
                              label: Text('Incluir ya resueltos ($resueltos)'),
                              selected: _incluirResueltos,
                              onSelected: (v) =>
                                  setState(() => _incluirResueltos = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (visibles.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Text(
                                'No hay grupos con este filtro.',
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            ),
                          ),
                        for (final grupo in visibles) ...[
                          _grupoCard(grupo),
                          const SizedBox(height: 10),
                        ],
                      ],
                    )),
    );
  }

  Widget _grupoCard(List<Poliza> grupo) {
    final cs = Theme.of(context).colorScheme;
    final norm =
        RepositorioPolizas.normalizarNroPoliza(grupo.first.nroPoliza ?? '');
    final tipo = _tipoDe(grupo);
    final resuelto = _resuelto(grupo);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: ExpansionTile(
          key: PageStorageKey('${grupo.first.asegId ?? 0}|$norm'),
          initiallyExpanded: _expandidos.contains(norm),
          onExpansionChanged: (abierto) {
            if (abierto) {
              _expandidos.add(norm);
            } else {
              _expandidos.remove(norm);
            }
          },
          title: Row(
            children: [
              Flexible(
                child: Text(
                  grupo.first.nroPoliza ?? '—',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _chip(resuelto ? 'Resuelto' : tipo.etiqueta,
                  resuelto ? cs.onSurfaceVariant : tipo.color),
            ],
          ),
          subtitle: Text(
              '${grupo.length} pólizas con este número · ${_activas(grupo).length} activa(s)'),
          leading: CircleAvatar(
            backgroundColor: AppTheme.warningContainer,
            child: Text('${grupo.length}',
                style: TextStyle(
                    color: AppTheme.onWarningContainer,
                    fontWeight: FontWeight.bold)),
          ),
          children: grupo.map(_filaPoliza).toList(),
        ),
      ),
    );
  }

  Widget _chip(String texto, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(texto,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );

  Widget _filaPoliza(Poliza p) {
    final cs = Theme.of(context).colorScheme;
    final anulada = _anulada(p);
    final vigencia = (p.finiPoliza != null || p.ffinPoliza != null)
        ? '${p.finiPoliza != null ? _dia.format(p.finiPoliza!) : '?'} – '
            '${p.ffinPoliza != null ? _dia.format(p.ffinPoliza!) : '?'}'
        : null;
    return ListTile(
      dense: true,
      title: Row(
        children: [
          Flexible(
            child: Text(
              '#${p.id} — ${p.nombreCliente ?? '—'}',
              overflow: TextOverflow.ellipsis,
              style: anulada
                  ? TextStyle(
                      color: cs.onSurfaceVariant,
                      decoration: TextDecoration.lineThrough)
                  : null,
            ),
          ),
          if (anulada) ...[
            const SizedBox(width: 8),
            _chip('ANULADA', AppTheme.danger),
          ],
        ],
      ),
      subtitle: Text(
        '${p.nombreAseg ?? '—'} · ${p.nombreRamo ?? '—'} · '
        '${(p.bienAsegurado ?? '').isNotEmpty ? '${p.bienAsegurado} · ' : ''}'
        'Prima: \$ ${Fmt.money(p.primaPoliza)}'
        '${vigencia != null ? ' · Vigencia: $vigencia' : ''}'
        '${p.nroPoliza != null ? ' · Nro. exacto: "${p.nroPoliza}"' : ''}',
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 20),
            tooltip: 'Ver pagos',
            color: AppTheme.navy,
            onPressed: () => _verPagos(p),
          ),
          if (!anulada)
            IconButton(
              icon: const Icon(Icons.block, size: 20),
              tooltip: 'Anular esta póliza',
              color: AppTheme.danger,
              onPressed: () => _anular(p),
            ),
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
      onTap: () => _editar(p),
    );
  }
}
