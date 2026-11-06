import { describe, it } from 'bun:test';
import { expectErr, expectOk } from '@atomicloud/diene.result/test-helper';
import 'should';
import { ForkNaming } from '../../../src/lib/fork/naming';

describe('ForkNaming', () => {
  const subject = new ForkNaming({ database: 'aseity', bucket: 'files' });

  it.each(['a', 'demo', 'pr-42', 'x1'])('should accept the fork name "%s"', async name => {
    // Act
    const actual = await expectOk(subject.validate(name));

    // Assert
    actual.should.equal(name);
  });

  it.each([
    { name: '', reason: 'must be 1 to 24 characters' },
    { name: 'a'.repeat(25), reason: 'must be 1 to 24 characters' },
    { name: 'Demo', reason: 'must be lowercase letters, digits and single hyphens, starting with a letter' },
    { name: '1demo', reason: 'must be lowercase letters, digits and single hyphens, starting with a letter' },
    { name: 'demo-', reason: 'must be lowercase letters, digits and single hyphens, starting with a letter' },
    { name: 'de--mo', reason: 'must be lowercase letters, digits and single hyphens, starting with a letter' },
    { name: 'de_mo', reason: 'must be lowercase letters, digits and single hyphens, starting with a letter' },
  ])('should reject the fork name "$name"', async ({ name, reason }) => {
    // Act
    const actual = await expectErr(subject.validate(name));

    // Assert
    actual.should.deepEqual({ kind: 'invalid_name', name, reason });
  });

  it('should map a fork to a database name and back', async () => {
    // Act
    const database = await expectOk(subject.databaseName('pr-42'));
    const fork = subject.databaseFork(database);

    // Assert
    database.should.equal('aseity_fork_pr_42');
    (fork ?? '').should.equal('pr-42');
  });

  it('should map a fork to a bucket name and back', async () => {
    // Act
    const bucket = await expectOk(subject.bucketName('pr-42'));
    const fork = subject.bucketFork(bucket);

    // Assert
    bucket.should.equal('files-fork-pr-42');
    (fork ?? '').should.equal('pr-42');
  });

  it('should map a fork to a branch name and back', () => {
    // Act
    const branch = subject.branchName('pr-42');
    const fork = subject.branchFork(branch);

    // Assert
    branch.should.equal('fork-pr-42');
    (fork ?? '').should.equal('pr-42');
  });

  it.each(['main', 'fork-', 'aseity', 'other_fork_x'])('should not read "%s" as a fork', name => {
    // Act
    const actual = [subject.databaseFork(name), subject.bucketFork(name), subject.branchFork(name)];

    // Assert
    actual.should.deepEqual([undefined, undefined, undefined]);
  });

  it('should reject a fork whose resource name passes 63 characters', async () => {
    // Arrange
    const long = new ForkNaming({ database: 's'.repeat(40), bucket: 's'.repeat(40) });

    // Act
    const database = await expectErr(long.databaseName('abcdefghijklmnopqrstuvwx'));
    const bucket = await expectErr(long.bucketName('abcdefghijklmnopqrstuvwx'));

    // Assert
    database.kind.should.equal('invalid_name');
    bucket.kind.should.equal('invalid_name');
  });
});
