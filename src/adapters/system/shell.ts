import { $ } from 'bun';

export interface IShellRunner {
  platform(): Promise<string>;
}

export class BunShell implements IShellRunner {
  constructor(private readonly shell: typeof $ = $) {}

  async platform(): Promise<string> {
    return (await this.shell`uname -srm`.text()).trim();
  }
}
