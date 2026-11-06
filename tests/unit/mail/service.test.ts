import { describe, it } from 'bun:test';
import { expectErr, expectOk } from '@atomicloud/diene.result/test-helper';
import 'should';
import type { Job } from '../../../src/lib/jobs/structures';
import type { Mailer } from '../../../src/lib/mail/interfaces';
import { MAIL_JOB_KIND, MailJobHandler, MailPolicy, MailSettingsParser } from '../../../src/lib/mail/service';
import type { MailMessage } from '../../../src/lib/mail/structures';

class RecordingMailer implements Mailer {
  readonly sent: MailMessage[] = [];

  async send(message: MailMessage): Promise<void> {
    this.sent.push(message);
  }
}

const API_KEY = crypto.randomUUID();

const mailJob = (payload: Record<string, unknown>): Job => ({
  id: crypto.randomUUID(),
  tenantId: 'tenant-a',
  kind: MAIL_JOB_KIND,
  payload,
  outsideEffect: true,
  status: 'running',
  runAt: new Date(),
  attempts: 1,
});

describe('MailPolicy', () => {
  it.each([
    { when: 'a fork has a key', isFork: true, apiKey: API_KEY, expected: 'sink' },
    { when: 'no key is set', isFork: false, apiKey: undefined, expected: 'sink' },
    { when: 'a key is set outside a fork', isFork: false, apiKey: API_KEY, expected: 'http' },
  ])('should pick $expected when $when', ({ isFork, apiKey, expected }) => {
    // Arrange
    const subject = new MailPolicy();
    const settings = apiKey === undefined ? { from: 'app@example.com' } : { from: 'app@example.com', apiKey };

    // Act
    const actual = subject.transport(settings, isFork);

    // Assert
    actual.should.equal(expected);
  });

  it('should turn a message into an outside-effect mail job', () => {
    // Arrange
    const subject = new MailPolicy();

    // Act
    const actual = subject.job({ to: 'a@example.com', subject: 'Hi', text: 'Body' });

    // Assert
    actual.should.deepEqual({
      kind: 'mail.send',
      payload: { to: 'a@example.com', subject: 'Hi', text: 'Body' },
      outsideEffect: true,
    });
  });
});

describe('MailJobHandler', () => {
  it('should send the job payload as a message', async () => {
    // Arrange
    const mailer = new RecordingMailer();
    const subject = new MailJobHandler(mailer);

    // Act
    await subject.handle(mailJob({ to: 'a@example.com', subject: 'Hi', text: 'Body', html: '<p>Body</p>' }));

    // Assert
    subject.kind.should.equal('mail.send');
    mailer.sent.should.deepEqual([{ to: 'a@example.com', subject: 'Hi', text: 'Body', html: '<p>Body</p>' }]);
  });

  it('should reject a payload that is not a message', async () => {
    // Arrange
    const mailer = new RecordingMailer();
    const subject = new MailJobHandler(mailer);

    // Act
    const attempt = subject.handle(mailJob({ to: 'not an email' }));

    // Assert
    await attempt.should.be.rejected();
    mailer.sent.should.deepEqual([]);
  });
});

describe('MailSettingsParser', () => {
  it('should keep the provider key when one is set', async () => {
    // Arrange
    const subject = new MailSettingsParser();

    // Act
    const actual = await expectOk(subject.parse({ MAIL_FROM: 'app@example.com', MAIL_API_KEY: API_KEY }));

    // Assert
    actual.should.deepEqual({ from: 'app@example.com', apiKey: API_KEY });
  });

  it('should treat a blank provider key as unset', async () => {
    // Arrange
    const subject = new MailSettingsParser();

    // Act
    const actual = await expectOk(subject.parse({ MAIL_FROM: 'app@example.com', MAIL_API_KEY: '' }));

    // Assert
    actual.should.deepEqual({ from: 'app@example.com' });
  });

  it('should reject a missing sender', async () => {
    // Arrange
    const subject = new MailSettingsParser();

    // Act
    const actual = await expectErr(subject.parse({}));

    // Assert
    actual.issues.map(issue => issue.path.join('.')).should.deepEqual(['MAIL_FROM']);
  });
});
