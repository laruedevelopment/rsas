import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../datos/meta.dart';
import '../../datos/repositorio_dashboard.dart';
import '../../utils/formatters.dart';
import '../../utils/numeros_co.dart';
import '../theme/app_theme.dart';
import 'dashboard_widgets.dart';

/// Editor de metas mensuales (solo Administrador). Se elige indicador y
/// alcance (agencia o un asesor), se escriben los 12 meses o se reparte un
/// total anual en partes iguales. Lo que se edite en varios indicadores o
/// asesores dentro de la misma apertura se guarda junto.
/// Devuelve true si se guardó algo.
Future<bool?> mostrarDialogoMetas(
  BuildContext context, {
  required int anio,
  required List<Meta> metasActuales,
  required List<({int id, String nombre})> asesores,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DialogoMetas(
        anio: anio, metasActuales: metasActuales, asesores: asesores),
  );
}

class _DialogoMetas extends StatefulWidget {
  final int anio;
  final List<Meta> metasActuales;
  final List<({int id, String nombre})> asesores;
  const _DialogoMetas({
    required this.anio,
    required this.metasActuales,
    required this.asesores,
  });

  @override
  State<_DialogoMetas> createState() => _DialogoMetasState();
}

class _DialogoMetasState extends State<_DialogoMetas> {
  String _indicador = kIndicadoresMeta.first.clave;
  int _asesorId = 0;
  final _totalCtrl = TextEditingController();
  bool _guardando = false;
  String? _error;

  /// Controladores por (indicador|asesor) → 12 meses; se crean al visitar.
  final Map<String, List<TextEditingController>> _ctrl = {};
  final Set<String> _editados = {};

  String get _clave => '$_indicador|$_asesorId';

  IndicadorMeta get _ind =>
      kIndicadoresMeta.firstWhere((i) => i.clave == _indicador);

  List<TextEditingController> _controladores() {
    return _ctrl.putIfAbsent(_clave, () {
      return List.generate(12, (m) {
        final v = widget.metasActuales
            .where((x) =>
                x.indicador == _indicador &&
                x.asesorId == _asesorId &&
                x.mes == m + 1)
            .fold<num>(0, (s, x) => s + x.valor);
        return TextEditingController(text: v == 0 ? '' : Fmt.numCO(v));
      });
    });
  }

  @override
  void dispose() {
    _totalCtrl.dispose();
    for (final l in _ctrl.values) {
      for (final c in l) {
        c.dispose();
      }
    }
    super.dispose();
  }

  num _suma() =>
      _controladores().fold<num>(0, (s, c) => s + (parseNumCO(c.text) ?? 0));

  void _repartir() {
    final total = parseNumCO(_totalCtrl.text);
    if (total == null || total <= 0) return;
    final base = (total / 12).floor();
    final ctrls = _controladores();
    var acum = 0;
    for (var m = 0; m < 12; m++) {
      // El último mes absorbe el redondeo para que la suma sea exacta.
      final v = m == 11 ? total - acum : base;
      acum += base;
      ctrls[m].text = Fmt.numCO(v);
    }
    _editados.add(_clave);
    setState(() {});
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final metas = <Meta>[];
      for (final k in _editados) {
        final partes = k.split('|');
        final ctrls = _ctrl[k]!;
        for (var m = 0; m < 12; m++) {
          final v = parseNumCO(ctrls[m].text) ?? 0;
          if (v < 0) throw 'Hay valores negativos.';
          metas.add(Meta(
            anio: widget.anio,
            mes: m + 1,
            indicador: partes[0],
            asesorId: int.parse(partes[1]),
            valor: v,
          ));
        }
      }
      await RepositorioDashboard().guardarMetas(metas);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      final s = e.toString();
      setState(() {
        _guardando = false;
        _error = s.contains('metas_comerciales')
            ? 'Falta crear la tabla de metas (migración 20261005090000).'
            : 'No se pudo guardar: $s';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrls = _controladores();
    final meses = [
      for (var m = 1; m <= 12; m++) mesCorto(DateTime(2000, m, 1))
    ];
    return AlertDialog(
      title: Text('Metas ${widget.anio}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _indicador,
                    decoration: const InputDecoration(labelText: 'Indicador'),
                    items: [
                      for (final i in kIndicadoresMeta)
                        DropdownMenuItem(value: i.clave, child: Text(i.nombre)),
                    ],
                    onChanged: (v) => setState(() => _indicador = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _asesorId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Alcance'),
                    items: [
                      const DropdownMenuItem(
                          value: 0, child: Text('Toda la agencia')),
                      for (final a in widget.asesores)
                        DropdownMenuItem(
                            value: a.id,
                            child: Text(a.nombre,
                                overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _asesorId = v!),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _totalCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                    ],
                    decoration: InputDecoration(
                      labelText: 'Total anual (opcional)',
                      helperText:
                          _ind.monetario ? 'En pesos' : 'Cantidad de pólizas',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _repartir,
                  child: const Text('Repartir en 12 meses'),
                ),
              ]),
              const SizedBox(height: 14),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (var m = 0; m < 12; m++)
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: ctrls[m],
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                      ],
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(labelText: meses[m]),
                      onChanged: (_) => setState(() => _editados.add(_clave)),
                    ),
                  ),
              ]),
              const SizedBox(height: 12),
              Text(
                'Total del año: ${_ind.monetario ? fmtMonto(_suma()) : fmtEntero(_suma())}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: const TextStyle(color: AppTheme.danger)),
                ),
              const SizedBox(height: 6),
              const Text(
                'Puede cambiar de indicador o de asesor y seguir editando: '
                'al guardar se guardan todos los que modificó.',
                style: TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando || _editados.isEmpty ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar metas'),
        ),
      ],
    );
  }
}
