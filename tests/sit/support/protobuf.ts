type Field = bigint | Uint8Array;
type Message = ReadonlyMap<number, readonly Field[]>;

class ProtobufReader {
  private offset = 0;

  constructor(private readonly bytes: Uint8Array) {}

  static decode(bytes: Uint8Array): Message {
    return new ProtobufReader(bytes).message();
  }

  static text(field: Field | undefined): string {
    return field instanceof Uint8Array ? new TextDecoder().decode(field) : '';
  }

  static messages(message: Message, number: number): Message[] {
    return (message.get(number) ?? []).flatMap(field =>
      field instanceof Uint8Array ? [ProtobufReader.decode(field)] : [],
    );
  }

  private message(): Message {
    const fields = new Map<number, Field[]>();
    while (this.offset < this.bytes.length) {
      const tag = this.varint();
      const number = Number(tag >> 3n);
      const value = this.value(Number(tag & 7n));
      if (value !== undefined) fields.set(number, [...(fields.get(number) ?? []), value]);
    }
    return fields;
  }

  private value(wireType: number): Field | undefined {
    if (wireType === 0) return this.varint();
    if (wireType === 2) return this.take(Number(this.varint()));
    if (wireType === 1) this.take(8);
    else if (wireType === 5) this.take(4);
    else throw new Error(`unsupported protobuf wire type ${wireType}`);
    return undefined;
  }

  private varint(): bigint {
    let result = 0n;
    for (let shift = 0n; ; shift += 7n) {
      const byte = this.bytes[this.offset++];
      if (byte === undefined) throw new Error('truncated varint');
      result |= BigInt(byte & 0x7f) << shift;
      if ((byte & 0x80) === 0) return result;
    }
  }

  private take(length: number): Uint8Array {
    const slice = this.bytes.subarray(this.offset, this.offset + length);
    this.offset += length;
    return slice;
  }
}

// Field numbers from opentelemetry/proto: resource=1 and scope list=2 on every Resource* message.
function leaves(request: Message): Message[] {
  return ProtobufReader.messages(request, 1)
    .flatMap(resource => ProtobufReader.messages(resource, 2))
    .flatMap(scope => ProtobufReader.messages(scope, 2));
}

const OtlpPayload = {
  resourceAttributes(request: Message): Record<string, string> {
    const resource = ProtobufReader.messages(ProtobufReader.messages(request, 1)[0] ?? new Map(), 1)[0] ?? new Map();
    return Object.fromEntries(
      ProtobufReader.messages(resource, 1).map(pair => [
        ProtobufReader.text(pair.get(1)?.[0]),
        ProtobufReader.text(ProtobufReader.messages(pair, 2)[0]?.get(1)?.[0]),
      ]),
    );
  },
  spanNames: (request: Message): string[] => leaves(request).map(span => ProtobufReader.text(span.get(5)?.[0])),
  metricNames: (request: Message): string[] => leaves(request).map(metric => ProtobufReader.text(metric.get(1)?.[0])),
};

export { OtlpPayload, ProtobufReader };
