const storageKey = "inkstead.writer.repositoryToken";

export function getRememberedToken(): string | undefined {
  return localStorage.getItem(storageKey) ?? undefined;
}

export function rememberToken(token: string): void {
  // Tokens are persisted only after the user explicitly chooses "Remember on this device".
  localStorage.setItem(storageKey, token);
}

export function forgetToken(): void {
  localStorage.removeItem(storageKey);
}
