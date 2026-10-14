import 'package:flutter/material.dart';
import '../../datos/catalogos.dart';
import '../../utils/numeros_co.dart';
import '../../datos/repositorio_catalogos.dart';
import '../../utils/formatters.dart';
import '../theme/app_layout.dart';
import '../widgets/section_card.dart';
import '../../utils/mensajes_error.dart';

class FormAsesor extends StatefulWidget {
  final Asesor? asesor;
  const FormAsesor({super.key, this.asesor});

  @override
  State<FormAsesor> createState() => _FormAsesorState();
}

class _FormAsesorState extends State<FormAsesor> {
  final _formKey = GlobalKey<FormState>();
  final repo = RepositorioCatalogos();

  bool guardando = false;
  bool cargandoId = true;

  late final TextEditingController idCtrl;
  late final TextEditingController nombreCtrl;
  late final TextEditingController docCtrl;
  late final TextEditingController telCtrl;
  late final TextEditingController correoCtrl;
  late final TextEditingController porccomCtrl;

  static const List<String> tiposDocNormalizados = ['CC', 'CE', 'NIT', 'PAS', 'OTRO'];
  String? tipoDocSel;

  bool estadoAsesor = true;

  bool get esEdicion => widget.asesor != null;

  @override
  void initState() {
    super.initState();

    idCtrl = TextEditingController(
      text: esEdicion ? widget.asesor!.id.toString() : '',
    );
    nombreCtrl = TextEditingController(text: widget.asesor?.nombreAsesor ?? '');
    docCtrl = TextEditingController(text: widget.asesor?.docAsesor ?? '');
    telCtrl = TextEditingController(text: widget.asesor?.telAsesor ?? '');
    correoCtrl = TextEditingController(text: widget.asesor?.correoAsesor ?? '');
    porccomCtrl = TextEditingController(
      text: widget.asesor?.porccomAsesor == null
          ? ''
          : Fmt.numCO(widget.asesor!.porccomAsesor, dec: 2),
    );

    final td = widget.asesor?.tipodocAsesor?.trim().toUpperCase();
    tipoDocSel = (td != null && tiposDocNormalizados.contains(td)) ? td : null;

    estadoAsesor = widget.asesor?.estadoAsesor ?? true;

    if (docCtrl.text.trim().isEmpty) tipoDocSel = null;

    docCtrl.addListener(() {
      final doc = docCtrl.text.trim();
      if (doc.isEmpty && tipoDocSel != null) {
        setState(() => tipoDocSel = null);
      }
    });

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
    docCtrl.dispose();
    telCtrl.dispose();
    correoCtrl.dispose();
    porccomCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarSiguienteId() async {
    try {
      final nextId = await repo.obtenerSiguienteIdAsesor();
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
  num? _parseNumeroONull(String v) => parseNumCO(v);

  String? _validarPorcentaje(String? v) {
    if ((v ?? '').trim().isEmpty) return null;
    final n = parseNumCO(v);
    if (n == null) return 'Valor inválido';
    if (n < 0 || n > 100) return 'Debe estar entre 0 y 100';
    return null;
  }

  void _formatearPorcentaje() {
    final n = _parseNumeroONull(porccomCtrl.text);
    if (n == null) return;
    porccomCtrl.text = formatearNumCO(n, maxDecimales: 5);
  }

  String? _validarCorreo(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    final ok = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s);
    return ok ? null : 'Correo inválido';
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

    final doc = _limpiarONull(docCtrl.text);
    final tipo = (tipoDocSel?.trim().isEmpty ?? true) ? null : tipoDocSel!.trim();

    if (doc != null && tipo == null) {
      _toast('Selecciona el tipo de documento.');
      return;
    }

    setState(() => guardando = true);
    try {
      final a = Asesor(
        id: esEdicion ? widget.asesor!.id : idNum,
        nombreAsesor: _limpiarObligatorio(nombreCtrl.text),
        tipodocAsesor: doc == null ? null : tipo,
        docAsesor: doc,
        telAsesor: _limpiarONull(telCtrl.text),
        correoAsesor: _limpiarONull(correoCtrl.text),
        porccomAsesor: _parseNumeroONull(porccomCtrl.text),
        estadoAsesor: estadoAsesor,
      );

      if (esEdicion) {
        await repo.actualizarAsesor(widget.asesor!.id, a);
      } else {
        await repo.crearAsesor(a);
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
        title: Text(esEdicion ? 'Editar asesor' : 'Nuevo asesor'),
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
          constraints: const BoxConstraints(maxWidth: 860),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: AppLayout.pagePadding,
              children: [
                // ── 1. Datos principales ─────────────────────────────────────
                _seccion('Datos principales', [
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
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(
                        labelText: 'Nombre *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final limpio = _limpiarONull(v ?? '');
                        return limpio == null ? 'Requerido' : null;
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: tiposDocNormalizados.contains(tipoDocSel)
                              ? tipoDocSel
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Tipo de documento',
                            border: OutlineInputBorder(),
                          ),
                          items: tiposDocNormalizados
                              .map((t) => DropdownMenuItem<String>(
                                    value: t,
                                    child: Text(t),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            setState(() => tipoDocSel = v);
                            if ((v ?? '').trim().isEmpty) docCtrl.text = '';
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: docCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Documento',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: porccomCtrl,
                    textInputAction: TextInputAction.next,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: _validarPorcentaje,
                      decoration: const InputDecoration(
                      labelText: '% Comisión',
                      helperText: 'Ej: 70 o 70,5',
                      border: OutlineInputBorder(),
                    ),
                    onEditingComplete: () {
                      _formatearPorcentaje();
                      FocusScope.of(context).nextFocus();
                    },
                  ),
                ]),

                // ── 2. Contacto ──────────────────────────────────────────────
                _seccion('Contacto', [
                  _fila2(
                    TextFormField(
                      controller: telCtrl,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      decoration: const InputDecoration(
                        labelText: 'Teléfono',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: correoCtrl,
                      textInputAction: TextInputAction.done,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Correo',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validarCorreo,
                      onFieldSubmitted: (_) => guardando ? null : _guardar(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: estadoAsesor,
                    onChanged: (v) => setState(() => estadoAsesor = v),
                    title: const Text('Asesor activo'),
                    subtitle: Text(estadoAsesor ? 'Activo' : 'Inactivo'),
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
                    child: Text(guardando ? 'Guardando...' : 'Guardar asesor'),
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
