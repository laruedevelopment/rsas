import 'package:flutter/material.dart';
import '../../datos/catalogos.dart';
import '../../datos/repositorio_catalogos.dart';
import '../theme/app_layout.dart';
import '../widgets/section_card.dart';
import '../../utils/mensajes_error.dart';

class FormFormaPago extends StatefulWidget {
  final FormaPago? forma;
  const FormFormaPago({super.key, this.forma});

  @override
  State<FormFormaPago> createState() => _FormFormaPagoState();
}

class _FormFormaPagoState extends State<FormFormaPago> {
  final _formKey = GlobalKey<FormState>();
  final repo = RepositorioCatalogos();

  bool guardando = false;
  bool cargandoId = true;

  late final TextEditingController idCtrl;
  late final TextEditingController nombreCtrl;
  late bool estado;

  bool get esEdicion => widget.forma != null;

  @override
  void initState() {
    super.initState();
    idCtrl = TextEditingController(text: esEdicion ? widget.forma!.id.toString() : '');
    nombreCtrl = TextEditingController(text: widget.forma?.nombreFormaPago ?? '');
    estado = widget.forma?.estadoFormaPago ?? true;

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
    super.dispose();
  }

  Future<void> _cargarSiguienteId() async {
    try {
      final nextId = await repo.obtenerSiguienteIdFormaPago();
      if (!mounted) return;
      idCtrl.text = nextId.toString();
    } catch (e) {
      _toast(mensajeAmigable(e, accion: 'No se pudo cargar el siguiente ID'));
    } finally {
      if (mounted) setState(() => cargandoId = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _validarId(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Requerido';
    final n = int.tryParse(s);
    if (n == null) return 'Debe ser numérico';
    if (n <= 0) return 'Debe ser mayor que 0';
    return null;
  }

  Future<void> _guardar() async {
    if (guardando) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final idNum = int.tryParse(idCtrl.text.trim());
    if (idNum == null || idNum <= 0) {
      _toast('El ID debe ser un número válido mayor que 0.');
      return;
    }

    setState(() => guardando = true);
    try {
      final f = FormaPago(
        id: esEdicion ? widget.forma!.id : idNum,
        nombreFormaPago: nombreCtrl.text.trim(),
        estadoFormaPago: estado,
      );

      if (esEdicion) {
        await repo.actualizarFormaPago(widget.forma!.id, f);
      } else {
        await repo.crearFormaPago(f);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _toast(mensajeAmigable(e, accion: 'Error guardando'));
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(esEdicion ? 'Editar forma de pago' : 'Nueva forma de pago'),
        actions: [
          if (guardando)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
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
          constraints: const BoxConstraints(maxWidth: 500),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: AppLayout.pagePadding,
              children: [
                SectionCard(
                  titulo: 'Datos',
                  children: [
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
                                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                  )
                                : null,
                          ),
                          validator: _validarId,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: nombreCtrl,
                          autofocus: true,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _guardar(),
                          decoration: const InputDecoration(
                            labelText: 'Nombre *',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          title: const Text('Activa'),
                          value: estado,
                          onChanged: (v) => setState(() => estado = v),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: (guardando || cargandoId) ? null : _guardar,
                  icon: guardando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(guardando ? 'Guardando...' : 'Guardar'),
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
