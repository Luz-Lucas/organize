import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/notebook_cover.dart';
import 'state/notebook_providers.dart';

/// Cor do texto que se lê bem sobre [background].
Color coverInkOn(Color background) => background.computeLuminance() > 0.5 ? const Color(0xFF1C1917) : Colors.white;

/// Desenha a [cover] do caderno [noteId] ocupando todo o espaço dado.
class NotebookCoverView extends StatelessWidget {
  const NotebookCoverView({super.key, required this.noteId, required this.cover, this.radius = 2});

  final String noteId;
  final NotebookCover cover;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bg = Color(cover.color);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        key: const ValueKey('nb-cover'),
        color: bg,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth.isFinite ? c.maxWidth : 120.0;
            return switch (cover.kind) {
              CoverKind.emoji => Center(
                child: Text(
                  cover.emoji,
                  style: TextStyle(fontSize: w * 0.45),
                  textAlign: TextAlign.center,
                ),
              ),
              CoverKind.text => Padding(
                padding: EdgeInsets.all(w * 0.1),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: w * 0.8),
                      child: Text(
                        cover.text,
                        textAlign: TextAlign.center,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: coverInkOn(bg),
                          fontSize: (w * 0.16).clamp(6, 64),
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              CoverKind.image => _CoverImage(
                noteId: noteId,
                path: cover.imagePath!,
                fit: cover.fit == CoverFit.fill ? BoxFit.cover : BoxFit.contain,
              ),
            };
          },
        ),
      ),
    );
  }
}

class _CoverImage extends ConsumerStatefulWidget {
  const _CoverImage({required this.noteId, required this.path, required this.fit});

  final String noteId;
  final String path;
  final BoxFit fit;

  @override
  ConsumerState<_CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends ConsumerState<_CoverImage> {
  static final _cache = <String, Future<ImageProvider>>{};
  Future<ImageProvider>? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_CoverImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _load();
  }

  void _load() {
    try {
      final store = ref.read(notebookImageStoreFactoryProvider)(widget.noteId);
      final path = widget.path;
      _image = _cache.putIfAbsent(path, () {
        final f = store.load(path);
        f.then(
          (_) {},
          onError: (Object _) {
            _cache.remove(path); // falhou: tenta de novo depois
          },
        );
        return f;
      });
    } catch (_) {
      _image = null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ImageProvider>(
    future: _image,
    builder: (context, snap) => snap.hasData
        ? Image(
            image: snap.data!,
            fit: widget.fit,
            width: double.infinity,
            height: double.infinity,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)),
          )
        : const SizedBox.expand(),
  );
}
