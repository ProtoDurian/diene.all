import type { MailMessage } from './structures';

export interface Mailer {
  send(message: MailMessage): Promise<void>;
}
