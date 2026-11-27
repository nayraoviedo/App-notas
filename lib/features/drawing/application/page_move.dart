import '../domain/drawing.dart';

/// Historial de deshacer de una hoja que no está abierta:
/// (pasos para deshacer, pasos para rehacer, cómo está ahora).
typedef PageHistory = (List<Drawing>, List<Drawing>, Drawing);

/// Lo último que se pasó con el lazo de una hoja a otra. Al pasar algo, se
/// quita de la hoja [from] y se pone en [to]; cada hoja guarda su paso en su
/// propio deshacer. Si en [to] se toca "deshacer" justo después, también hay
/// que devolverlo a [from]: si no, desaparece de las dos.
class PageMove {
  const PageMove({required this.from, required this.to, required this.after, required this.before});

  final String from;
  final String to;

  /// Cómo quedó la hoja [to] justo después de recibir lo pasado.
  final Drawing after;

  /// Cómo estaba la hoja [to] antes de recibirlo.
  final Drawing before;
}

/// Deshace el último paso de una hoja cerrada: devuelve lo que hay que
/// guardar en su archivo y su historial nuevo, o null si no hay nada.
(Drawing, PageHistory)? undoClosedPage(PageHistory h) {
  final (u, r, at) = h;
  if (u.isEmpty) return null;
  final prev = u.last;
  return (prev, (u.sublist(0, u.length - 1), [...r, at], prev));
}

/// Rehace el último paso deshecho de una hoja cerrada.
(Drawing, PageHistory)? redoClosedPage(PageHistory h) {
  final (u, r, at) = h;
  if (r.isEmpty) return null;
  final next = r.last;
  return (next, ([...u, at], r.sublist(0, r.length - 1), next));
}
