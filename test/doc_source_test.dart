import 'package:app_notas/features/reader/data/doc_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Google Slides se baja como PDF', () {
    final u = googleExportUrl(Uri.parse(
        'https://docs.google.com/presentation/d/1AbCdEfGhIjKlMnOpQrStUvWxYz_-123/edit?usp=sharing#slide=id.p'));
    expect(u.toString(), 'https://docs.google.com/presentation/d/1AbCdEfGhIjKlMnOpQrStUvWxYz_-123/export/pdf');
  });

  test('Google Docs y Drive', () {
    expect(googleExportUrl(Uri.parse('https://docs.google.com/document/d/1AbCdEfGhIjK/edit')).toString(),
        'https://docs.google.com/document/d/1AbCdEfGhIjK/export?format=pdf');
    expect(googleExportUrl(Uri.parse('https://drive.google.com/file/d/1AbCdEfGhIjK/view?usp=drive_link')).toString(),
        'https://drive.google.com/uc?export=download&id=1AbCdEfGhIjK');
  });

  test('otros enlaces se bajan tal cual', () {
    expect(googleExportUrl(Uri.parse('https://example.com/clase.pdf')), isNull);
  });
}
