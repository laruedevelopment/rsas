/// Meta mensual de un indicador, para toda la agencia ([asesorId] = 0) o
/// para un asesor. Ver supabase/migrations/20261005090000_metas_comerciales.sql.
class Meta {
  final int anio;
  final int mes;
  final String indicador;
  final int asesorId;
  final num valor;

  const Meta({
    required this.anio,
    required this.mes,
    required this.indicador,
    this.asesorId = 0,
    required this.valor,
  });

  factory Meta.fromMap(Map<String, dynamic> m) => Meta(
        anio: (m['anio'] as num).toInt(),
        mes: (m['mes'] as num).toInt(),
        indicador: m['indicador'].toString(),
        asesorId: (m['asesor_id'] as num?)?.toInt() ?? 0,
        valor: num.tryParse(m['valor'].toString()) ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'anio': anio,
        'mes': mes,
        'indicador': indicador,
        'asesor_id': asesorId,
        'valor': valor,
      };
}

/// Indicadores con meta. `monetario` decide cómo se muestran los valores.
class IndicadorMeta {
  final String clave;
  final String nombre;
  final bool monetario;
  final bool soloComisiones;
  const IndicadorMeta(this.clave, this.nombre,
      {this.monetario = true, this.soloComisiones = false});
}

const List<IndicadorMeta> kIndicadoresMeta = [
  IndicadorMeta('prima', 'Prima emitida'),
  IndicadorMeta('polizas', 'Pólizas emitidas', monetario: false),
  IndicadorMeta('comision', 'Comisión recibida', soloComisiones: true),
  IndicadorMeta('recaudo', 'Recaudo de prima', soloComisiones: true),
];
