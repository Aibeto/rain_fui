import 'package:desktop_drop/desktop_drop.dart';
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;

import '../i18n/i18n.dart';
import '../i18n/i18n_keys.dart';
import '../models/source_selection.dart';
import '../services/file_source_service.dart';
import '../services/platform_support.dart';

/// Turns its [child] into a drag-and-drop target for files and folders.
///
/// Drops are resolved by [FileSourceService] — never by `dart:io` — so the
/// surface works on desktop and on the web alike. A successful drop is reported
/// through [onSelection]; a failed one through [onError], leaving the choice of
/// how to surface it to the owner of this widget.
///
/// The hover highlight only ever appears where dragging exists
/// ([supportsDropTarget]); touch platforms never see it.
class DropSurface extends StatefulWidget {
  /// Creates a drop surface wrapped around [child].
  const DropSurface({
    super.key,
    required this.child,
    required this.onSelection,
    required this.onError,
  });

  /// The widget that becomes the drop target — usually the whole shell body.
  final Widget child;

  /// Called with the parsed selection when a drop produced one.
  final ValueChanged<SourceSelection> onSelection;

  /// Called when the dropped items could not be read.
  final ValueChanged<FileSourceException> onError;

  @override
  State<DropSurface> createState() => _DropSurfaceState();
}

class _DropSurfaceState extends State<DropSurface> {
  bool _hovering = false;

  Future<void> _handleDrop(DropDoneDetails details) async {
    try {
      final SourceSelection? selection =
          await FileSourceService.selectionFromDrop(details);
      if (selection != null) {
        widget.onSelection(selection);
      }
    } on FileSourceException catch (error) {
      widget.onError(error);
    } catch (error) {
      widget.onError(
        FileSourceException(I18nKey.errorDropFailed, detail: '$error'),
      );
    } finally {
      if (mounted) {
        _setHovering(false);
      }
    }
  }

  void _setHovering(bool hovering) {
    if (_hovering == hovering) {
      return;
    }
    setState(() => _hovering = hovering);
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final Color accent = theme.accentColor.normal;

    return DropTarget(
      onDragEntered: (_) => _setHovering(true),
      onDragExited: (_) => _setHovering(false),
      onDragDone: _handleDrop,
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          widget.child,
          if (supportsDropTarget)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_hovering,
                child: AnimatedOpacity(
                  opacity: _hovering ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  child: Container(
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      border: Border.all(color: accent, width: 2),
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: accent),
                        ),
                        child: Text(
                          context.l10n(I18nKey.homeDropHint),
                          style: theme.typography.bodyStrong?.copyWith(
                            color: accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
