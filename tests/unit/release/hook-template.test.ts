import { describe, expect, it } from 'bun:test';
import { HookTemplate } from '../../../src/lib/release/hook-template';

describe('hook template', () => {
  const subject = new HookTemplate();

  it('should render commit text without shell quoting', () => {
    // Arrange
    const template = 'release ${version}\n${notes}';

    // Act
    const actual = subject.renderText(template, '1.0.0', 'notes\n');

    // Assert
    expect(actual).toBe('release 1.0.0\nnotes');
  });

  it('should safely render unquoted, single-quoted, and double-quoted placeholders', () => {
    // Arrange
    const value = 'spaces \'single\' "double" $(touch pwned); echo bad\nnext';
    const template = 'hook ${version} \'${version}\' "${version}" ${notes} \'${notes}\' "${notes}"';

    // Act
    const actual = subject.renderCommand(template, value, `${value}\n`);

    // Assert
    expect(actual).toContain(`'${value.replaceAll("'", `'"'"'`)}'`);
    expect(actual).toContain(
      `"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('$', '\\$').replaceAll('`', '\\`')}"`,
    );
  });

  it('should reject ambiguous or unsupported shell quote states before execution', () => {
    // Arrange
    const render = (template: string) => () => subject.renderCommand(template, '1.0.0', 'notes');

    // Act
    const unterminated = render("hook '${version}");
    const escaped = render('hook \\${version}');
    const ansi = render("hook $'${version}'");

    // Assert
    expect(unterminated).toThrow('unterminated');
    expect(escaped).toThrow('must not escape');
    expect(ansi).toThrow('ANSI-C');
  });

  it('should preserve ordinary escapes and reject trailing escapes and NUL bytes', () => {
    // Arrange
    const render = (template: string, version: string, notes: string) => () =>
      subject.renderCommand(template, version, notes);

    // Act
    const ordinaryEscape = subject.renderCommand('printf "\\n" ${version}', '1.0.0', 'notes');
    const trailing = render('hook \\', '1.0.0', 'notes');
    const nulTemplate = render('hook\0${version}', '1.0.0', 'notes');
    const nulVersion = render('${version}', '1.0.0\0', 'notes');
    const nulNotes = render('${notes}', '1.0.0', 'notes\0');
    const locale = render('hook $"${version}"', '1.0.0', 'notes');

    // Assert
    expect(ordinaryEscape).toBe('printf "\\n" \'1.0.0\'');
    expect(trailing).toThrow('ambiguous escape');
    expect(nulTemplate).toThrow('hook template');
    expect(nulVersion).toThrow('hook version');
    expect(nulNotes).toThrow('hook notes');
    expect(locale).toThrow('locale quote');
  });
});
