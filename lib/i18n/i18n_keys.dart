/// Frozen i18n key set.
///
/// Every user-visible string outside `LanguageActivity` is looked up with one
/// of these constants. `tool/check_i18n.py` verifies that each catalog declares
/// exactly these keys, so adding a key means touching this file, `en_US.dart`
/// and all 18 translations.
abstract final class I18nKey {
  // Shell / brand.
  static const String appTitle = 'app_title';

  // Top bar.
  static const String topBarSidebarToggle = 'top_bar_sidebar_toggle';
  static const String topBarLanguage = 'top_bar_language';
  static const String topBarTheme = 'top_bar_theme';
  static const String themeLight = 'theme_light';
  static const String themeDark = 'theme_dark';
  static const String themeSystem = 'theme_system';

  // Sidebar.
  static const String sidebarHome = 'sidebar_home';

  // Home content.
  static const String homeEmptyTitle = 'home_empty_title';
  static const String homeEmptyBody = 'home_empty_body';
  static const String homeEmptyBodyTouch = 'home_empty_body_touch';
  static const String homeDropHint = 'home_drop_hint';
  static const String homeDropHintIdle = 'home_drop_hint_idle';
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
  static const String addSourceConfirmTitle = 'add_source_confirm_title';
  static const String addSourceConfirmBody = 'add_source_confirm_body';
  static const String actionAdd = 'action_add';

  static const String jobSectionInput = 'job_section_input';
  static const String jobLabelVideoDecoder = 'job_label_video_decoder';
  static const String jobLabelAudioDecoder = 'job_label_audio_decoder';
  static const String jobDecoderAuto = 'job_decoder_auto';

  static const String jobRateMode = 'job_rate_mode';
  static const String jobRateAuto = 'job_rate_auto';
  static const String jobRateQuality = 'job_rate_quality';
  static const String jobRateBitrate = 'job_rate_bitrate';
  static const String jobRateCbr = 'job_rate_cbr';
  static const String jobRateRequired = 'job_rate_required';

  /// Shown as the empty entry of an option that may be left unset.
  static const String optionUnset = 'option_unset';
  static const String optionEdit = 'option_edit';

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

  // Encode form.
  static const String jobPageTitle = 'job_page_title';
  static const String jobSectionCodecs = 'job_section_codecs';
  static const String jobSectionBasic = 'job_section_basic';
  static const String jobSectionAdvanced = 'job_section_advanced';
  static const String jobSectionCustom = 'job_section_custom';
  static const String jobCustomHint = 'job_custom_hint';
  static const String jobLabelVideoCodec = 'job_label_video_codec';
  static const String jobLabelAudioCodec = 'job_label_audio_codec';
  static const String jobLabelContainer = 'job_label_container';
  static const String jobLabelOutputName = 'job_label_output_name';

  /// Caption that names the folder the finished file lands in.
  static const String jobOutputTo = 'job_output_to';
  static const String jobNoVideo = 'job_no_video';
  static const String jobNoAudio = 'job_no_audio';
  static const String jobNoContainer = 'job_no_container';
  static const String jobNoOptions = 'job_no_options';
  static const String jobCancel = 'job_cancel';
  static const String jobStart = 'job_start';
  static const String jobDiscardTitle = 'job_discard_title';
  static const String jobDiscardBody = 'job_discard_body';
  static const String jobDiscardKeep = 'job_discard_keep';
  static const String jobDiscardConfirm = 'job_discard_confirm';
  static const String mediaTypeVideo = 'media_type_video';
  static const String mediaTypeAudio = 'media_type_audio';
  static const String mediaTypeImage = 'media_type_image';
  static const String mediaTypeUnknown = 'media_type_unknown';

  // Job list.
  static const String jobsTitle = 'jobs_title';
  static const String jobsEmpty = 'jobs_empty';
  static const String jobLogTitle = 'job_log_title';
  static const String jobLogAutoscroll = 'job_log_autoscroll';
  static const String jobLogEmpty = 'job_log_empty';
  static const String jobStateQueued = 'job_state_queued';
  static const String jobStateRunning = 'job_state_running';
  static const String jobStatePaused = 'job_state_paused';
  static const String jobStateCompleted = 'job_state_completed';
  static const String jobStateFailed = 'job_state_failed';
  static const String jobStateCancelled = 'job_state_cancelled';
  static const String jobPause = 'job_pause';
  static const String jobResume = 'job_resume';
  static const String jobStop = 'job_stop';
  static const String jobRemove = 'job_remove';
  static const String jobPauseUnsupported = 'job_pause_unsupported';
  static const String jobConfirmStopTitle = 'job_confirm_stop_title';
  static const String jobConfirmStopBody = 'job_confirm_stop_body';
  static const String jobConfirmStopConfirm = 'job_confirm_stop_confirm';
  static const String jobProgressUnknown = 'job_progress_unknown';

  // Option labels.
  static const String optQualityScale = 'opt_quality_scale';
  static const String optQualityScaleAudio = 'opt_quality_scale_audio';
  static const String optBitrateVideo = 'opt_bitrate_video';
  static const String optBitrateAudio = 'opt_bitrate_audio';
  static const String optQuantMin = 'opt_quant_min';
  static const String optQuantMax = 'opt_quant_max';
  static const String optMaxRate = 'opt_max_rate';
  static const String optBufSize = 'opt_buf_size';
  static const String optGopSize = 'opt_gop_size';
  static const String optBFrames = 'opt_b_frames';
  static const String optPixelFormat = 'opt_pixel_format';
  static const String optThreads = 'opt_threads';
  static const String optProfile = 'opt_profile';
  static const String optLevel = 'opt_level';
  static const String optCodecLevel = 'opt_codec_level';
  static const String optMbDecision = 'opt_mb_decision';
  static const String optTrellis = 'opt_trellis';
  static const String optMvFourMotion = 'opt_mv_four_motion';
  static const String optHuffman = 'opt_huffman';
  static const String optCompressionLevel = 'opt_compression_level';
  static const String optPrediction = 'opt_prediction';
  static const String optCoder = 'opt_coder';
  static const String optSlices = 'opt_slices';
  static const String optSliceCrc = 'opt_slice_crc';
  static const String optVendor = 'opt_vendor';
  static const String optBitsPerMb = 'opt_bits_per_mb';
  static const String optCutoff = 'opt_cutoff';
  static const String optSampleRate = 'opt_sample_rate';
  static const String optChannels = 'opt_channels';
  static const String optDialNorm = 'opt_dial_norm';
  static const String optDolbySurround = 'opt_dolby_surround';
  static const String optApplication = 'opt_application';
  static const String optFrameDuration = 'opt_frame_duration';
  static const String optMovFlags = 'opt_mov_flags';
  static const String optMovFastStart = 'opt_mov_fast_start';
  static const String optMovFragmented = 'opt_mov_fragmented';
  static const String optMovMetadataTags = 'opt_mov_metadata_tags';
  static const String optClusterTime = 'opt_cluster_time';
  static const String optClusterSize = 'opt_cluster_size';
  static const String optMpegtsFlags = 'opt_mpegts_flags';
  static const String optFlvFlags = 'opt_flv_flags';
  static const String optGifLoop = 'opt_gif_loop';
  static const String optPageDuration = 'opt_page_duration';

  /// Display order used by `LanguageActivity`; mirrors `kSupportedLanguageTags`.
  static const List<String> all = <String>[
    appTitle,
    topBarSidebarToggle,
    topBarLanguage,
    topBarTheme,
    themeLight,
    themeDark,
    themeSystem,
    sidebarHome,
    homeEmptyTitle,
    homeEmptyBody,
    homeEmptyBodyTouch,
    homeDropHint,
    homeDropHintIdle,
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
    addSourceConfirmTitle,
    addSourceConfirmBody,
    actionAdd,
    optionUnset,
    optionEdit,
    jobSectionInput,
    jobLabelVideoDecoder,
    jobLabelAudioDecoder,
    jobDecoderAuto,
    jobRateMode,
    jobRateAuto,
    jobRateQuality,
    jobRateBitrate,
    jobRateCbr,
    jobRateRequired,
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
    jobPageTitle,
    jobSectionCodecs,
    jobSectionBasic,
    jobSectionAdvanced,
    jobSectionCustom,
    jobCustomHint,
    jobLabelVideoCodec,
    jobLabelAudioCodec,
    jobLabelContainer,
    jobLabelOutputName,
    jobOutputTo,
    jobNoVideo,
    jobNoAudio,
    jobNoContainer,
    jobNoOptions,
    jobCancel,
    jobStart,
    jobDiscardTitle,
    jobDiscardBody,
    jobDiscardKeep,
    jobDiscardConfirm,
    mediaTypeVideo,
    mediaTypeAudio,
    mediaTypeImage,
    mediaTypeUnknown,
    jobsTitle,
    jobsEmpty,
    jobLogTitle,
    jobLogAutoscroll,
    jobLogEmpty,
    jobStateQueued,
    jobStateRunning,
    jobStatePaused,
    jobStateCompleted,
    jobStateFailed,
    jobStateCancelled,
    jobPause,
    jobResume,
    jobStop,
    jobRemove,
    jobPauseUnsupported,
    jobConfirmStopTitle,
    jobConfirmStopBody,
    jobConfirmStopConfirm,
    jobProgressUnknown,
    optQualityScale,
    optQualityScaleAudio,
    optBitrateVideo,
    optBitrateAudio,
    optQuantMin,
    optQuantMax,
    optMaxRate,
    optBufSize,
    optGopSize,
    optBFrames,
    optPixelFormat,
    optThreads,
    optProfile,
    optLevel,
    optCodecLevel,
    optMbDecision,
    optTrellis,
    optMvFourMotion,
    optHuffman,
    optCompressionLevel,
    optPrediction,
    optCoder,
    optSlices,
    optSliceCrc,
    optVendor,
    optBitsPerMb,
    optCutoff,
    optSampleRate,
    optChannels,
    optDialNorm,
    optDolbySurround,
    optApplication,
    optFrameDuration,
    optMovFlags,
    optMovFastStart,
    optMovFragmented,
    optMovMetadataTags,
    optClusterTime,
    optClusterSize,
    optMpegtsFlags,
    optFlvFlags,
    optGifLoop,
    optPageDuration,
  ];
}
