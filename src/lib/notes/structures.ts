import { z } from 'zod';

export interface NoteRecord {
  readonly title: string;
  readonly body: string;
}

export type NotePatch = Partial<NoteRecord>;

export interface Note extends NoteRecord {
  readonly id: string;
  readonly createdAt: Date;
}

export const NoteListSchema = z.array(
  z.object({ id: z.string(), title: z.string(), body: z.string(), createdAt: z.coerce.date() }),
);

export class NoteNotFound {
  readonly kind = 'note_not_found';
  constructor(readonly id: string) {}
}

export class AttachmentNotFound {
  readonly kind = 'attachment_not_found';
  constructor(readonly id: string) {}
}
