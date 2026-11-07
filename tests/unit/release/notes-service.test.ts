import { describe, expect, it } from 'bun:test';
import { NotesService } from '../../../src/lib/release/notes-service';
import { TEST_CONFIG } from '../../helpers/fakes';

describe('notes service', () => {
  const subject = new NotesService();

  it('should render first-release sections, hidden-type omission, links, and stable sorting', () => {
    // Arrange
    const commits = [
      { sha: '222222222222', message: 'feat(api): zebra' },
      { sha: '111111111111', message: 'feat: alpha' },
      { sha: '333333333333', message: 'docs: hidden' },
    ];

    // Act
    const actual = subject.render({
      config: TEST_CONFIG,
      version: '1.0.0',
      previousTag: null,
      newTag: 'v1.0.0',
      repositoryUrl: 'https://github.com/AtomiCloud/example',
      date: '2026-07-22',
      commits,
    });

    // Assert
    expect(actual).toStartWith('## 1.0.0 (2026-07-22)');
    // One blank line and dash bullets match what a markdown formatter keeps unchanged.
    expect(actual).toContain('## 1.0.0 (2026-07-22)\n\n### ✨ Features ✨');
    expect(actual).not.toContain('\n\n\n');
    expect(actual).toContain('\n- alpha (');
    expect(actual).not.toContain('\n* ');
    expect(actual.indexOf('alpha')).toBeLessThan(actual.indexOf('zebra'));
    expect(actual).toContain('- **api:** zebra');
    expect(actual).not.toContain('hidden');
    expect(actual).toContain('https://github.com/AtomiCloud/example/commit/111111111111');
  });

  it('should render a compare link after the first release', () => {
    // Arrange
    const commits = [{ sha: 'a'.repeat(40), message: 'feat: add release' }];

    // Act
    const actual = subject.render({
      config: TEST_CONFIG,
      version: '1.1.0',
      previousTag: 'v1.0.0',
      newTag: 'v1.1.0',
      repositoryUrl: 'https://github.com/AtomiCloud/example',
      date: '2026-07-22',
      commits,
    });

    // Assert
    expect(actual).toContain('/compare/v1.0.0...v1.1.0');
    expect(actual.endsWith('\n')).toBe(true);
  });

  it('should preserve input order when subject and scope sort keys are equal', () => {
    // Arrange
    const commits = [
      { sha: 'b'.repeat(40), message: 'feat(api): same subject' },
      { sha: 'a'.repeat(40), message: 'feat(api): same subject' },
    ];

    // Act
    const actual = subject.render({
      config: TEST_CONFIG,
      version: '1.0.0',
      previousTag: null,
      newTag: 'v1.0.0',
      repositoryUrl: 'https://github.com/AtomiCloud/example',
      date: '2026-07-22',
      commits,
    });

    // Assert
    expect(actual.indexOf('/commit/bbbbbbb')).toBeLessThan(actual.indexOf('/commit/aaaaaaa'));
  });
});
