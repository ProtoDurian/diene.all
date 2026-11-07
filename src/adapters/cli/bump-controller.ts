import type { Command } from 'commander';
import { type ReleaseService, userMessage } from '../../lib/release/release-service';
import type { ICliIo } from '../terminal/console-io';
import { EXIT_ERROR, EXIT_OK } from './exit-codes';

export class BumpController {
  constructor(
    private readonly releases: ReleaseService,
    private readonly io: ICliIo,
  ) {}

  register(program: Command): void {
    program
      .command('bump')
      // Positional, not --version: the root -v/--version would shadow it.
      .argument('<version>', 'version to stamp into the configured files')
      .description('stamp the configured version files without releasing')
      .option('-c, --config <path>', 'release configuration path', 'release.yaml')
      .action((version: string, options: { config: string }) => this.handle(version, options.config));
  }

  async handle(version: string, configPath: string): Promise<void> {
    try {
      const written = await this.releases.bump(version, configPath);
      this.io.write(
        written.length === 0
          ? `no bump entries configured in ${configPath}\n`
          : `${written.join('\n')}\nstamped to ${version}\n`,
      );
      this.io.setExitCode(EXIT_OK);
    } catch (error) {
      this.io.writeError(`${userMessage(error)}\n`);
      this.io.setExitCode(EXIT_ERROR);
    }
  }
}
