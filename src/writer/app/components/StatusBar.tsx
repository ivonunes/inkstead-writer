export function StatusBar({ status, error, busy = false }: { status: string; error?: string; busy?: boolean }): JSX.Element {
  return (
    <div className="status-bar" role="status" aria-live="polite">
      <span>{busy ? <span className="spinner" aria-hidden="true" /> : null}{status}</span>
      {error ? <strong>{error}</strong> : null}
    </div>
  );
}
