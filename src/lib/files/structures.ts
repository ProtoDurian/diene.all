export interface StoredFile {
  readonly body: ReadableStream<Uint8Array>;
  readonly contentType: string;
  readonly size: number;
}

export interface FileUpload {
  readonly body: ArrayBuffer;
  readonly contentType: string;
}

export interface StorageSettings {
  readonly endpoint: string;
  readonly bucket: string;
  readonly region: string;
  readonly accessKeyId: string;
  readonly secretAccessKey: string;
}
