import 'package:go_router/go_router.dart';

import '../features/notes/presentation/note_editor_screen.dart';
import '../features/notes/presentation/notes_list_screen.dart';
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
      builder: (context, state) => const NotesListScreen(),
      routes: [
        GoRoute(
          path: 'notes/:id',
          builder: (context, state) =>
              NoteEditorScreen(noteId: state.pathParameters['id']!),
          routes: [
            GoRoute(
              path: 'record',
              builder: (context, state) =>
                  RecordingScreen(noteId: state.pathParameters['id']!),
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
