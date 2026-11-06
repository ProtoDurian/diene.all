import type { Mailer } from '../../lib/mail/interfaces';
import type { MailMessage } from '../../lib/mail/structures';

export interface SinkLog {
  info(message: string, fields: Record<string, unknown>): void;
}

/** Never delivers: records the envelope in the Worker log. Forced in a fork. */
export class SinkMailer implements Mailer {
  constructor(private readonly log: SinkLog = console) {}

  async send(message: MailMessage): Promise<void> {
    this.log.info('mail sunk', { to: message.to, subject: message.subject });
  }
}
