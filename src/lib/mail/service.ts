import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { z } from 'zod';
import type { IJobHandler } from '../jobs/interfaces';
import type { Job, NewJob } from '../jobs/structures';
import type { Mailer } from './interfaces';
import type { MailMessage, MailSettings, MailTransport } from './structures';

export const MAIL_JOB_KIND = 'mail.send';

const MailMessageSchema = z.object({
  to: z.email(),
  subject: z.string().min(1),
  text: z.string(),
  html: z.string().optional(),
});

export class MailPolicy {
  constructor(private readonly jobKind = MAIL_JOB_KIND) {}

  /** A fork always sinks mail, whatever key it copied. */
  transport(settings: MailSettings, isFork: boolean): MailTransport {
    return isFork || settings.apiKey === undefined ? 'sink' : 'http';
  }

  job(message: MailMessage): NewJob {
    return { kind: this.jobKind, payload: { ...message }, outsideEffect: true };
  }
}

export class MailJobHandler implements IJobHandler {
  readonly kind = MAIL_JOB_KIND;

  constructor(private readonly mailer: Mailer) {}

  async handle(job: Job): Promise<void> {
    await this.mailer.send(MailMessageSchema.parse(job.payload));
  }
}

const MailEnvSchema = z.object({
  MAIL_FROM: z.string().min(1),
  MAIL_API_KEY: z.preprocess(value => (value === '' ? undefined : value), z.string().min(1).optional()),
});

export class MailSettingsParser {
  constructor(private readonly schema: typeof MailEnvSchema = MailEnvSchema) {}

  parse(env: Readonly<Record<string, unknown>>): Result<MailSettings, z.ZodError> {
    const parsed = this.schema.safeParse(env);
    if (!parsed.success) return Err(parsed.error);
    const { MAIL_FROM: from, MAIL_API_KEY: apiKey } = parsed.data;
    return Ok(apiKey === undefined ? { from } : { from, apiKey });
  }
}
