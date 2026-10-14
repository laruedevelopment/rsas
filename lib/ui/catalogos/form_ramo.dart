import 'package:flutter/material.dart';
import '../../datos/catalogos.dart';
import '../../utils/numeros_co.dart';
import '../../datos/repositorio_catalogos.dart';
import '../theme/app_layout.dart';
import '../widgets/section_card.dart';
import '../../utils/mensajes_error.dart';

class FormRamo extends StatefulWidget {
  final Ramo? ramo;
  const FormRamo({super.key, this.ramo});

  @override
  State<FormRamo> createState() => _FormRamoState();
}

class _FormRamoState extends State<FormRamo> {
  final _formKey = GlobalKey<FormState>();
  final repo = RepositorioCatalogos();

  bool guardando = false;
  bool cargandoId = true;

  late final TextEditingController idCtrl;
  late final TextEditingController nombreCtrl;
  late final TextEditingController obsCtrl;
  late final TextEditingController porcomCtrl;

  bool estadoRamo = true;

  bool get esEdicion => widget.ramo != null;

  @override
  void initState() {
    super.initState();

    idCtrl = TextEditingController(
      text: esEdicion ? widget.ramo!.id.toString() : '',
    );
    nombreCtrl = TextEditingController(text: widget.ramo?.nombreRamo ?? '');
    obsCtrl = TextEditingController(text: widget.ramo?.obsRamo ?? '');

    final por = widget.ramo?.porcomBaseRamo ?? 100;
    porcomCtrl = TextEditingController(text: por.toString());

    estadoRamo = widget.ramo?.estadoRamo ?? true;

    if (!esEdicion) {
      _cargarSiguienteId();
    } else {
      cargandoId = false;
    }
  }

  @override
  void dispose() {
    idCtrl.dispose();
    nombreCtrl.dispose();
    obsCtrl.dispose();
    porcomCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarSiguienteId() async {
    try {
      final nextId = await repo.obtenerSiguienteIdRamo();
      if (!mounted) return;
      idCtrl.text = nextId.toString();
      setState(() => cargandoId = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => cargandoId = false);
      _toast(mensajeAmigable(e, accion: 'No se pudo cargar el siguiente ID'));
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _limpiarONull(String v) {
    final t = v.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.isEmpty ? null : t;
  }

  String _limpiarObligatorio(String v) {
    return v.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String? _validarId(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Requerido';
    final n = int.tryParse(s);
    if (n == null) return 'Debe ser numérico';
    if (n <= 0) return 'Debe ser mayor que 0';
    return null;
  }

  // Parser compartido: "12.5" es 12,5 (antes se borraban los puntos → 125).
  num _parseNumConDefault100(String s) => parseNumCO(s) ?? 100;

  String? _validarPorcom(String? v) {
    if ((v ?? '').trim().isEmpty) return null;
    final n = parseNumCO(v);
    if (n == null) return 'Valor inválido';
    if (n < 0 || n > 100) return 'Debe estar entre 0 y 100';
    return null;
  }

  Future<void> _guardar() async {
    if (guardando) return;

    FocusScope.of(context).unfocus();

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    final idTexto = idCtrl.text.trim();
    final idNum = int.tryParse(idTexto);

    if (idNum == null || idNum <= 0) {
      _toast('El ID debe ser un número válido mayor que 0.');
      return;
    }

    final nombre = _limpiarObligatorio(nombreCtrl.text);
    if (nombre.isEmpty) {
      _toast('El nombre es requerido.');
      return;
    }

    final porcom = _parseNumConDefault100(porcomCtrl.text);

    setState(() => guardando = true);
    try {
      final r = Ramo(
        id: esEdicion ? widget.ramo!.id : idNum,
        nombreRamo: nombre,
        estadoRamo: estadoRamo,
        obsRamo: _limpiarONull(obsCtrl.text),
        porcomBaseRamo: porcom,
      );

      if (esEdicion) {
        await repo.actualizarRamo(widget.ramo!.id, r);
      } else {
        await repo.crearRamo(r);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _toast(mensajeAmigable(e, accion: 'Error guardando'));
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  Widget _seccion(String titulo, List<Widget> campos) {
    return SectionCard(titulo: titulo, children: campos);
  }

  Widget _fila2(Widget a, Widget b) {
    final w = MediaQuery.of(context).size.width;
    if (w < 700) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [a, const SizedBox(height: 12), b],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 16),
        Expanded(child: b),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(esEdicion ? 'Editar ramo' : 'Nuevo ramo'),
        actions: [
          if (guardando)
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
              onPressed: cargandoId ? null : _guardar,
              icon: const Icon(Icons.save),
              label: const Text('Guardar'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: AppLayout.pagePadding,
              children: [
                // ── 1. Identificación ────────────────────────────────────────
                _seccion('Identificación', [
                  _fila2(
                    TextFormField(
                      controller: idCtrl,
                      enabled: !esEdicion,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: esEdicion ? 'ID' : 'ID sugerido',
                        border: const OutlineInputBorder(),
                        suffixIcon: cargandoId
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              )
                            : null,
                      ),
                      validator: _validarId,
                    ),
                    TextFormField(
                      controller: nombreCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del ramo *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final nombre = _limpiarObligatorio(v ?? '');
                        return nombre.isEmpty ? 'Requerido' : null;
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: porcomCtrl,
                    textInputAction: TextInputAction.next,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '% Base comisión',
                      helperText: 'Si lo dejas vacío, se guarda como 100',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validarPorcom,
                  ),
                ]),

                // ── 2. Observaciones ─────────────────────────────────────────
                _seccion('Observaciones', [
                  TextFormField(
                    controller: obsCtrl,
                    maxLines: 3,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: 'Observaciones (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: estadoRamo,
                    onChanged: (v) => setState(() => estadoRamo = v),
                    title: const Text('Activo'),
                    subtitle: Text(estadoRamo ? 'Activo' : 'Inactivo'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ]),

                FilledButton.icon(
                  onPressed: (guardando || cargandoId) ? null : _guardar,
                  icon: guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(guardando ? 'Guardando...' : 'Guardar ramo'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
