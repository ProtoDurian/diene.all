import { describe, expect, it } from 'bun:test';
import { CommitLinter } from '../../../src/lib/commits/linter';
import type { ReleaserConfig } from '../../../src/lib/config/model';
import { TEST_CONFIG } from '../../helpers/fakes';

describe('commit linter', () => {
  const subject = new CommitLinter();

  it('should accept valid scoped, unscoped, breaking, and ignored messages', () => {
    // Arrange
    const messages = [
      'feat: add release',
      'fix: repair behavior\n\nThis body is comfortably long enough.',
      'feat(api)!: replace behavior',
      'feat: replace behavior\n\nBREAKING CHANGE: This body describes the incompatible change.',
      'feat: replace behavior\n\nBREAKING CHANGES: This body describes the incompatible changes.',
      'Merge branch main',
    ];

    // Act
    const actual = messages.map(message => subject.lint(message, TEST_CONFIG));

    // Assert
    expect(actual).toEqual(messages.map(() => []));
  });

  it('should enforce Gitlint title/body parity rules', () => {
    // Arrange
    const input = ` WIP bad\ttitle.\nbody without blank line \t`;

    // Act
    const actual = subject.lint(input, TEST_CONFIG);

    // Assert
    expect(actual.map(item => item.rule)).toEqual(['T4', 'T3', 'T5', 'T6', 'CT1', 'B4', 'B2', 'B3']);
  });

  it('should concatenate body lines directly at the 19-versus-20 boundary', () => {
    // Arrange
    const input = 'feat: add release\n\n1234567890\n123456789';

    // Act
    const actual = subject.lint(input, TEST_CONFIG);

    // Assert
    expect(actual.map(item => item.rule)).toEqual(['B5']);
  });

  it('should use Unicode code-point counts for title, body-line, and body-total limits', () => {
    // Arrange
    const config: ReleaserConfig = {
      ...TEST_CONFIG,
      lint: {
        ...TEST_CONFIG.lint,
        header: { ...TEST_CONFIG.lint.header, maxLength: 7 },
        body: { ...TEST_CONFIG.lint.body, maxLineLength: 1, minLengthWhenPresent: 2 },
      },
    };

    // Act
    const actual = subject.lint('feat: 😀\n\n😀', config);

    // Assert
    expect(actual.map(item => item.rule)).toEqual(['B5']);
  });

  it('should reject unknown types/scopes and malformed breaking trailers', () => {
    // Arrange
    const malformedTrailer = 'feat: do a thing\n\nBREAKING CHANGE without colon';

    // Act
    const unknownType = subject.lint('unknown: do a thing', TEST_CONFIG);
    const unknownScope = subject.lint('feat(nope): do a thing', TEST_CONFIG);
    const trailer = subject.lint(malformedTrailer, TEST_CONFIG);

    // Assert
    expect(unknownType[0]?.message).toContain('unknown commit type');
    expect(unknownScope[0]?.message).toContain('unknown scope');
    expect(trailer.map(item => item.rule)).toContain('CT1');
  });

  it('should ignore Git comment lines without losing source line numbers', () => {
    // Arrange
    const input = 'feat: add release\n\n# generated comment\nshort';

    // Act
    const actual = subject.lint(input, TEST_CONFIG);

    // Assert
    expect(actual.find(item => item.rule === 'B5')?.line).toBe(4);
  });

  it('should treat a leading blank as the title and cut at the Git scissors line', () => {
    // Arrange
    const scissorsInput =
      'feat: add release\n\nThis body is comfortably long enough.\n# ------------------------ >8 ------------------------\ninvalid trailing content.';

    // Act
    const leadingBlank = subject.lint('\nfeat: add release', TEST_CONFIG);
    const scissors = subject.lint(scissorsInput, TEST_CONFIG);

    // Assert
    expect(leadingBlank.map(item => item.rule)).toEqual(expect.arrayContaining(['T8', 'CT1', 'B4']));
    expect(leadingBlank.every(item => item.line === 1 || item.line === 2)).toBe(true);
    expect(scissors).toEqual([]);
  });

  it('should report the remaining header, body-line, and empty-message rules', () => {
    // Arrange
    const config: ReleaserConfig = {
      ...TEST_CONFIG,
      lint: {
        ...TEST_CONFIG.lint,
        header: { ...TEST_CONFIG.lint.header, maxLength: 10 },
        body: { ...TEST_CONFIG.lint.body, maxLineLength: 5 },
      },
    };

    // Act
    const tooLong = subject.lint('feat: a subject that is too long\nbody-too-long', config);
    const blankSubject = subject.lint('feat:  ', config);
    const commentOnly = subject.lint('# comment only', config);

    // Assert
    expect(tooLong.map(item => item.rule)).toEqual(['T1', 'B4', 'B1']);
    expect(blankSubject.map(item => item.rule)).toEqual(['T2', 'CT1']);
    expect(commentOnly).toEqual([{ line: 1, rule: 'CT1', message: 'commit message is empty' }]);
  });
});
