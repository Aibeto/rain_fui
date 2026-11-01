/// Spacing shared by every screen.
///
/// The header, the scrolling content and the action bar used to pick their own
/// insets, so moving between the home list, the encode page and the log page
/// shifted everything a few pixels sideways. They all read from here instead.
abstract final class AppMetrics {
  /// Inset on the start and end edge of a page, and of its bars.
  static const double gutter = 20;

  /// Gap above a section title.
  static const double sectionGap = 20;

  /// Gap between a section title and the controls under it.
  static const double sectionTitleGap = 8;

  /// Gap between two rows of the same kind.
  static const double rowGap = 8;

  /// Width of the narrow input that sits at the end of an option row.
  static const double fieldWidth = 132;

  /// Horizontal gap between two columns of the option grid.
  static const double columnGap = 16;

  /// Widest a form may get before it stops stretching on a wide window.
  static const double contentWidth = 960;

  /// Smallest width an option cell may get before a column is dropped.
  static const double minCellWidth = 260;
}
