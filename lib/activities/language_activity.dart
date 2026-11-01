import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../i18n/i18n.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

/// Endonyms for the 19 supported locales, i.e. the name each language has for
/// itself in its own script. The spec allows this screen to carry its copy in
/// code: it is always presented in English and its rows have a fixed shape.
const Map<String, String> _endonyms = <String, String>{
  'zh-CN': '简体中文',
  'zh-TW': '繁體中文',
  'ja-JP': '日本語',
  'ko-KR': '한국어',
  'vi-VN': 'Tiếng Việt',
  'th-TH': 'ไทย',
  'id-ID': 'Bahasa Indonesia',
  'en-US': 'English (United States)',
  'en-GB': 'English (United Kingdom)',
  'fr-FR': 'Français',
  'de-DE': 'Deutsch',
  'es-ES': 'Español',
  'it-IT': 'Italiano',
  'pt-BR': 'Português (Brasil)',
  'ru-RU': 'Русский',
  'nl-NL': 'Nederlands',
  'pl-PL': 'Polski',
  'ar': 'العربية',
  'tr-TR': 'Türkçe',
};

/// Language picker.
///
/// Two behaviours differ from the rest of the app on purpose (spec §4):
///
/// * the screen is always in English, whatever locale is active, so the rows
///   stay comparable while the user is looking for their own language, and
/// * choosing a language only *stores* it — the current session keeps its
///   locale, and the choice takes effect on the next start. That is why this
///   activity never touches `FluentApp.locale`.
///
/// A monospaced face gives the list its table-like alignment; the bundled font
/// covers Latin only, so every row falls back per script for its endonym.
class LanguageActivity extends StatefulWidget {
  /// Creates the language picker.
  const LanguageActivity({super.key});

  /// Route used by the top bar's language button.
  static Route<void> get route => FluentPageRoute<void>(
    builder: (BuildContext context) => const LanguageActivity(),
  );

  @override
  State<LanguageActivity> createState() => _LanguageActivityState();
}

class _LanguageActivityState extends State<LanguageActivity> {
  /// Tag currently persisted in `SharedPreferences`, marked in the list.
  String? _persistedTag;

  @override
  void initState() {
    super.initState();
    _loadPersistedTag();
  }

  Future<void> _loadPersistedTag() async {
    final String? tag = await LocaleService.readPersistedTag();
    if (!mounted) {
      return;
    }
    setState(() => _persistedTag = tag);
  }

  Future<void> _select(String tag) async {
    await LocaleService.persistTag(tag);
    if (!mounted) {
      return;
    }
    // Deliberately no locale change: the new language applies next launch.
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: <Widget>[
          SafeArea(bottom: false, child: _Header(title: 'Language')),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 4, 24, 12),
            child: Text(
              'The selected language is applied the next time Rain FUI starts.',
              style: theme.typography.caption?.copyWith(
                color: resources.textFillColorSecondary,
              ),
              softWrap: true,
            ),
          ),
          Expanded(
            child: Scrollbar(
              child: ListView.separated(
                padding: const EdgeInsetsDirectional.only(bottom: 16),
                itemCount: kSupportedLanguageTags.length,
                separatorBuilder: (BuildContext context, int index) => Divider(
                  style: DividerThemeData(
                    horizontalMargin: EdgeInsets.zero,
                    thickness: 1,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: resources.dividerStrokeColorDefault,
                        ),
                      ),
                    ),
                  ),
                ),
                itemBuilder: (BuildContext context, int index) {
                  final String tag = kSupportedLanguageTags[index];
                  return _LanguageRow(
                    tag: tag,
                    endonym: _endonyms[tag] ?? tag,
                    selected: tag == _persistedTag,
                    onPressed: () => _select(tag),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fixed-height title strip with a back button.
class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    return Container(
      height: 48,
      width: double.infinity,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: resources.controlStrokeColorDefault),
        ),
      ),
      child: Row(
        children: <Widget>[
          Tooltip(
            message: 'Back',
            child: IconButton(
              icon: Icon(
                FluentIcons.arrow_left_24_regular,
                size: 16,
                color: resources.textFillColorPrimary,
              ),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.typography.subtitle?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// One `code endonym` row, monospaced so the codes line up like a table.
class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.tag,
    required this.endonym,
    required this.selected,
    required this.onPressed,
  });

  final String tag;
  final String endonym;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    final Color accent = theme.accentColor.normal;
    // The row text stays English-shaped, but the endonyms need the per-script
    // fallbacks of the Latin catalogue, which is the fallback locale here.
    final TextStyle mono = AppTheme.mono(
      theme.typography.body,
      kFallbackLocale,
    );

    return Semantics(
      selected: selected,
      child: SizedBox(
        height: 44,
        child: HoverButton(
          onPressed: onPressed,
          builder: (BuildContext context, Set<WidgetState> states) {
            final bool hovered = states.contains(WidgetState.hovered);
            final bool pressed = states.contains(WidgetState.pressed);
            return ColoredBox(
              color: selected
                  ? accent.withValues(alpha: pressed ? 0.20 : 0.12)
                  : pressed
                  ? resources.subtleFillColorTertiary
                  : hovered
                  ? resources.subtleFillColorSecondary
                  : theme.scaffoldBackgroundColor,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 0),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 18,
                      child: selected
                          ? Icon(
                              FluentIcons.checkmark_24_regular,
                              size: 14,
                              color: accent,
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$tag $endonym',
                        style: mono,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
