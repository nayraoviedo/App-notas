import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/platform_info.dart';
import '../../../core/providers.dart';
import '../../drawing/domain/drawing.dart';
import '../../drawing/presentation/drawing_screen.dart';
import '../../notes/domain/note_block.dart';
import '../../notes/presentation/widgets/text_block_view.dart';
import '../../settings/settings.dart';
import '../data/doc_pages.dart';
import 'doc_chooser.dart';

/// Ver un PDF, diapositivas u otro documento y escribir en el cuaderno al
/// mismo tiempo (como "Video y notas").
///
/// - Arriba (o a la izquierda en la compu) el documento, página por página.
/// - Abajo (o a la derecha) la Hoja del cuaderno y los Apuntes.
/// - La raya del medio se arrastra para dar más espacio a uno u otro.
/// - "Al cuaderno" copia la página que se ve como hoja nueva, para escribir encima.
class DocNotesScreen extends ConsumerStatefulWidget {
  const DocNotesScreen({super.key, required this.noteId, required this.docPath});

  final String noteId;
  final String docPath;

  @override
  ConsumerState<DocNotesScreen> createState() => _DocNotesScreenState();
}

class _DocNotesScreenState extends ConsumerState<DocNotesScreen> with SingleTickerProviderStateMixin {
  late String _docPath = widget.docPath;
  final _pages = <DocPage>[];
  StreamSubscription<DocPage>? _sub;
  bool _rendering = true;
  String? _error;

  final _scroll = ScrollController();
  double _zoom = 1;
  int _page = 0; // la página que se ve (desde 0)
  double _viewWidth = 1;
  int? _restorePage;

  late final _tabs = TabController(length: 2, vsync: this)..addListener(() => setState(() {}));
  final _aText = TextEditingController();
  String? _sheetPath; // hoja elegida a mano (por ejemplo una página copiada)
  bool _creating = false;
  double? _split;

  String get _docKey => p.basenameWithoutExtension(_docPath);
  String get _apuntesKey => 'doc.apuntes.$_docKey';
  String get _pageKey => 'doc.page.$_docKey';
  static const _splitKey = 'doc.split';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _openDoc();
  }

  void _openDoc() {
    _sub?.cancel();
    final prefs = ref.read(sharedPreferencesProvider);
    rememberRecentDoc(prefs, widget.noteId, _docPath);
    _pages.clear();
    _page = 0;
    _rendering = true;
    _error = null;
    _restorePage = prefs.getInt(_pageKey);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _sub = docPages(_docPath).listen(
      (pg) {
        if (!mounted) return;
        setState(() => _pages.add(pg));
        final r = _restorePage;
        if (r != null && r > 0 && _pages.length == r + 1) {
          _restorePage = null;
          WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(r, animate: false));
        }
      },
      onError: (Object e) {
        if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
      },
      onDone: () {
        if (mounted) setState(() => _rendering = false);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    _tabs.dispose();
    _aText.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ Documento

  static const _gap = 10.0;
  double _pageWidth() => (_viewWidth - 16) * _zoom;
  double _extent(int i) => _pageWidth() * _pages[i].ratio + _gap;

  void _onScroll() {
    if (_pages.isEmpty) return;
    // La página que ocupa el centro de la vista.
    final mid = _scroll.offset + _scroll.position.viewportDimension / 3;
    var y = 0.0;
    var i = 0;
    for (; i < _pages.length - 1; i++) {
      y += _extent(i);
      if (y > mid) break;
    }
    if (i != _page) {
      setState(() => _page = i);
      ref.read(sharedPreferencesProvider).setInt(_pageKey, i);
    }
  }

  void _goTo(int i, {bool animate = true}) {
    if (_pages.isEmpty || !_scroll.hasClients) return;
    i = i.clamp(0, _pages.length - 1);
    var y = 0.0;
    for (var k = 0; k < i; k++) {
      y += _extent(k);
    }
    y = y.clamp(0.0, _scroll.position.maxScrollExtent);
    animate
        ? _scroll.animateTo(y, duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
        : _scroll.jumpTo(y);
    setState(() => _page = i);
  }

  void _setZoom(double z) {
    final keep = _page;
    setState(() => _zoom = z.clamp(1.0, 3.0));
    WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(keep, animate: false));
  }

  Future<void> _changeDoc() async {
    final path = await chooseDocument(context, ref, noteId: widget.noteId);
    if (path == null || !mounted) return;
    setState(() {
      _docPath = path;
      _openDoc();
    });
  }

  /// La página que se ve, como hoja nueva del cuaderno (para escribir encima).
  Future<void> _pageToNotebook() async {
    if (_pages.isEmpty) return;
    final pg = _pages[_page];
    final path = await ref.read(importServiceProvider).addPageImage(widget.noteId, pg.path, pg.width, pg.height);
    if (!mounted) return;
    setState(() => _sheetPath = path);
    _tabs.animateTo(0);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Página ${_page + 1} copiada como hoja nueva: ya puedes escribir encima')));
  }

  Widget _docView() {
    final scheme = Theme.of(context).colorScheme;
    Widget body;
    if (_error != null && _pages.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No se pudo abrir el documento.\n$_error', textAlign: TextAlign.center),
        ),
      );
    } else if (_pages.isEmpty) {
      body = const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 10),
          Text('Abriendo el documento…'),
        ]),
      );
    } else {
      body = LayoutBuilder(builder: (context, c) {
        _viewWidth = c.maxWidth;
        final list = ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          itemCount: _pages.length,
          itemExtentBuilder: (i, _) => i < _pages.length ? _extent(i) : null,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: _gap),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4)],
              ),
              child: Image.file(File(_pages[i].path), fit: BoxFit.fill, filterQuality: FilterQuality.medium),
            ),
          ),
        );
        if (_zoom == 1) return list;
        // Con lupa: la página es más ancha que la vista y se mueve de lado.
        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: _pageWidth() + 16, height: c.maxHeight, child: list),
          ),
        );
      });
    }
    final n = _pages.length;
    final bar = Material(
      color: scheme.surfaceContainerHigh,
      child: SizedBox(
        height: 44,
        child: Row(children: [
          IconButton(
            tooltip: 'Página anterior',
            onPressed: _page > 0 ? () => _goTo(_page - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          InkWell(
            onTap: n > 1 ? _askPage : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(n == 0 ? '…' : '${_page + 1} / $n${_rendering ? '…' : ''}'),
            ),
          ),
          IconButton(
            tooltip: 'Página siguiente',
            onPressed: _page < n - 1 ? () => _goTo(_page + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Alejar',
            onPressed: _zoom > 1 ? () => _setZoom(_zoom - 0.5) : null,
            icon: const Icon(Icons.zoom_out),
          ),
          IconButton(
            tooltip: 'Acercar',
            onPressed: _zoom < 3 ? () => _setZoom(_zoom + 0.5) : null,
            icon: const Icon(Icons.zoom_in),
          ),
          if (_viewWidth < 460)
            IconButton(
              tooltip: 'Copiar esta página al cuaderno (para escribir encima)',
              onPressed: n == 0 ? null : _pageToNotebook,
              icon: const Icon(Icons.note_add_outlined),
            )
          else
            TextButton.icon(
              onPressed: n == 0 ? null : _pageToNotebook,
              icon: const Icon(Icons.note_add_outlined, size: 20),
              label: const Text('Al cuaderno'),
            ),
        ]),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _goTo(_page + 1),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _goTo(_page - 1),
      },
      child: Focus(
        child: ColoredBox(
          color: scheme.surfaceContainerLow,
          child: Column(children: [Expanded(child: body), bar]),
        ),
      ),
    );
  }

  Future<void> _askPage() async {
    final c = TextEditingController(text: '${_page + 1}');
    final v = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ir a la página'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          onSubmitted: (s) => Navigator.pop(context, int.tryParse(s)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, int.tryParse(c.text)), child: const Text('Ir')),
        ],
      ),
    );
    if (v != null) _goTo(v - 1);
  }

  // ------------------------------------------------------------- Apuntes

  TextBlock? _apuntes(List<NoteBlock> blocks) {
    final id = ref.read(sharedPreferencesProvider).getString(_apuntesKey);
    return blocks.whereType<TextBlock>().where((b) => b.id == id).firstOrNull;
  }

  /// Envía un apunte: se agrega como "[pág. 3] texto".
  Future<void> _sendApunte() async {
    final text = _aText.text.trim();
    if (text.isEmpty) return;
    final repo = ref.read(notesRepositoryProvider);
    final block = _apuntes(ref.read(blocksProvider(widget.noteId)).valueOrNull ?? const []);
    String id;
    var current = '';
    if (block == null) {
      id = await repo.addTextBlock(widget.noteId);
      await ref.read(sharedPreferencesProvider).setString(_apuntesKey, id);
    } else {
      id = block.id;
      current = block.text.trimRight();
    }
    final line = '[pág. ${_page + 1}] $text';
    await repo.updateText(id, current.isEmpty ? line : '$current\n$line');
    _aText.clear();
    if (mounted) setState(() {});
  }

  Future<void> _createSheet() async {
    if (_creating) return;
    _creating = true;
    final path = await ref.read(fileStorageProvider).newDrawingPath();
    await ref
        .read(drawingStoreProvider)
        .save(path, Drawing.blank(paper: const PaperStyle(template: PaperTemplate.lined)));
    await ref.read(notesRepositoryProvider).addDrawingBlock(widget.noteId, path);
    _creating = false;
  }

  Widget _panel(List<NoteBlock> blocks) {
    final sheets = blocks.whereType<DrawingBlock>().toList();
    final firstIsCover = sheets.isNotEmpty &&
        ref.watch(drawingFileProvider(sheets.first.path)).valueOrNull?.paper.template == PaperTemplate.cover;
    final chosen = sheets.where((s) => s.path == _sheetPath).firstOrNull;
    final sheet = chosen ?? (firstIsCover && sheets.length > 1 ? sheets[1] : sheets.firstOrNull);

    final sheetTab = sheet == null
        ? Center(
            child: FilledButton.icon(
              onPressed: _createSheet,
              icon: const Icon(Icons.draw_outlined),
              label: const Text('Crear hoja para escribir a mano'),
            ),
          )
        : DrawingScreen(key: ValueKey(sheet.path), noteId: widget.noteId, path: sheet.path, embedded: true);

    final apuntes = _apuntes(blocks);
    final marks = apuntes == null
        ? const <int>[]
        : {
            for (final m in RegExp(r'\[pág\. (\d+)\]').allMatches(apuntes.text)) int.parse(m.group(1)!),
          }.toList();
    final apuntesTab = Column(children: [
      Expanded(
        child: apuntes == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Escribe abajo y envía: cada apunte guarda la página que estás viendo. '
                    'Luego tocas la página para volver ahí.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                children: [
                  if (marks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                      child: Wrap(spacing: 6, runSpacing: 4, children: [
                        for (final n in marks)
                          ActionChip(
                            avatar: const Icon(Icons.description_outlined, size: 16),
                            label: Text('pág. $n'),
                            onPressed: () => _goTo(n - 1),
                          ),
                      ]),
                    ),
                  TextBlockView(key: ValueKey(apuntes.id), block: apuntes),
                ],
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _aText,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _sendApunte(),
              decoration: InputDecoration(
                hintText: 'Apunte de la página ${_page + 1}…',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          IconButton(onPressed: _sendApunte, icon: const Icon(Icons.send)),
        ]),
      ),
    ]);

    return Column(children: [
      TabBar(controller: _tabs, tabs: const [Tab(text: 'Hoja'), Tab(text: 'Apuntes')]),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          // En la hoja el dedo dibuja: ahí no se desliza entre pestañas.
          physics: const NeverScrollableScrollPhysics(),
          children: [sheetTab, apuntesTab],
        ),
      ),
    ]);
  }

  // -------------------------------------------------------------- Pantalla

  @override
  Widget build(BuildContext context) {
    final blocks = ref.watch(blocksProvider(widget.noteId)).valueOrNull ?? const <NoteBlock>[];
    final prefs = ref.read(sharedPreferencesProvider);
    final split = _split ?? prefs.getDouble(_splitKey) ?? 0.5;
    return Scaffold(
      appBar: AppBar(
        title: Text(docTitle(prefs, _docPath), overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Abrir otro documento',
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: _changeDoc,
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth > 720;
          final total = wide ? c.maxWidth : c.maxHeight;
          final first = (total * split).clamp(120.0, total - 160.0);
          void drag(double delta) {
            final f = ((first + delta) / total).clamp(0.2, 0.8);
            setState(() => _split = f);
          }

          final handle = _SplitHandle(
            vertical: wide,
            onDrag: drag,
            onEnd: () => prefs.setDouble(_splitKey, _split ?? split),
          );
          _viewWidth = wide ? first : c.maxWidth;
          final children = [
            SizedBox(width: wide ? first : null, height: wide ? null : first, child: _docView()),
            handle,
            Expanded(child: _panel(blocks)),
          ];
          return wide ? Row(children: children) : Column(children: children);
        }),
      ),
    );
  }
}

/// La raya entre el documento y las notas: se arrastra para cambiar el tamaño.
class _SplitHandle extends StatelessWidget {
  const _SplitHandle({required this.vertical, required this.onDrag, required this.onEnd});
  final bool vertical;
  final void Function(double delta) onDrag;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final grip = Container(
      width: vertical ? 4 : 40,
      height: vertical ? 40 : 4,
      decoration: BoxDecoration(color: scheme.outline, borderRadius: BorderRadius.circular(2)),
    );
    return MouseRegion(
      cursor: vertical ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: vertical ? (d) => onDrag(d.delta.dx) : null,
        onVerticalDragUpdate: vertical ? null : (d) => onDrag(d.delta.dy),
        onHorizontalDragEnd: vertical ? (_) => onEnd() : null,
        onVerticalDragEnd: vertical ? null : (_) => onEnd(),
        child: Container(
          width: vertical ? (isDesktop ? 10 : 16) : double.infinity,
          height: vertical ? double.infinity : 16,
          color: scheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: grip,
        ),
      ),
    );
  }
}
