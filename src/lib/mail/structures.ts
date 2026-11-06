export interface MailMessage {
  readonly to: string;
  readonly subject: string;
  readonly text: string;
  readonly html?: string;
}

export type MailTransport = 'http' | 'sink';

export interface MailSettings {
  readonly from: string;
  readonly apiKey?: string;
}
