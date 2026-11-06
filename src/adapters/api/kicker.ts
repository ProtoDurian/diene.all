import type { IJobKicker } from '../../lib/jobs/interfaces';

export class DeferredKicker implements IJobKicker {
  constructor(private requested = false) {}

  kick(): void {
    this.requested = true;
  }

  get wanted(): boolean {
    return this.requested;
  }
}
