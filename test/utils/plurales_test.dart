import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento_polizas/utils/plurales.dart';

void main() {
  test('plural usa singular solo con 1', () {
    expect(plural(1, 'póliza', 'pólizas'), '1 póliza');
    expect(plural(0, 'póliza', 'pólizas'), '0 pólizas');
    expect(plural(3, 'pago', 'pagos'), '3 pagos');
    expect(palabraPlural(1, 'eliminada', 'eliminadas'), 'eliminada');
    expect(palabraPlural(2, 'eliminada', 'eliminadas'), 'eliminadas');
  });
}
