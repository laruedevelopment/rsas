import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../datos/catalogos.dart';
import '../../datos/repositorio_catalogos.dart';
import '../../utils/formatters.dart';
import '../../utils/municipios.dart';
import '../theme/app_layout.dart';
import '../widgets/section_card.dart';
import '../../utils/mensajes_error.dart';

/// Agrega los puntos de miles al documento mientras se escribe, igual que
/// los campos de plata — el guion del dígito de verificación de NIT (si lo
/// hay) se deja tal cual, sin agruparle puntos a lo que viene después.
class _DocInputFormatter extends TextInputFormatter {
  /// CC y NIT: solo dígitos (y el guion del dígito de verificación), con
  /// puntos de miles. Pasaporte, CE y otros: letras y dígitos tal cual
  /// (antes las letras se borraban y no se podía escribir un pasaporte).
  final bool soloNumerico;
  const _DocInputFormatter({this.soloNumerico = true});

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (!soloNumerico) {
      final t =
          newValue.text.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z\-]'), '');
      return newValue.copyWith(
        text: t,
        selection: TextSelection.collapsed(offset: t.length),
      );
    }
    final limpio = newValue.text.replaceAll(RegExp(r'[^0-9\-]'), '');
    if (limpio.isEmpty) return newValue.copyWith(text: '');

    final guionIdx = limpio.indexOf('-');
    final numero = guionIdx == -1 ? limpio : limpio.substring(0, guionIdx);
    final sufijo = guionIdx == -1 ? '' : limpio.substring(guionIdx);

    final buf = StringBuffer();
    for (var i = 0; i < numero.length; i++) {
      if (i > 0 && (numero.length - i) % 3 == 0) buf.write('.');
      buf.write(numero[i]);
    }
    final resultado = '$buf$sufijo';

    return newValue.copyWith(
      text: resultado,
      selection: TextSelection.collapsed(offset: resultado.length),
    );
  }
}

class FormCliente extends StatefulWidget {
  final Cliente? cliente;
  const FormCliente({super.key, this.cliente});

  @override
  State<FormCliente> createState() => _FormClienteState();
}

class _FormClienteState extends State<FormCliente> {
  final _formKey = GlobalKey<FormState>();
  final repo = RepositorioCatalogos();

  bool guardando = false;
  bool cargandoMunicipios = true;
  bool cargandoId = true;
  bool cargandoAsesores = true;

  late final TextEditingController idCtrl;
  late final TextEditingController nombreCtrl;
  late final TextEditingController docCtrl;
  late final TextEditingController telCtrl;
  late final TextEditingController correoCtrl;
  late final TextEditingController dirCtrl;
  late final TextEditingController notasCtrl;
  late final TextEditingController contactoCtrl;
  late final TextEditingController cargocontCtrl;

  static const List<String> tiposDocNormalizados = [
    'CC',
    'CE',
    'NIT',
    'PAS',
    'OTRO'
  ];

  bool get _docNumerico =>
      tipoDocSel == null || tipoDocSel == 'CC' || tipoDocSel == 'NIT';

  String? tipoDocSel;
  String tipopersSel = 'N';

  List<Municipio> municipios = [];
  int? municIdSel;

  List<Asesor> asesores = [];
  int? asesorIdSel;

  bool estadoCliente = true;
  bool recordarCliente = false;

  bool get esEdicion => widget.cliente != null;

  @override
  void initState() {
    super.initState();

    idCtrl = TextEditingController(
      text: esEdicion ? widget.cliente!.id.toString() : '',
    );
    nombreCtrl =
        TextEditingController(text: widget.cliente?.nombreCliente ?? '');
    docCtrl = TextEditingController(text: Fmt.doc(widget.cliente?.docCliente));
    telCtrl = TextEditingController(text: widget.cliente?.telCliente ?? '');
    correoCtrl =
        TextEditingController(text: widget.cliente?.correoCliente ?? '');
    dirCtrl = TextEditingController(text: widget.cliente?.dirCliente ?? '');
    notasCtrl = TextEditingController(text: widget.cliente?.notasCliente ?? '');
    contactoCtrl =
        TextEditingController(text: widget.cliente?.contactoCliente ?? '');
    cargocontCtrl =
        TextEditingController(text: widget.cliente?.cargocontCliente ?? '');

    tipoDocSel = widget.cliente?.tipodocCliente;
    tipopersSel = widget.cliente?.tipopersCliente ?? 'N';
    municIdSel = widget.cliente?.municId;
    asesorIdSel = widget.cliente?.asesorId;
    estadoCliente = widget.cliente?.estadoCliente ?? true;
    recordarCliente = widget.cliente?.recordarCliente ?? false;

    _cargarMunicipios();
    _cargarAsesores();
    cargandoId = false;
  }

  Future<void> _cargarMunicipios() async {
    try {
      final res = await repo.listarMunicipios();
      if (!mounted) return;
      setState(() {
        municipios = res;
        cargandoMunicipios = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => cargandoMunicipios = false);
      _toast(mensajeAmigable(e, accion: 'Error cargando municipios'));
    }
  }

  Future<void> _cargarAsesores() async {
    try {
      final res = await repo.listarAsesores(soloActivos: true);
      if (!mounted) return;
      setState(() {
        asesores = res;
        cargandoAsesores = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => cargandoAsesores = false);
    }
  }

  @override
  void dispose() {
    idCtrl.dispose();
    nombreCtrl.dispose();
    docCtrl.dispose();
    telCtrl.dispose();
    correoCtrl.dispose();
    dirCtrl.dispose();
    notasCtrl.dispose();
    contactoCtrl.dispose();
    cargocontCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _validarCorreo(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    final ok = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s);
    return ok ? null : 'Correo inválido';
  }

  String? _limpiarONull(String v) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _guardar() async {
    if (guardando) return;

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    // Se guarda sin puntos — el campo solo los muestra para que sea más
    // fácil de leer mientras se digita (ver fix_doc_cliente_sin_puntos.sql).
    final doc = _limpiarONull(docCtrl.text.replaceAll('.', ''));
    if (doc != null && (tipoDocSel == null || tipoDocSel!.trim().isEmpty)) {
      _toast('Seleccione el tipo de documento.');
      return;
    }

    // "guardando" se marca antes de la verificación: con doble clic se
    // hacían dos verificaciones, las dos pasaban y se creaban dos clientes.
    setState(() => guardando = true);

    try {
      if (doc != null) {
        final existe = await repo.existeDocCliente(
          tipoDocSel,
          doc,
          excluirId: esEdicion ? widget.cliente!.id : null,
        );
        if (existe) {
          _toast('Ya existe un cliente con ese tipo y número de documento.');
          return;
        }
      }

      if (esEdicion) {
        final c = Cliente(
          id: widget.cliente!.id,
          nombreCliente: nombreCtrl.text.trim(),
          tipopersCliente: tipopersSel,
          tipodocCliente:
              (tipoDocSel?.trim().isEmpty ?? true) ? null : tipoDocSel!.trim(),
          docCliente: doc,
          telCliente: _limpiarONull(telCtrl.text),
          correoCliente: _limpiarONull(correoCtrl.text),
          dirCliente: _limpiarONull(dirCtrl.text),
          municId: municIdSel,
          notasCliente: _limpiarONull(notasCtrl.text),
          contactoCliente: _limpiarONull(contactoCtrl.text),
          cargocontCliente: _limpiarONull(cargocontCtrl.text),
          asesorId: asesorIdSel,
          estadoCliente: estadoCliente,
          recordarCliente: recordarCliente,
        );
        await repo.actualizarCliente(widget.cliente!.id, c);
        if (!mounted) return;
        Navigator.pop(context, widget.cliente!.id);
      } else {
        // El id que trae este objeto se ignora al insertar (toInsertMap()
        // no lo incluye) — lo asigna la base sola.
        final cNuevo = Cliente(
          id: 0,
          nombreCliente: nombreCtrl.text.trim(),
          tipopersCliente: tipopersSel,
          tipodocCliente:
              (tipoDocSel?.trim().isEmpty ?? true) ? null : tipoDocSel!.trim(),
          docCliente: doc,
          telCliente: _limpiarONull(telCtrl.text),
          correoCliente: _limpiarONull(correoCtrl.text),
          dirCliente: _limpiarONull(dirCtrl.text),
          municId: municIdSel,
          notasCliente: _limpiarONull(notasCtrl.text),
          contactoCliente: _limpiarONull(contactoCtrl.text),
          cargocontCliente: _limpiarONull(cargocontCtrl.text),
          asesorId: asesorIdSel,
          estadoCliente: estadoCliente,
          recordarCliente: recordarCliente,
        );
        final nuevoId = await repo.crearCliente(cNuevo);
        if (!mounted) return;
        // Recién acá se conoce el código real — antes de guardar no se
        // muestra ningún preview, para que no queden códigos anotados a
        // mano que después no coinciden si otra persona guardó primero.
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Cliente guardado'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Código: $nuevoId',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 20)),
                const SizedBox(height: 8),
                Text('Cliente: ${cNuevo.nombreCliente}'),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Listo'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        Navigator.pop(context, nuevoId);
      }
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
    final municipioInicial = widget.cliente?.nombreMunicipio ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(esEdicion ? 'Editar cliente' : 'Nuevo cliente'),
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
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'ID',
                        border: const OutlineInputBorder(),
                        helperText: esEdicion ? null : 'Se asigna al guardar',
                      ),
                    ),
                    TextFormField(
                      controller: nombreCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Tipo persona + Tipo doc + Documento. En pantallas angostas
                  // (móvil) el documento pasa a su propia fila.
                  LayoutBuilder(builder: (context, caja) {
                    final angosto = caja.maxWidth < 560;
                    final persona = DropdownButtonFormField<String>(
                      value: tipopersSel,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Tipo persona',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'N', child: Text('Natural')),
                        DropdownMenuItem(value: 'J', child: Text('Jurídica')),
                      ],
                      onChanged: (v) => setState(() => tipopersSel = v ?? 'N'),
                    );
                    final tipoDoc = DropdownButtonFormField<String>(
                      value: tiposDocNormalizados.contains(tipoDocSel)
                          ? tipoDocSel
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Tipo documento',
                        border: OutlineInputBorder(),
                      ),
                      items: tiposDocNormalizados
                          .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) => setState(() => tipoDocSel = v),
                    );
                    final documento = TextFormField(
                      controller: docCtrl,
                      keyboardType: _docNumerico
                          ? TextInputType.number
                          : TextInputType.text,
                      inputFormatters: [
                        _DocInputFormatter(soloNumerico: _docNumerico)
                      ],
                      decoration: InputDecoration(
                        labelText: 'Documento',
                        border: const OutlineInputBorder(),
                        helperText:
                            _docNumerico ? 'Los puntos se agregan solos' : null,
                      ),
                    );
                    if (angosto) {
                      return Column(children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: persona),
                            const SizedBox(width: 12),
                            Expanded(child: tipoDoc),
                          ],
                        ),
                        const SizedBox(height: 12),
                        documento,
                      ]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 130, child: persona),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: tipoDoc),
                        const SizedBox(width: 12),
                        Expanded(flex: 3, child: documento),
                      ],
                    );
                  }),
                  const SizedBox(height: 12),
                  Autocomplete<Municipio>(
                    initialValue: TextEditingValue(text: municipioInicial),
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      final query = normalizarTexto(textEditingValue.text);
                      if (query.isEmpty) return municipios.take(20);
                      return municipios
                          .where((m) =>
                              normalizarTexto(m.nombreMunic).contains(query))
                          .take(40);
                    },
                    displayStringForOption: (Municipio m) => m.nombreMunic,
                    onSelected: (Municipio m) =>
                        setState(() => municIdSel = m.id),
                    fieldViewBuilder: (context, textEditingController,
                        focusNode, onFieldSubmitted) {
                      if (municipioInicial.isNotEmpty &&
                          textEditingController.text.isEmpty) {
                        textEditingController.text = municipioInicial;
                      }
                      return TextFormField(
                        controller: textEditingController,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: 'Municipio',
                          border: const OutlineInputBorder(),
                          suffixIcon: cargandoMunicipios
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                )
                              : const Icon(Icons.search),
                        ),
                        validator: (_) {
                          final texto = textEditingController.text.trim();
                          if (texto.isEmpty) return null;
                          // No eligió de la lista: se intenta resolver por el
                          // texto escrito antes de dar el error.
                          municIdSel ??=
                              resolverMunicipio(municipios, texto)?.id;
                          if (municIdSel == null) {
                            return 'Elija el municipio de la lista (puede haber varios con ese nombre)';
                          }
                          return null;
                        },
                        onChanged: (value) {
                          final nuevo =
                              resolverMunicipio(municipios, value)?.id;
                          if (nuevo != municIdSel) {
                            setState(() => municIdSel = nuevo);
                          }
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: asesores.any((a) => a.id == asesorIdSel)
                        ? asesorIdSel
                        : null,
                    decoration: InputDecoration(
                      labelText: 'Asesor asignado',
                      border: const OutlineInputBorder(),
                      suffixIcon: cargandoAsesores
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('— Sin asesor —')),
                      ...asesores.map((a) => DropdownMenuItem(
                            value: a.id,
                            child: Text(a.nombreAsesor,
                                overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (v) => setState(() => asesorIdSel = v),
                  ),
                ]),

                // ── 2. Contacto ──────────────────────────────────────────────
                _seccion('Contacto', [
                  _fila2(
                    TextFormField(
                      controller: telCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: correoCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validarCorreo,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: dirCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Dirección',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _fila2(
                    TextFormField(
                      controller: contactoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Persona de contacto',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: cargocontCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Cargo del contacto',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ]),

                // ── 3. Notas y estado ────────────────────────────────────────
                _seccion('Notas y estado', [
                  TextFormField(
                    controller: notasCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Notas / Observaciones',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: estadoCliente,
                    onChanged: (v) => setState(() => estadoCliente = v),
                    title: const Text('Cliente activo'),
                    subtitle: Text(estadoCliente ? 'Activo' : 'Inactivo'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    value: recordarCliente,
                    onChanged: (v) => setState(() => recordarCliente = v),
                    title: const Text('Recordar cliente'),
                    subtitle: const Text('Marcar para seguimiento especial'),
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
                    child: Text(guardando ? 'Guardando...' : 'Guardar cliente'),
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
