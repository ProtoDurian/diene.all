import type { IJobKicker } from '../../lib/jobs/interfaces';

/** Remembers a kick; the runtime drains after the response, once the request transaction committed. */
export class DeferredKicker implements IJobKicker {
  constructor(private requested = false) {}

  kick(): void {
    this.requested = true;
  }

  get wanted(): boolean {
    return this.requested;
  }
}
