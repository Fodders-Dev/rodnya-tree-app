part of '../create_post_screen.dart';

class _PostMedia {
  const _PostMedia({required this.file, required this.isVideo});

  final XFile file;
  final bool isVideo;
}

/// Audience preview computed from the composer's selected branches.
/// Carries the union member count and the branch count so the
/// pluralization helpers can render the right grammar.
class _AudienceSummary {
  const _AudienceSummary({required this.viewers, required this.branches});

  final int viewers;
  final int branches;
}

class _PickedMediaPreview extends StatelessWidget {
  const _PickedMediaPreview({required this.media});

  final _PostMedia media;

  @override
  Widget build(BuildContext context) {
    if (media.isVideo) {
      return _VideoTilePoster(file: media.file);
    }
    return FutureBuilder<Uint8List>(
      future: media.file.readAsBytes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ColoredBox(
            color: Color(0x11000000),
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          // Composer-side preview of an image the user just attached
          // to their post — confirms the attach worked.
          semanticLabel: 'Прикреплённое изображение',
          errorBuilder: (_, __, ___) => const ColoredBox(
            color: Color(0x11000000),
            child: Center(child: Icon(Icons.broken_image_outlined)),
          ),
        );
      },
    );
  }
}

/// Composer-side video poster. We don't pull a real frame here because
/// that would mean importing video_thumbnail just for the draft state —
/// the published post does it server-side / via the lightbox. A dark
/// gradient + filename + play overlay is enough to confirm "this is the
/// video I just attached" before publishing.
class _VideoTilePoster extends StatelessWidget {
  const _VideoTilePoster({required this.file});

  final XFile file;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF332B45), Color(0xFF181522)],
            ),
          ),
        ),
        Center(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(10),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
        Positioned(
          left: 6,
          right: 6,
          bottom: 6,
          child: Text(
            file.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
            ),
          ),
        ),
      ],
    );
  }
}
