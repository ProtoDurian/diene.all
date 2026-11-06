import type { Job } from '../../../lib/jobs/structures';
import type { Note } from '../../../lib/notes/structures';

export interface NoteWire {
  readonly id: string;
  readonly title: string;
  readonly body: string;
  readonly createdAt: string;
}

export interface ShareWire {
  readonly jobId: string;
  readonly status: string;
}

export class NoteWireMapper {
  constructor(private readonly instant: (date: Date) => string = date => date.toISOString()) {}

  note(note: Note): NoteWire {
    return { id: note.id, title: note.title, body: note.body, createdAt: this.instant(note.createdAt) };
  }

  list(notes: readonly Note[]): { readonly items: readonly NoteWire[] } {
    return { items: notes.map(note => this.note(note)) };
  }

  share(job: Job): ShareWire {
    return { jobId: job.id, status: job.status };
  }
}
