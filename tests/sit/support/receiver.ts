import { ProtobufReader } from './protobuf';

interface ReceivedExport {
  readonly path: string;
  readonly contentType: string | null;
  readonly body: ReturnType<typeof ProtobufReader.decode>;
}

class LoopbackOtlpReceiver {
  readonly received: ReceivedExport[] = [];
  private readonly server: ReturnType<typeof Bun.serve>;

  constructor() {
    this.server = Bun.serve({
      hostname: '127.0.0.1',
      port: 0,
      fetch: async request => {
        const raw = new Uint8Array(await request.arrayBuffer());
        const body = request.headers.get('content-encoding') === 'gzip' ? Bun.gunzipSync(raw) : raw;
        this.received.push({
          path: new URL(request.url).pathname,
          contentType: request.headers.get('content-type'),
          body: ProtobufReader.decode(body),
        });
        return new Response(new Uint8Array(), { headers: { 'content-type': 'application/x-protobuf' } });
      },
    });
  }

  get origin(): string {
    return `http://127.0.0.1:${this.server.port}`;
  }

  on(path: string): ReceivedExport[] {
    return this.received.filter(entry => entry.path === path);
  }

  async stop(): Promise<void> {
    await this.server.stop(true);
  }
}

export { LoopbackOtlpReceiver };
