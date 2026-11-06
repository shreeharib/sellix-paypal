/// The "## Saved answers" section of the shop profile, as a list.
///
/// The agent reads that section, and the backend keeps it when it rewrites the profile from the
/// onboarding answers (`modules/shop_profile/service.py`).
library;

const savedAnswersHeading = '## Saved answers';

/// What `PUT /v1/shop-profile` accepts.
const shopProfileLimit = 8000;

class SavedRule {
  const SavedRule({required this.question, required this.answer, required this.raw});

  /// A new or edited rule. Line breaks are flattened so it cannot break out of its section.
  factory SavedRule.written(String question, String answer) {
    final q = _oneLine(question);
    final a = _oneLine(answer);
    final joiner = RegExp(r'[?!.:]$').hasMatch(q) ? ' ' : ': ';
    return SavedRule(question: q, answer: a, raw: '- $q$joiner$a');
  }

  /// Reads a line of the section. The backend's lines look like "- Bulk orders: ask the owner.".
  factory SavedRule.parse(String line) {
    final text = line.trim().replaceFirst(RegExp(r'^[-*]\s+'), '');
    final split = RegExp(r'(\?\s+|:\s+)').firstMatch(text);
    if (split == null) return SavedRule(question: text, answer: '', raw: line.trim());
    final keepsMark = split.group(0)!.startsWith('?');
    return SavedRule(
      question: text.substring(0, split.start + (keepsMark ? 1 : 0)),
      answer: text.substring(split.end),
      raw: line.trim(),
    );
  }

  final String question;
  final String answer;

  /// The exact line, written back unchanged unless this rule is edited.
  final String raw;

  static String _oneLine(String text) => text.trim().replaceAll(RegExp(r'\s*\n\s*'), ' ');
}

/// The range of the section body, heading excluded, and the whole section. Null if absent.
({int start, int bodyStart, int end})? _section(String md) {
  final heading = RegExp('^${RegExp.escape(savedAnswersHeading)}[ \\t]*\$', multiLine: true).firstMatch(md);
  if (heading == null) return null;
  final next = RegExp(r'^## ', multiLine: true).allMatches(md).where((m) => m.start > heading.start);
  return (start: heading.start, bodyStart: heading.end, end: next.isEmpty ? md.length : next.first.start);
}

List<SavedRule> parseSavedRules(String? md) {
  if (md == null) return const [];
  final section = _section(md);
  if (section == null) return const [];
  return [
    for (final line in md.substring(section.bodyStart, section.end).split('\n'))
      if (line.trim().isNotEmpty) SavedRule.parse(line),
  ];
}

/// [md] with its section replaced by [rules]. Everything outside the section stays as it is. With no
/// rules left the heading goes too, and [fallbackTitle] starts a profile that has nothing else.
String withSavedRules(String? md, List<SavedRule> rules, {required String fallbackTitle}) {
  final text = (md ?? '').trim();
  final body = rules.isEmpty ? '' : '$savedAnswersHeading\n${rules.map((r) => r.raw).join('\n')}';
  final section = _section(text);
  final String result;
  if (section == null) {
    result = body.isEmpty ? text : (text.isEmpty ? body : '$text\n$body');
  } else {
    final before = text.substring(0, section.start).trimRight();
    final after = text.substring(section.end).trimLeft();
    result = [before, body, after].where((part) => part.isNotEmpty).join('\n');
  }
  if (result.isEmpty) return '# $fallbackTitle';
  return result.startsWith(savedAnswersHeading) ? '# $fallbackTitle\n$result' : result;
}
