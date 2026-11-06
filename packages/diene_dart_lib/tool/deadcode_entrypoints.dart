// Production dead-code root: references every public export so test_helper.dart counts as used.
import 'package:diene_dart_lib/diene_dart_lib.dart';
import 'package:diene_dart_lib/test_helper.dart';

void main() {
  const Note note = Note(
    title: 'Dead-code entrypoint',
    body: 'reference the public surface',
  );

  final Note roundTripped = Note.fromJson(note.toJson());
  final String summary = summarizeNote(
    roundTripped,
    maxLength: defaultSummaryLength,
  );

  assertNoteSummary(roundTripped, summary, maxLength: defaultSummaryLength);

  try {
    assertNoteSummary(roundTripped, 'wrong');
  } on NoteAssertionFailure catch (error) {
    if (error.message.isEmpty) rethrow;
  }
}
