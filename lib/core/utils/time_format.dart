/// Formatea milisegundos como `mm:ss` o `h:mm:ss`.
String formatMs(int ms) {
  final total = Duration(milliseconds: ms);
  final h = total.inHours;
  final m = total.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = total.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
