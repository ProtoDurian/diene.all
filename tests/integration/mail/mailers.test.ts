import { afterAll, beforeAll, describe, it } from 'bun:test';
import type { Server } from 'bun';
import 'should';
import { HttpMailer, MailDeliveryError } from '../../../src/adapters/mail/http-mailer';
import { PolicyMailer } from '../../../src/adapters/mail/policy-mailer';
import { type SinkLog, SinkMailer } from '../../../src/adapters/mail/sink-mailer';
import type { IForkMarkerReader } from '../../../src/lib/db/interfaces';
import { MailPolicy } from '../../../src/lib/mail/service';

interface Received {
  readonly authorization: string | null;
  readonly body: unknown;
}

class RecordingSinkLog implements SinkLog {
  readonly entries: Record<string, unknown>[] = [];

  info(_message: string, fields: Record<string, unknown>): void {
    this.entries.push(fields);
  }
}

const API_KEY = crypto.randomUUID();
const REJECTED_KEY = crypto.randomUUID();

const marker = (isFork: boolean): IForkMarkerReader => ({ read: async () => ({ isFork }) });

describe('Mailers against a local HTTP mail API', () => {
  let server: Server<undefined>;
  let endpoint: string;
  const received: Received[] = [];
  const message = { to: 'b@example.com', subject: 'Hello', text: 'Body' };

  beforeAll(() => {
    server = Bun.serve({
      port: 0,
      fetch: async request => {
        received.push({ authorization: request.headers.get('authorization'), body: await request.json() });
        return new Response(request.headers.get('authorization') === `Bearer ${REJECTED_KEY}` ? 'no' : '{}', {
          status: request.headers.get('authorization') === `Bearer ${REJECTED_KEY}` ? 422 : 200,
        });
      },
    });
    endpoint = `http://127.0.0.1:${server.port}/emails`;
  });

  afterAll(() => {
    server?.stop(true);
  });

  it('should post the message with the sender and bearer key', async () => {
    // Arrange
    received.length = 0;
    const subject = new HttpMailer('app@example.com', API_KEY, endpoint);

    // Act
    await subject.send(message);

    // Assert
    received.should.deepEqual([{ authorization: `Bearer ${API_KEY}`, body: { from: 'app@example.com', ...message } }]);
  });

  it('should raise when the provider rejects the message', async () => {
    // Arrange
    const subject = new HttpMailer('app@example.com', REJECTED_KEY, endpoint);

    // Act
    const actual = await subject.send(message).catch(e => e);

    // Assert
    actual.should.be.instanceOf(MailDeliveryError).and.have.property('status', 422);
  });

  it('should only log the envelope from the sink', async () => {
    // Arrange
    const log = new RecordingSinkLog();

    // Act
    await new SinkMailer(log).send(message);

    // Assert
    log.entries.should.deepEqual([{ to: 'b@example.com', subject: 'Hello' }]);
  });

  it.each([
    { when: 'a fork has a key', isFork: true, apiKey: API_KEY, delivered: 0, sunk: 1 },
    { when: 'no key is set', isFork: false, apiKey: undefined, delivered: 0, sunk: 1 },
    { when: 'a key is set outside a fork', isFork: false, apiKey: API_KEY, delivered: 1, sunk: 0 },
  ])('should deliver $delivered and sink $sunk when $when', async ({ isFork, apiKey, delivered, sunk }) => {
    // Arrange
    received.length = 0;
    const log = new RecordingSinkLog();
    const settings = apiKey === undefined ? { from: 'app@example.com' } : { from: 'app@example.com', apiKey };
    const subject = new PolicyMailer(new MailPolicy(), settings, marker(isFork), new SinkMailer(log), endpoint);

    // Act
    await subject.send(message);

    // Assert
    received.length.should.equal(delivered);
    log.entries.length.should.equal(sunk);
  });
});
