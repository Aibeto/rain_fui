/// Frozen i18n key set.
///
/// Every user-visible string outside `LanguageActivity` is looked up with one
/// of these constants. `tool/check_i18n.py` verifies that each catalog declares
/// exactly these keys, so adding a key means touching this file, `en_US.dart`
/// and all 18 translations.
abstract final class I18nKey {
  // Shell / brand.
  static const String appTitle = 'app_title';
  static const String appTagline = 'app_tagline';

  // Top bar.
  static const String topBarSidebarToggle = 'top_bar_sidebar_toggle';
  static const String topBarLanguage = 'top_bar_language';
  static const String topBarTheme = 'top_bar_theme';
  static const String themeLight = 'theme_light';
  static const String themeDark = 'theme_dark';
  static const String themeSystem = 'theme_system';

  // Sidebar.
  static const String sidebarWorkspace = 'sidebar_workspace';
  static const String sidebarHome = 'sidebar_home';

  // Home content.
  static const String homeTitle = 'home_title';
  static const String homeEmptyTitle = 'home_empty_title';
  static const String homeEmptyBody = 'home_empty_body';
  static const String homeDropHint = 'home_drop_hint';
  static const String homePhaseNotice = 'home_phase_notice';
  static const String homeSourcesTitle = 'home_sources_title';
  static const String homeSourcesEmpty = 'home_sources_empty';

  // Bottom bar.
  static const String bottomBarHome = 'bottom_bar_home';
  static const String bottomBarAdd = 'bottom_bar_add';

  // Add-source dialog.
  static const String addSourceTitle = 'add_source_title';
  static const String addSourceBody = 'add_source_body';
  static const String addSourceFiles = 'add_source_files';
  static const String addSourceFilesHint = 'add_source_files_hint';
  static const String addSourceFolder = 'add_source_folder';
  static const String addSourceFolderHint = 'add_source_folder_hint';
  static const String actionCancel = 'action_cancel';
  static const String actionClose = 'action_close';

  // Selection result dialog.
  static const String resultFilesTitle = 'result_files_title';
  static const String resultFolderTitle = 'result_folder_title';
  static const String resultDropTitle = 'result_drop_title';
  static const String resultNothing = 'result_nothing';
  static const String resultFilesLabel = 'result_files_label';
  static const String resultFoldersLabel = 'result_folders_label';
  static const String resultChildrenLabel = 'result_children_label';
  static const String resultChildrenEmpty = 'result_children_empty';
  static const String resultChildrenTruncated = 'result_children_truncated';
  static const String resultWebPathsUnavailable =
      'result_web_paths_unavailable';
  static const String resultReadError = 'result_read_error';

  // Errors.
  static const String errorPickerFailed = 'error_picker_failed';
  static const String errorFolderUnsupportedWeb =
      'error_folder_unsupported_web';
  static const String errorFolderUnsupportedAndroid =
      'error_folder_unsupported_android';
  static const String errorDropFailed = 'error_drop_failed';

  /// Display order used by `LanguageActivity`; mirrors `kSupportedLanguageTags`.
  static const List<String> all = <String>[
    appTitle,
    appTagline,
    topBarSidebarToggle,
    topBarLanguage,
    topBarTheme,
    themeLight,
    themeDark,
    themeSystem,
    sidebarWorkspace,
    sidebarHome,
    homeTitle,
    homeEmptyTitle,
    homeEmptyBody,
    homeDropHint,
    homePhaseNotice,
    homeSourcesTitle,
    homeSourcesEmpty,
    bottomBarHome,
    bottomBarAdd,
    addSourceTitle,
    addSourceBody,
    addSourceFiles,
    addSourceFilesHint,
    addSourceFolder,
    addSourceFolderHint,
    actionCancel,
    actionClose,
    resultFilesTitle,
    resultFolderTitle,
    resultDropTitle,
    resultNothing,
    resultFilesLabel,
    resultFoldersLabel,
    resultChildrenLabel,
    resultChildrenEmpty,
    resultChildrenTruncated,
    resultWebPathsUnavailable,
    resultReadError,
    errorPickerFailed,
    errorFolderUnsupportedWeb,
    errorFolderUnsupportedAndroid,
    errorDropFailed,
  ];
}
