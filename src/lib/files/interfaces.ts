import type { FileUpload, StoredFile } from './structures';

export interface IFileStore {
  put(key: string, upload: FileUpload): Promise<void>;
  get(key: string): Promise<StoredFile | undefined>;
  delete(key: string): Promise<void>;
}
