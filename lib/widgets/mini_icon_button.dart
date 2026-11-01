import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;

/// A square icon button that takes the height of a text line.
///
/// The stock `IconButton` reserves 40 px around a small glyph, which pushes the
/// row it sits in taller than the text next to it. This keeps the hit target
/// and the row height in step, and greys the glyph out when there is nothing to
/// press.
class MiniIconButton extends StatelessWidget {
  /// Creates a small icon button.
  const MiniIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = 24,
    this.iconSize = 12,
  });

  /// Glyph to draw.
  final IconData icon;

  /// Tooltip text; already localized by the caller.
  final String tooltip;

  /// Null disables the button.
  final VoidCallback? onPressed;

  /// Width and height of the hit target.
  final double size;

  /// Size of the glyph inside the target.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    final bool enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: HoverButton(
        onPressed: onPressed,
        builder: (BuildContext context, Set<WidgetState> states) {
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: enabled && states.contains(WidgetState.hovered)
                  ? resources.subtleFillColorSecondary
                  : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: enabled
                  ? resources.textFillColorSecondary
                  : resources.textFillColorDisabled,
            ),
          );
        },
      ),
    );
  }
}
