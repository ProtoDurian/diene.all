import chalk from 'chalk';

export interface ICliIo {
  success(message: string): void;
  warn(message: string): void;
  error(message: string): void;
  setExitCode(code: number): void;
  interactive(): boolean;
}

export class ConsoleIo implements ICliIo {
  constructor(private readonly output: Pick<Console, 'log' | 'error'> = console) {}

  success(message: string): void {
    this.output.log(chalk.green(message));
  }

  warn(message: string): void {
    this.output.log(chalk.yellow(message));
  }

  error(message: string): void {
    this.output.error(chalk.red(message));
  }

  setExitCode(code: number): void {
    process.exitCode = code;
  }

  interactive(): boolean {
    return Boolean(process.stdin.isTTY && process.stdout.isTTY);
  }
}
