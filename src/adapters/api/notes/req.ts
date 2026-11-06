import { z } from 'zod';

export const NoteIdParam = z.object({ id: z.uuid() });

export const CreateNoteBody = z
  .object({
    title: z.string().trim().min(1).max(200),
    body: z.string().max(20_000),
  })
  .strict();

export const UpdateNoteBody = CreateNoteBody.partial().refine(
  patch => patch.title !== undefined || patch.body !== undefined,
  { message: 'provide title, body or both' },
);

export const ShareNoteBody = z.object({ to: z.email() }).strict();
