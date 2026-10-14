import 'package:flutter/material.dart';
import '../../datos/catalogos.dart';
import '../../utils/numeros_co.dart';
import '../../datos/repositorio_catalogos.dart';
import '../theme/app_layout.dart';
import '../widgets/section_card.dart';
import '../../utils/mensajes_error.dart';

class FormProducto extends StatefulWidget {
  final Producto? producto;
  const FormProducto({super.key, this.producto});

  @override
  State<FormProducto> createState() => _FormProductoState();
}

class _FormProductoState extends State<FormProducto> {
  final _formKey = GlobalKey<FormState>();
  final repo = RepositorioCatalogos();

  bool cargando = true;
  bool guardando = false;
  bool cargandoId = true;

  late final TextEditingController idCtrl;
  late final TextEditingController nombreCtrl;
  late final TextEditingController comisionCtrl;
  late final TextEditingController porcomCtrl;
  late final TextEditingController descCtrl;
  late final TextEditingController porcadCtrl;
  late final TextEditingController obsCtrl;

  List<Ramo> ramos = [];
  List<Aseguradora> aseguradoras = [];

  Ramo? ramoSel;
  Aseguradora? asegSel;

  bool estadoProd = true;

  bool get esEdicion => widget.producto != null;

  @override
  void initState() {
    super.initState();

    final p = widget.producto;

    idCtrl = TextEditingController(
      text: esEdicion ? widget.producto!.id.toString() : '',
    );
    nombreCtrl = TextEditingController(text: p?.nombreProd ?? '');
    estadoProd = p?.estadoProd ?? true;

    comisionCtrl = TextEditingController(text: _numToText(p?.comisionProd));
    porcomCtrl = TextEditingController(text: _numToText(p?.porcomProd));
    descCtrl = TextEditingController(text: p?.descProd ?? '');
    porcadCtrl = TextEditingController(text: _numToText(p?.porcadProd));
    obsCtrl = TextEditingController(text: p?.obsProd ?? '');

    _cargar();
  }

  @override
  void dispose() {
    idCtrl.dispose();
    nombreCtrl.dispose();
    comisionCtrl.dispose();
    porcomCtrl.dispose();
    descCtrl.dispose();
    porcadCtrl.dispose();
    obsCtrl.dispose();
    super.dispose();
  }

  String _numToText(num? n) => n == null ? '' : n.toString();

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

  String? _validarNumeroOpcional(String? v) {
    if ((v ?? '').trim().isEmpty) return null;
    return parseNumCO(v) == null ? 'Valor inválido' : null;
  }

  Future<void> _cargar() async {
    try {
      final resultados = await Future.wait([
        repo.listarRamos(),
        repo.listarAseguradoras(),
        if (!esEdicion) repo.obtenerSiguienteIdProducto(),
      ]);

      ramos = resultados[0] as List<Ramo>;
      aseguradoras = resultados[1] as List<Aseguradora>;

      if (esEdicion) {
        final p = widget.producto!;
        final rOk = ramos.any((r) => r.id == p.ramoId);
        ramoSel = rOk ? ramos.firstWhere((r) => r.id == p.ramoId) : null;
        final aOk = aseguradoras.any((a) => a.id == p.aseguradoraId);
        asegSel =
            aOk ? aseguradoras.firstWhere((a) => a.id == p.aseguradoraId) : null;
        cargandoId = false;
      } else {
        final nextId = resultados[2] as int;
        idCtrl.text = nextId.toString();
        cargandoId = false;
      }

      if (!mounted) return;
      setState(() => cargando = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        cargando = false;
        cargandoId = false;
      });
      _toast(mensajeAmigable(e, accion: 'Error cargando catálogos'));
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _guardar() async {
    if (guardando) return;

    FocusScope.of(context).unfocus();

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    if (ramoSel == null) {
      _toast('Selecciona un ramo válido.');
      return;
    }
    if (asegSel == null) {
      _toast('Selecciona una aseguradora válida.');
      return;
    }

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

    setState(() => guardando = true);

    try {
      final p = Producto(
        id: esEdicion ? widget.producto!.id : idNum,
        nombreProd: nombre,
        ramoId: ramoSel!.id,
        aseguradoraId: asegSel!.id,
        estadoProd: estadoProd,
        comisionProd: _parseNumeroONull(comisionCtrl.text),
        porcomProd: _parseNumeroONull(porcomCtrl.text),
        descProd: _limpiarONull(descCtrl.text),
        porcadProd: _parseNumeroONull(porcadCtrl.text),
        obsProd: _limpiarONull(obsCtrl.text),
      );

      if (esEdicion) {
        await repo.actualizarProducto(widget.producto!.id, p);
      } else {
        await repo.crearProducto(p);
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

  Widget _fila3(Widget a, Widget b, Widget c) {
    final w = MediaQuery.of(context).size.width;
    if (w < 900) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          a,
          const SizedBox(height: 12),
          b,
          const SizedBox(height: 12),
          c,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 16),
        Expanded(child: b),
        const SizedBox(width: 16),
        Expanded(child: c),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final ramoInicial = ramoSel?.nombreRamo ?? '';
    final asegInicial = asegSel?.nombreAseg ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(esEdicion ? 'Editar producto' : 'Nuevo producto'),
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
          constraints: const BoxConstraints(maxWidth: 820),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
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
                        labelText: 'Nombre del producto *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final limpio = _limpiarONull(v ?? '');
                        return limpio == null ? 'Requerido' : null;
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _fila2(
                    Autocomplete<Ramo>(
                      initialValue: TextEditingValue(text: ramoInicial),
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        final query =
                            textEditingValue.text.trim().toLowerCase();
                        if (query.isEmpty) return ramos.take(20);
                        return ramos
                            .where((r) =>
                                r.nombreRamo.toLowerCase().contains(query) ||
                                r.id.toString().contains(query))
                            .take(20);
                      },
                      displayStringForOption: (Ramo r) => r.nombreRamo,
                      onSelected: (Ramo r) => setState(() => ramoSel = r),
                      fieldViewBuilder: (
                        context,
                        textEditingController,
                        focusNode,
                        onFieldSubmitted,
                      ) {
                        if (ramoInicial.isNotEmpty &&
                            textEditingController.text.isEmpty) {
                          textEditingController.text = ramoInicial;
                        }
                        return TextFormField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Ramo *',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.search),
                          ),
                          validator: (_) {
                            final texto = textEditingController.text.trim();
                            if (texto.isEmpty) return 'Requerido';
                            if (ramoSel == null) {
                              return 'Selecciona un ramo válido';
                            }
                            return null;
                          },
                          onChanged: (value) {
                            final query = value.trim().toLowerCase();
                            Ramo? exacto;
                            for (final r in ramos) {
                              if (r.nombreRamo.toLowerCase() == query ||
                                  r.id.toString() == query) {
                                exacto = r;
                                break;
                              }
                            }
                            setState(() => ramoSel = exacto);
                          },
                        );
                      },
                    ),
                    Autocomplete<Aseguradora>(
                      initialValue: TextEditingValue(text: asegInicial),
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        final query =
                            textEditingValue.text.trim().toLowerCase();
                        if (query.isEmpty) return aseguradoras.take(20);
                        return aseguradoras
                            .where((a) =>
                                a.nombreAseg.toLowerCase().contains(query) ||
                                a.id.toString().contains(query))
                            .take(20);
                      },
                      displayStringForOption: (Aseguradora a) => a.nombreAseg,
                      onSelected: (Aseguradora a) =>
                          setState(() => asegSel = a),
                      fieldViewBuilder: (
                        context,
                        textEditingController,
                        focusNode,
                        onFieldSubmitted,
                      ) {
                        if (asegInicial.isNotEmpty &&
                            textEditingController.text.isEmpty) {
                          textEditingController.text = asegInicial;
                        }
                        return TextFormField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Aseguradora *',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.search),
                          ),
                          validator: (_) {
                            final texto = textEditingController.text.trim();
                            if (texto.isEmpty) return 'Requerido';
                            if (asegSel == null) {
                              return 'Selecciona una aseguradora válida';
                            }
                            return null;
                          },
                          onChanged: (value) {
                            final query = value.trim().toLowerCase();
                            Aseguradora? exacto;
                            for (final a in aseguradoras) {
                              if (a.nombreAseg.toLowerCase() == query ||
                                  a.id.toString() == query) {
                                exacto = a;
                                break;
                              }
                            }
                            setState(() => asegSel = exacto);
                          },
                        );
                      },
                    ),
                  ),
                ]),

                // ── 2. Comisiones ────────────────────────────────────────────
                _seccion('Comisiones', [
                  _fila3(
                    TextFormField(
                      controller: comisionCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Comisión fija',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validarNumeroOpcional,
                    ),
                    TextFormField(
                      controller: porcomCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '% Comisión',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validarPorcentaje,
                    ),
                    TextFormField(
                      controller: porcadCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '% Comisión adicional',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validarPorcentaje,
                    ),
                  ),
                ]),

                // ── 3. Descripción ───────────────────────────────────────────
                _seccion('Descripción', [
                  TextFormField(
                    controller: descCtrl,
                    maxLines: 2,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Descripción',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: obsCtrl,
                    maxLines: 2,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Observaciones',
                      border: OutlineInputBorder(),
                    ),
                    onFieldSubmitted: (_) => guardando ? null : _guardar(),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    value: estadoProd,
                    onChanged: (v) => setState(() => estadoProd = v),
                    title: const Text('Activo'),
                    subtitle: Text(estadoProd ? 'Activo' : 'Inactivo'),
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
                    child:
                        Text(guardando ? 'Guardando...' : 'Guardar producto'),
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
