import 'package:app_notas/features/drawing/domain/canvas_item.dart';
import 'package:app_notas/features/drawing/presentation/widgets/table_equation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tabla y ecuación se guardan dentro de la imagen y se vuelven a leer', () {
    final t = TableData.empty(2, 3).resized(3, 2);
    expect((t.rows, t.cols), (3, 2));
    final back = decodeSource(TableData(cells: const [['A', 'B'], ['1', '2']], color: 0xFF112233).encode());
    expect(back, isA<TableData>());
    expect((back! as TableData).cells[1][1], '2');

    final eq = decodeSource(const EquationData(r'\frac{a}{b}').encode());
    expect((eq! as EquationData).tex, r'\frac{a}{b}');
    expect(decodeSource(null), isNull);
    expect(decodeSource('basura'), isNull);

    const item = ImageItem(id: 'i', x: 1, y: 2, path: 'p.png', width: 10, height: 5, source: '{"kind":"eq"}');
    final again = CanvasItem.fromJson(item.toJson())! as ImageItem;
    expect(again.source, '{"kind":"eq"}');
    expect(item.moved(x: 3).source, '{"kind":"eq"}');
  });
}
