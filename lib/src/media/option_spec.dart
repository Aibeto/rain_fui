/// Declarative description of one FFmpeg option.
///
/// The encode form renders itself from these objects instead of hard-coding a
/// widget per parameter, so covering the full option surface of an encoder or a
/// muxer costs a table entry, not a screenful of code.
library;

/// How an option is edited and how it turns into command-line arguments.
sealed class OptionSpec {
  const OptionSpec({
    required this.flag,
    this.labelKey,
    this.defaultValue,
    this.advanced = false,
  });

  /// The CLI flag, for example `-b:v`. Shown verbatim next to the label because
  /// it is a technical identifier, not prose.
  final String flag;

  /// i18n key of the human label, or null when the flag itself is the label.
  final String? labelKey;

  /// Value the form starts with; `null` means "leave the flag out".
  final String? defaultValue;

  /// Advanced options live behind the "more options" expander.
  final bool advanced;

  /// CLI fragment for [value], or an empty list when the flag must not appear.
  List<String> render(String? value);

  /// Normalised initial value used by the form state.
  String? get initialValue => defaultValue;
}

/// A checkbox that maps to the presence or absence of a bare flag.
class ToggleOption extends OptionSpec {
  const ToggleOption({
    required super.flag,
    required super.labelKey,
    super.defaultValue = '0',
    super.advanced,
  });

  @override
  List<String> render(String? value) =>
      (value == '1' || value == 'true') ? <String>[flag] : const <String>[];
}

/// A whole-number option with an optional range.
class IntOption extends OptionSpec {
  const IntOption({
    required super.flag,
    required super.labelKey,
    super.defaultValue,
    super.advanced,
    this.min,
    this.max,
    this.unit,
  });

  /// Smallest accepted value (inclusive).
  final int? min;

  /// Largest accepted value (inclusive).
  final int? max;

  /// Unit shown after the field, such as `kbps`. Not translated.
  final String? unit;

  @override
  List<String> render(String? value) {
    final int? parsed = int.tryParse((value ?? '').trim());
    if (parsed == null) {
      return const <String>[];
    }
    if ((min != null && parsed < min!) || (max != null && parsed > max!)) {
      return const <String>[];
    }
    return <String>[flag, parsed.toString()];
  }
}

/// A decimal option, used by rates, scaling factors and timestamps.
class DecimalOption extends OptionSpec {
  const DecimalOption({
    required super.flag,
    required super.labelKey,
    super.defaultValue,
    super.advanced,
    this.min,
    this.max,
    this.unit,
  });

  /// Smallest accepted value (inclusive).
  final double? min;

  /// Largest accepted value (inclusive).
  final double? max;

  /// Unit shown after the field. Not translated.
  final String? unit;

  @override
  List<String> render(String? value) {
    final double? parsed = double.tryParse((value ?? '').trim());
    if (parsed == null) {
      return const <String>[];
    }
    if ((min != null && parsed < min!) || (max != null && parsed > max!)) {
      return const <String>[];
    }
    return <String>[flag, parsed.toString()];
  }
}

/// One selectable value of a [ChoiceOption].
class OptionChoice {
  const OptionChoice(this.value, {this.labelKey});

  /// The literal passed to FFmpeg.
  final String value;

  /// i18n key of the displayed label; the raw [value] when null.
  final String? labelKey;
}

/// A drop-down over a fixed set of literals.
class ChoiceOption extends OptionSpec {
  const ChoiceOption({
    required super.flag,
    required super.labelKey,
    required this.choices,
    super.defaultValue,
    super.advanced,
  });

  /// Selectable literals, in display order.
  final List<OptionChoice> choices;

  @override
  List<String> render(String? value) {
    if (value == null || value.isEmpty) {
      return const <String>[];
    }
    final bool known = choices.any((OptionChoice c) => c.value == value);
    return known ? <String>[flag, value] : const <String>[];
  }

  /// Default rendered label for [value].
  String labelFor(String value) {
    for (final OptionChoice choice in choices) {
      if (choice.value == value) {
        return choice.labelKey ?? choice.value;
      }
    }
    return value;
  }
}

/// A free-form string, used by flags whose grammar is not a single token.
class TextOption extends OptionSpec {
  const TextOption({
    required super.flag,
    required super.labelKey,
    super.defaultValue,
    super.advanced,
    this.hint,
  });

  /// Example value shown as the field placeholder. Not translated.
  final String? hint;

  @override
  List<String> render(String? value) {
    final String trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? const <String>[] : <String>[flag, trimmed];
  }
}
