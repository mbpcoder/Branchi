import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_locale.dart';
import '../theme/app_theme.dart';

/// How a file is shown in an editor tab.
enum OpenFileKind { text, image, svg, binary }

/// Raster formats Flutter can decode on every desktop platform.
const Set<String> _imageExtensions = {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'wbmp',
  'ico',
};

/// Picks how to show [path]: images and SVGs by extension, otherwise text
/// unless the start of the file contains a NUL byte (a binary file).
Future<OpenFileKind> detectOpenFileKind(String path) async {
  final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
  if (_imageExtensions.contains(ext)) return OpenFileKind.image;
  if (ext == 'svg') return OpenFileKind.svg;
  RandomAccessFile? handle;
  try {
    handle = await File(path).open();
    final head = await handle.read(8000);
    return head.contains(0) ? OpenFileKind.binary : OpenFileKind.text;
  } catch (_) {
    // Let the text loader report the real error.
    return OpenFileKind.text;
  } finally {
    await handle?.close();
  }
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// A zoomable preview of an image or SVG, or a notice for a binary file.
class FilePreview extends StatefulWidget {
  const FilePreview({
    super.key,
    required this.path,
    required this.kind,
    this.onShowSource,
  });

  final String path;
  final OpenFileKind kind;

  /// For SVGs: switches the tab to the text editor.
  final VoidCallback? onShowSource;

  @override
  State<FilePreview> createState() => _FilePreviewState();
}

class _FilePreviewState extends State<FilePreview> {
  /// Large images are decoded at most this wide/tall, so a huge photo
  /// doesn't hold hundreds of MB of pixels.
  static const _maxDecodeSize = 4096;

  int? _bytes;
  Size? _dimensions;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  @override
  void didUpdateWidget(covariant FilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _bytes = null;
      _dimensions = null;
      _loadInfo();
    }
  }

  Future<void> _loadInfo() async {
    final path = widget.path;
    try {
      final bytes = await File(path).length();
      Size? dimensions;
      if (widget.kind == OpenFileKind.image) {
        // Reads only the header, without decoding the pixels.
        final buffer = await ui.ImmutableBuffer.fromFilePath(path);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        dimensions = Size(
          descriptor.width.toDouble(),
          descriptor.height.toDouble(),
        );
        descriptor.dispose();
        buffer.dispose();
      }
      if (!mounted || path != widget.path) return;
      setState(() {
        _bytes = bytes;
        _dimensions = dimensions;
      });
    } catch (_) {
      // The preview itself shows the error.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.branchi;
    final style = TextStyle(fontSize: 12, color: c.muted);

    if (widget.kind == OpenFileKind.binary) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 40, color: c.muted),
            const SizedBox(height: 12),
            Text(translate('preview_binary_file'), style: TextStyle(color: c.fg)),
            if (_bytes != null) ...[
              const SizedBox(height: 4),
              Text(formatFileSize(_bytes!), style: style),
            ],
          ],
        ),
      );
    }

    final file = File(widget.path);
    final Widget picture;
    if (widget.kind == OpenFileKind.svg) {
      picture = SvgPicture.file(
        file,
        key: ValueKey(widget.path),
        fit: BoxFit.contain,
        errorBuilder: (context, error, _) => _error(c),
      );
    } else {
      final provider = FileImage(file);
      // Show the file as it is on disk now, not a cached earlier version.
      provider.evict();
      picture = Image(
        image: ResizeImage(
          provider,
          width: _maxDecodeSize,
          height: _maxDecodeSize,
          policy: ResizeImagePolicy.fit,
        ),
        fit: BoxFit.scaleDown,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (context, error, _) => _error(c),
      );
    }

    final info = [
      if (_dimensions != null)
        '${_dimensions!.width.toInt()} × ${_dimensions!.height.toInt()}',
      if (_bytes != null) formatFileSize(_bytes!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRect(
            child: InteractiveViewer(
              minScale: 0.1,
              maxScale: 16,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: picture),
              ),
            ),
          ),
        ),
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(border: Border(top: c.hairline)),
          child: Row(
            children: [
              Text(translate('preview_zoom_hint'), style: style),
              const Spacer(),
              if (widget.onShowSource != null) ...[
                InkWell(
                  onTap: widget.onShowSource,
                  child: Text(
                    translate('preview_show_source'),
                    style: style.copyWith(color: c.accent),
                  ),
                ),
                const SizedBox(width: 16),
              ],
              Text(info.join('  ·  '), style: style),
            ],
          ),
        ),
      ],
    );
  }

  Widget _error(BranchiColors c) => Text(
        translate('preview_failed'),
        style: TextStyle(color: c.del),
      );
}
