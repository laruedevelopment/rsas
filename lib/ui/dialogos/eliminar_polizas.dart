import 'package:flutter/material.dart';

import '../../datos/poliza.dart';
import '../../datos/repositorio_eliminacion.dart';
import '../../datos/sesion.dart';
import '../../utils/formatters.dart';
import '../../utils/mensajes_error.dart';
import '../theme/app_theme.dart';

/// Función que marca las pólizas (inyectable para pruebas).
typedef EnviarEliminacion = Future<ResultadoEliminacion> Function(
    List<int> ids, String motivo);

/// Pide confirmación para marcar [polizas] como eliminadas (una o varias, una
/// sola validación). No las borra: quedan pendientes de que un Administrador
/// las autorice o las rechace, y desaparecen de listas y estadísticas.
///
/// Devuelve true si se marcó alguna (quien llama recarga su lista).
Future<bool> mostrarDialogoEliminarPolizas(
  BuildContext context,
  List<Poliza> polizas, {
  EnviarEliminacion? enviar,
}) async {
  if (polizas.isEmpty) return false;
  final r = await showDialog<ResultadoEliminacion>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DialogoEliminarPolizas(polizas: polizas, enviar: enviar),
  );
  if (r == null || !context.mounted) return false;

  final porId = {for (final p in polizas) p.id: p};
  if (r.omitidas.isNotEmpty) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r.hechas > 0
            ? 'Se marcaron ${r.hechas}; ${r.omitidas.length} no se pudieron marcar'
            : 'No se pudo marcar ninguna'),
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
                              'Cód. ${o.id} · ${porId[o.id]?.nroPoliza ?? 'sin número'}\n',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
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
  } else if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        r.hechas == 1
            ? 'Póliza marcada para eliminar. Un administrador debe autorizarla.'
            : '${r.hechas} pólizas marcadas para eliminar. Un administrador debe autorizarlas.',
      ),
    ));
  }
  return r.hechas > 0;
}

class DialogoEliminarPolizas extends StatefulWidget {
  final List<Poliza> polizas;
  final EnviarEliminacion? enviar;
  const DialogoEliminarPolizas({super.key, required this.polizas, this.enviar});

  @override
  State<DialogoEliminarPolizas> createState() => _DialogoEliminarPolizasState();
}

class _DialogoEliminarPolizasState extends State<DialogoEliminarPolizas> {
  final _motivo = TextEditingController();
  final _confirmar = TextEditingController();
  bool _enviando = false;
  String? _error;

  static const int _minMotivo = 5;

  @override
  void dispose() {
    _motivo.dispose();
    _confirmar.dispose();
    super.dispose();
  }

  bool get _valido =>
      _motivo.text.trim().length >= _minMotivo &&
      _confirmar.text.trim().toUpperCase() == 'ELIMINAR';

  Future<void> _enviar() async {
    if (!_valido || _enviando) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final ids = widget.polizas.map((p) => p.id).toList();
      final envio = widget.enviar ?? RepositorioEliminacion().solicitar;
      final r = await envio(ids, _motivo.text.trim());
      if (mounted) Navigator.pop(context, r);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = mensajeAmigable(e, accion: 'No se pudo marcar para eliminar');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.polizas.length;
    final varias = n > 1;
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.delete_forever_outlined, color: AppTheme.danger),
        const SizedBox(width: 10),
        Expanded(
            child: Text(varias ? 'Eliminar $n pólizas' : 'Eliminar póliza')),
      ]),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.warningContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'No se borran todavía. Quedan marcadas, desaparecen de las '
                  'listas, las estadísticas y los dashboards, y un administrador '
                  '${Sesion.esAdmin ? '(usted, en "Eliminaciones por autorizar") ' : ''}'
                  'debe autorizar la eliminación o rechazarla (y entonces vuelven).',
                  style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: AppTheme.onWarningContainer),
                ),
              ),
              const SizedBox(height: 12),
              Text(varias ? 'Pólizas a eliminar ($n):' : 'Póliza a eliminar:',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: n,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = widget.polizas[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Cód. ${p.id} · ${p.nroPoliza ?? 'sin número'}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5)),
                            Text(
                              [
                                if ((p.nombreCliente ?? '').isNotEmpty)
                                  p.nombreCliente!,
                                if ((p.nombreAseg ?? '').isNotEmpty)
                                  p.nombreAseg!,
                                'Prima \$ ${Fmt.money(p.primaPoliza)}',
                              ].join(' · '),
                              style: const TextStyle(
                                  fontSize: 12, color: AppTheme.inkSoft),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _motivo,
                enabled: !_enviando,
                maxLength: 300,
                minLines: 2,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Motivo (obligatorio)',
                  hintText: 'Ej.: duplicada de la póliza cód. 1234',
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _confirmar,
                enabled: !_enviando,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _enviar(),
                decoration: const InputDecoration(
                  labelText: 'Para confirmar, escriba ELIMINAR',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!,
                      style: const TextStyle(color: AppTheme.danger)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
          onPressed: _valido && !_enviando ? _enviar : null,
          icon: _enviando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.delete_outline, size: 18),
          label:
              Text(varias ? 'Marcar $n para eliminar' : 'Marcar para eliminar'),
        ),
      ],
    );
  }
}
