export interface UserRole {
  readonly id: string;
  readonly email: string;
  readonly role?: string;
}

export interface AdminGranted {
  readonly email: string;
  readonly role: string;
  readonly changed: boolean;
}

export type AdminError =
  | { readonly kind: 'invalid_email'; readonly email: string }
  | { readonly kind: 'user_not_found'; readonly email: string }
  | { readonly kind: 'store_failed'; readonly message: string };
