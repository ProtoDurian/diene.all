import type { Mailer } from '../../lib/mail/interfaces';
import type { MailMessage } from '../../lib/mail/structures';

const DEFAULT_MAIL_ENDPOINT = 'https://api.resend.com/emails';

export class MailDeliveryError extends Error {
  constructor(readonly status: number) {
    super(`mail provider rejected the message with HTTP ${status}`);
    this.name = 'MailDeliveryError';
  }
}

export class HttpMailer implements Mailer {
  constructor(
    private readonly from: string,
    private readonly apiKey: string,
    private readonly endpoint: string = DEFAULT_MAIL_ENDPOINT,
  ) {}

  async send(message: MailMessage): Promise<void> {
    const response = await fetch(this.endpoint, {
      method: 'POST',
      headers: { authorization: `Bearer ${this.apiKey}`, 'content-type': 'application/json' },
      body: JSON.stringify({ from: this.from, ...message }),
    });
    await response.body?.cancel();
    if (!response.ok) throw new MailDeliveryError(response.status);
  }
}
