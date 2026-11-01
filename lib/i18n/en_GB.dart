/// English (United Kingdom) — British spelling and register ("choose", "select").
const Map<String, String> enGb = <String, String>{
  // Shell / brand.
  'app_title': 'Rain FUI',

  // Top bar.
  'top_bar_sidebar_toggle': 'Show or hide the sidebar',
  'top_bar_language': 'Change the language',
  'top_bar_theme': 'Theme',
  'theme_light': 'Light',
  'theme_dark': 'Dark',
  'theme_system': 'System',

  // Sidebar.
  'sidebar_home': 'Home',

  // Home content.
  'home_empty_title': 'Nothing has been added yet',
  'home_empty_body': 'Use the + button to choose files or a folder, or drag and drop them anywhere in this window.',
  'home_empty_body_touch': 'Use the + button to choose files or a folder.',
  'home_drop_hint': 'Release to add',
  'home_drop_hint_idle': 'Drag files or folders here',
  'home_phase_notice': 'Preview build: the UI skeleton is in place, but media handling and FFmpeg are not connected yet.',
  'home_sources_title': 'Added sources',
  'home_sources_empty': 'Sources you add during this session appear here.',

  // Bottom bar.
  'bottom_bar_home': 'Home',
  'bottom_bar_add': 'Add files or folders',

  // Add-source dialog.
  'add_source_title': 'Add sources',
  'add_source_body':
      'Select one or more files, or choose a folder to see what’s inside.',
  'add_source_files': 'Choose files',
  'add_source_files_hint': 'You can select more than one file.',
  'add_source_folder': 'Choose a folder',
  'add_source_folder_hint': 'Adds the folder and its top-level contents.',
  'add_source_confirm_title': 'Add this folder?',
  'add_source_confirm_body':
      'The folder will be listed as a source on the home screen.',
  'action_add': 'Add',
  'action_cancel': 'Cancel',
  'action_close': 'Close',

  // Selection result dialog.
  'result_files_title': 'Selected files',
  'result_folder_title': 'Selected folder',
  'result_drop_title': 'Dropped items',
  'result_nothing': 'Nothing has been added.',
  'result_files_label': 'Files',
  'result_folders_label': 'Folders',
  'result_children_label': 'Contents',
  'result_children_empty': 'This folder is empty.',
  'result_children_truncated': 'Only the first entries are shown.',
  'result_web_paths_unavailable':
      'Browsers don’t expose local file paths, so only names are shown.',
  'result_read_error': 'The folder’s contents couldn’t be read.',

  // Errors.
  'error_picker_failed': 'The file picker couldn’t be opened.',
  'error_folder_unsupported_web': 'Folder selection isn’t available in a browser. Choose files instead, or drop a folder onto the window.',
  'error_folder_unsupported_android': 'This version of Android can’t open a folder picker. Choose files instead.',
  'error_drop_failed': 'The items you dropped couldn’t be read.',
};
