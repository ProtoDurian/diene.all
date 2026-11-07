import { describe, it } from 'bun:test';
import { PortError } from '@atomicloud/diene.interfaces';
import 'should';
import { SafePath } from '../../src/lib/path';
import { expectErr, expectOk } from './support/result';

describe('SafePath.safeJoin', () => {
  it.each([
    { root: '/srv/app', segments: ['config', 'app.yaml'], expected: '/srv/app/config/app.yaml' },
    { root: '/srv/app', segments: ['a/./b', '../c'], expected: '/srv/app/a/c' },
    { root: '/srv/app', segments: [], expected: '/srv/app' },
    { root: '/srv/app', segments: ['/srv/app/inner'], expected: '/srv/app/inner' },
    { root: '/', segments: ['etc', 'hosts'], expected: '/etc/hosts' },
    { root: '/', segments: [], expected: '/' },
    { root: '/', segments: ['/etc/hosts'], expected: '/etc/hosts' },
    { root: '/srv/app', segments: ['', 'a', ''], expected: '/srv/app/a' },
  ])('should join $segments beneath $root', async ({ root, segments, expected }) => {
    // Arrange
    const safePath = new SafePath();

    // Act
    const actual = await expectOk(safePath.safeJoin(root, ...segments));

    // Assert
    actual.should.equal(expected);
  });

  it.each([
    { label: 'an empty root', root: '', segments: ['a'], message: /non-empty/ },
    { label: 'a relative root', root: 'srv/app', segments: ['a'], message: /absolute/ },
    { label: 'a dot-segment root', root: '/srv/../app', segments: [], message: /dot segments/ },
    { label: 'a parent traversal', root: '/srv/app', segments: ['..', 'etc'], message: /beneath root/ },
    { label: 'a sibling-prefix escape', root: '/srv/app', segments: ['../app-other'], message: /beneath root/ },
    { label: 'an absolute escape', root: '/srv/app', segments: ['/etc/passwd'], message: /beneath root/ },
    { label: 'a parent traversal under /', root: '/', segments: ['..'], message: /beneath root/ },
    { label: 'a nested traversal under /', root: '/', segments: ['a/../..'], message: /beneath root/ },
    { label: 'an absolute traversal under /', root: '/', segments: ['/..'], message: /beneath root/ },
    { label: 'a traversal after an empty segment', root: '/srv/app', segments: ['', '..'], message: /beneath root/ },
    { label: 'a re-entering traversal', root: '/srv/app', segments: ['..', 'app', 'x'], message: /beneath root/ },
    { label: 'a NUL segment', root: '/srv/app', segments: ['a\0b'], message: /NUL-free/ },
  ])('should return a vfs invalid-input Err for $label', async ({ root, segments, message }) => {
    // Arrange
    const safePath = new SafePath();

    // Act
    const actual = await expectErr(safePath.safeJoin(root, ...segments));

    // Assert
    actual.should.be.instanceof(PortError);
    actual.port.should.equal('vfs');
    actual.code.should.equal('invalid-input');
    actual.operation.should.equal('safeJoin');
    actual.message.should.match(message);
  });
});
