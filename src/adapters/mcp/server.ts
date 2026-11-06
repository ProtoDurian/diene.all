import type { TenantIdentity } from '../../lib/auth/structures';

export interface McpNote {
  readonly id: string;
  readonly title: string;
  readonly body: string;
  readonly createdAt: Date | string;
}

export interface IMcpNotesReader {
  list(tenantId: string): Promise<readonly McpNote[]>;
}

type JsonRpcId = string | number;

interface JsonRpcRequest {
  readonly id?: JsonRpcId;
  readonly method: string;
  readonly params?: Record<string, unknown>;
}

const PROTOCOL_VERSIONS = ['2025-06-18', '2025-03-26'];

const LIST_NOTES_TOOL = {
  name: 'list_notes',
  description: "List the notes of the caller's tenant.",
  inputSchema: { type: 'object', properties: {}, additionalProperties: false },
};

// A minimal stateless MCP server (JSON-RPC over streamable HTTP, JSON responses only).
export class McpServer {
  constructor(private readonly notes: IMcpNotesReader) {}

  async handle(body: unknown, identity: TenantIdentity): Promise<unknown> {
    if (Array.isArray(body)) {
      const replies = await Promise.all(body.map(message => this.one(message, identity)));
      const answered = replies.filter(reply => reply !== undefined);
      return answered.length > 0 ? answered : undefined;
    }
    return this.one(body, identity);
  }

  private async one(message: unknown, identity: TenantIdentity): Promise<unknown> {
    if (!this.isRequest(message)) return this.error(null, -32600, 'Invalid Request');
    const { id, method, params } = message;
    if (id === undefined) return undefined;
    switch (method) {
      case 'initialize':
        return this.result(id, {
          protocolVersion: this.negotiate(params?.protocolVersion),
          capabilities: { tools: { listChanged: false } },
          serverInfo: { name: 'aseity', version: '0.1.0' },
        });
      case 'ping':
        return this.result(id, {});
      case 'tools/list':
        return this.result(id, { tools: [LIST_NOTES_TOOL] });
      case 'tools/call':
        return this.call(id, params, identity);
      default:
        return this.error(id, -32601, `Method not found: ${method}`);
    }
  }

  private async call(id: JsonRpcId, params: Record<string, unknown> | undefined, identity: TenantIdentity) {
    if (params?.name !== LIST_NOTES_TOOL.name) return this.error(id, -32602, `Unknown tool: ${String(params?.name)}`);
    const notes = await this.notes.list(identity.tenantId);
    const items = notes.map(note => ({
      id: note.id,
      title: note.title,
      body: note.body,
      createdAt: typeof note.createdAt === 'string' ? note.createdAt : note.createdAt.toISOString(),
    }));
    return this.result(id, {
      content: [{ type: 'text', text: JSON.stringify({ items }) }],
      structuredContent: { items },
    });
  }

  private negotiate(requested: unknown): string {
    return typeof requested === 'string' && PROTOCOL_VERSIONS.includes(requested)
      ? requested
      : (PROTOCOL_VERSIONS[0] as string);
  }

  private isRequest(message: unknown): message is JsonRpcRequest {
    if (typeof message !== 'object' || message === null) return false;
    const candidate = message as Record<string, unknown>;
    return candidate.jsonrpc === '2.0' && typeof candidate.method === 'string';
  }

  private result(id: JsonRpcId, result: unknown) {
    return { jsonrpc: '2.0', id, result };
  }

  private error(id: JsonRpcId | null, code: number, message: string) {
    return { jsonrpc: '2.0', id, error: { code, message } };
  }
}
