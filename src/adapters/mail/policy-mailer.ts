import type { IForkMarkerReader } from '../../lib/db/interfaces';
import type { Mailer } from '../../lib/mail/interfaces';
import type { MailPolicy } from '../../lib/mail/service';
import type { MailMessage, MailSettings } from '../../lib/mail/structures';
import { HttpMailer } from './http-mailer';
import type { SinkMailer } from './sink-mailer';

/** Picks the transport per message from the fork marker, so a fork can never send real mail. */
export class PolicyMailer implements Mailer {
  constructor(
    private readonly policy: MailPolicy,
    private readonly settings: MailSettings,
    private readonly fork: IForkMarkerReader,
    private readonly sink: SinkMailer,
    private readonly endpoint?: string,
  ) {}

  async send(message: MailMessage): Promise<void> {
    const marker = await this.fork.read();
    const { apiKey } = this.settings;
    if (this.policy.transport(this.settings, marker.isFork) === 'sink' || apiKey === undefined) {
      return this.sink.send(message);
    }
    return new HttpMailer(this.settings.from, apiKey, this.endpoint).send(message);
  }
}
