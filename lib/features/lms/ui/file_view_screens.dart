import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/desktop.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/lms/data/file_opener.dart';
import 'package:resit/features/lms/data/topic_files.dart';
import 'package:resit/features/lms/domain/course_extras.dart';
import 'package:resit/features/lms/ui/open_in_browser.dart';

/// Draws a PDF from a local file. A provider so tests can stand in for the
/// native PDF engine (PDFium), which isn't available to widget tests.
final pdfViewBuilderProvider = Provider<Widget Function(String path)>(
  (ref) => (path) => PdfViewer.file(
        path,
        params: const PdfViewerParams(
          margin: 8,
          backgroundColor: Colors.transparent,
        ),
      ),
);

/// A downloaded course file shown in the app: a PDF in a viewer, an image
/// that can be zoomed, or plain text (notes, Markdown, logs). Its bar offers the file to another app, or
/// the item on xSiTe.
class FileViewScreen extends ConsumerWidget {
  final SavedFile file;

  /// The item's page on xSiTe.
  final Uri onXsite;

  const FileViewScreen({super.key, required this.file, required this.onXsite});

  Future<void> _openElsewhere(BuildContext context, WidgetRef ref) async {
    final opened = await ref.read(fileOpenerProvider).open(file.path);
    if (!opened && context.mounted) showError(context, 'No app on this device opens ${file.name}.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      appBar: thumbAppBar(file.name, subtitle: fileSizeLabel(file.size)),
      body: switch (viewFor(file.name)) {
        FileView.pdf => ref.watch(pdfViewBuilderProvider)(file.path),
        FileView.text => _TextView(file: file),
        _ => InteractiveViewer(
            maxScale: 6,
            child: Center(
              child: Image.file(
                File(file.path),
                semanticLabel: file.name,
                errorBuilder: (context, error, stack) => const MessageView(
                  icon: Icons.broken_image_outlined,
                  title: "Couldn't show this image",
                  message: 'Open it in another app or on xSiTe.',
                ),
              ),
            ),
          ),
      },
      bottomNavigationBar: ThumbBar(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => _openElsewhere(context, ref),
                icon: const Icon(Icons.ios_share),
                label: const Text('Open in another app', overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 8),
            ThumbIconButton(
              tooltip: 'Open on xSiTe',
              icon: Icons.open_in_new,
              onPressed: () => openInBrowser(context, onXsite),
            ),
          ],
        ),
      ),
    );
  }
}

/// Text files over this are left to another app: drawing megabytes of text
/// at once makes scrolling stutter.
const maxTextViewBytes = 1024 * 1024;

/// A text file's words, selectable, at reading size and width. Bytes that
/// aren't UTF-8 show as a replacement mark rather than failing the file.
class _TextView extends StatefulWidget {
  final SavedFile file;
  const _TextView({required this.file});

  @override
  State<_TextView> createState() => _TextViewState();
}

class _TextViewState extends State<_TextView> {
  late final Future<String> _text = _read();

  Future<String> _read() async {
    if (widget.file.size > maxTextViewBytes) throw const FileSystemException('too big');
    return utf8.decode(await File(widget.file.path).readAsBytes(), allowMalformed: true);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _text,
      builder: (context, snap) {
        if (snap.hasError) {
          return MessageView(
            icon: Icons.article_outlined,
            title: widget.file.size > maxTextViewBytes ? 'Too long to show here' : "Couldn't read this file",
            message: 'Open it in another app or on xSiTe.',
          );
        }
        final text = snap.data;
        if (text == null) return const Center(child: CircularProgressIndicator());
        final style = Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6);
        return SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: SizedBox(width: double.infinity, child: Text(text, style: style)),
              ),
            ),
          ),
        );
      },
    );
  }
}
