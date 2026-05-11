const storageKey = "inkstead.writer.repositoryToken";

export function getRememberedToken(): string | undefined {
  try {
    return localStorage.getItem(storageKey) ?? undefined;
  } catch {
    return undefined;
  }
}

export function rememberToken(token: string): void {
  // Tokens are persisted only after the user explicitly chooses "Remember on this device".
  try {
    localStorage.setItem(storageKey, token);
  } catch {
    // Ignore storage access failures so connecting still works.
  }
}

export function forgetToken(): void {
  try {
    localStorage.removeItem(storageKey);
  } catch {
    // Ignore storage access failures.
  }
}
