import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'malayalam.dart';

const supportedAppLocales = [Locale('en'), Locale('ml')];
const _languageKey = 'app_language';

final appLocaleProvider = NotifierProvider<AppLocale, Locale?>(AppLocale.new);

class AppLocale extends Notifier<Locale?> {
  @override
  Locale? build() => null;

  Future<void> restore() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_languageKey);
    if (state != null || saved == null) return;
    for (final locale in supportedAppLocales) {
      if (locale.languageCode == saved) state = locale;
    }
  }

  Future<void> select(Locale locale) async {
    state = locale;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_languageKey, locale.languageCode);
  }
}

extension AppTranslation on BuildContext {
  String get dateLocale =>
      Localizations.maybeLocaleOf(this)?.languageCode == 'ml' ? 'ml' : 'en_US';

  String tr(String english, [List<Object?> arguments = const []]) {
    final template =
        dateLocale == 'ml' ? malayalam[english] ?? english : english;
    if (arguments.isEmpty) return template;
    return template.replaceAllMapped(
      RegExp(r'\{(\d+)\}'),
      (match) => arguments[int.parse(match[1]!)].toString(),
    );
  }
}

String languageName(Locale locale) =>
    locale.languageCode == 'ml' ? 'മലയാളം' : 'English';

class LanguagePickerButton extends ConsumerWidget {
  const LanguagePickerButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      onPressed: () => showLanguagePicker(context, ref),
      icon: const Icon(Icons.language),
      label: Text(languageName(Localizations.localeOf(context))),
    );
  }
}

Future<void> showLanguagePicker(BuildContext context, WidgetRef ref) async {
  final current = Localizations.localeOf(context).languageCode;
  final locale = await showDialog<Locale>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(context.tr('Language')),
      children: [
        for (final locale in supportedAppLocales)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, locale),
            child: Row(
              children: [
                Expanded(child: Text(languageName(locale))),
                if (locale.languageCode == current) const Icon(Icons.check),
              ],
            ),
          ),
      ],
    ),
  );
  if (locale != null && context.mounted) {
    await ref.read(appLocaleProvider.notifier).select(locale);
  }
}
