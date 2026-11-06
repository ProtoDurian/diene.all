export interface Stream {
  write(chunk: string): unknown;
}

export class Output {
  constructor(
    private readonly json: boolean,
    private readonly out: Stream,
    private readonly err: Stream,
  ) {}

  result(human: string, data: unknown): void {
    this.out.write(`${this.json ? JSON.stringify(data) : human}\n`);
  }

  error(human: string, data: unknown): void {
    this.err.write(`${this.json ? JSON.stringify({ error: data }) : `error: ${human}`}\n`);
  }

  text(human: string): void {
    this.out.write(`${human}\n`);
  }
}
