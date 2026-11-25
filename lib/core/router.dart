import 'package:go_router/go_router.dart';

import '../features/drawing/presentation/drawing_screen.dart';
import '../features/expenses/presentation/expenses_screen.dart';
import '../features/notebooks/presentation/library_screen.dart';
import '../features/notes/presentation/book_view_screen.dart';
import '../features/notes/presentation/note_editor_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/notes/presentation/notes_list_screen.dart';
import '../features/recording/presentation/recording_detail_screen.dart';
import '../features/recording/presentation/recording_screen.dart';
import '../features/video/presentation/video_notes_screen.dart';

/// Argumentos para abrir un video en un minuto concreto.
class VideoArgs {
  const VideoArgs({required this.videoPath, this.startMs = 0});
  final String videoPath;
  final int startMs;
}

final appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const LibraryScreen(),
      routes: [
        GoRoute(
          path: 'expenses',
          builder: (context, state) => const ExpensesScreen(),
        ),
        GoRoute(
          path: 'settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: 'notebooks/:nb',
          builder: (context, state) {
            final nb = state.pathParameters['nb']!;
            return NotesListScreen(notebookId: nb == 'all' ? null : nb);
          },
        ),
        GoRoute(
          path: 'notes/:id',
          builder: (context, state) =>
              NoteEditorScreen(noteId: state.pathParameters['id']!),
          routes: [
            GoRoute(
              path: 'book',
              builder: (context, state) => BookViewScreen(
                noteId: state.pathParameters['id']!,
                initialPage: state.extra as int? ?? 0,
              ),
            ),
            GoRoute(
              path: 'record',
              builder: (context, state) =>
                  RecordingScreen(noteId: state.pathParameters['id']!),
            ),
            GoRoute(
              path: 'audio/:blockId',
              builder: (context, state) => RecordingDetailScreen(
                noteId: state.pathParameters['id']!,
                blockId: state.pathParameters['blockId']!,
              ),
            ),
            GoRoute(
              path: 'drawing',
              builder: (context, state) => DrawingScreen(
                noteId: state.pathParameters['id']!,
                path: state.extra! as String,
              ),
            ),
            GoRoute(
              path: 'video',
              builder: (context, state) {
                final args = state.extra! as VideoArgs;
                return VideoNotesScreen(
                  noteId: state.pathParameters['id']!,
                  videoPath: args.videoPath,
                  startMs: args.startMs,
                );
              },
            ),
          ],
        ),
      ],
    ),
  ],
);
