/// English (United States) — reference catalog.
///
/// This map is the fallback for every other locale and must stay the most
/// complete one. Copy rules: short sentences, no placeholder tokens (lookup is
/// a plain map), sentence case, no trailing period on single-line labels.
const Map<String, String> enUs = <String, String>{
  // Shell / brand.
  'app_title': 'Rain FUI',
  'app_tagline': 'A Fluent shell for FFmpeg',

  // Top bar.
  'top_bar_sidebar_toggle': 'Toggle sidebar',
  'top_bar_language': 'Change language',
  'top_bar_theme': 'Theme',
  'theme_light': 'Light',
  'theme_dark': 'Dark',
  'theme_system': 'System',

  // Sidebar.
  'sidebar_workspace': 'Workspace',
  'sidebar_home': 'Home',

  // Home content.
  'home_title': 'Workspace',
  'home_empty_title': 'Nothing added yet',
  'home_empty_body': 'Use the + button to pick files or a folder, or drop them anywhere in this window.',
  'home_drop_hint': 'Release to add',
  'home_phase_notice': 'Preview build: the UI skeleton is in place, media handling and FFmpeg are not wired up yet.',
  'home_sources_title': 'Added sources',
  'home_sources_empty': 'Sources you add in this session show up here.',

  // Bottom bar.
  'bottom_bar_home': 'Home',
  'bottom_bar_add': 'Add files or folders',

  // Add-source dialog.
  'add_source_title': 'Add to workspace',
  'add_source_body':
      'Pick one or more files, or choose a folder to see its contents.',
  'add_source_files': 'Choose files',
  'add_source_files_hint': 'Multiple selection is supported.',
  'add_source_folder': 'Choose folder',
  'add_source_folder_hint': 'Adds the folder and its first-level children.',
  'action_cancel': 'Cancel',
  'action_close': 'Close',

  // Selection result dialog.
  'result_files_title': 'Selected files',
  'result_folder_title': 'Selected folder',
  'result_drop_title': 'Dropped items',
  'result_nothing': 'Nothing was added.',
  'result_files_label': 'Files',
  'result_folders_label': 'Folders',
  'result_children_label': 'Contents',
  'result_children_empty': 'This folder is empty.',
  'result_children_truncated': 'Showing the first entries only.',
  'result_web_paths_unavailable':
      'Browsers do not expose local file paths, so only names are shown.',
  'result_read_error': 'The folder contents could not be read.',

  // Errors.
  'error_picker_failed': 'The picker could not be opened.',
  'error_folder_unsupported_web': 'Folder selection is not available in a browser. Pick files instead, or drop a folder onto the window.',
  'error_folder_unsupported_android':
      'This Android version cannot open a folder picker. Pick files instead.',
  'error_drop_failed': 'The dropped items could not be read.',
};
