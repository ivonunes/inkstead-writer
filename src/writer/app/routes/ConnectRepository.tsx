import { useState } from "react";
import { createRepositoryAdapter } from "../adapters/factory.js";
import { Button } from "../components/Button.js";
import { Dialog } from "../components/Dialog.js";
import { TextInput } from "../components/TextInput.js";
import type { WriterPublicConfig } from "../core/config.js";
import { rememberToken } from "../core/session.js";

function providerName(provider: WriterPublicConfig["provider"]): string {
  if (provider === "gitlab") return "GitLab";
  if (provider === "forgejo") return "Forgejo";
  if (provider === "github") return "GitHub";
  return "local";
}

function providerTokenHelp(config: WriterPublicConfig): string {
  if (config.provider === "forgejo") {
    return `Paste a Forgejo access token with write:repository permission for ${config.owner}/${config.repo}.`;
  }
  if (config.provider === "gitlab") {
    return `Paste a GitLab personal access token with access only to ${config.owner}/${config.repo} and repository contents read/write permissions.`;
  }
  return `Paste a GitHub fine-grained personal access token with access only to ${config.owner}/${config.repo} and repository contents read/write permissions.`;
}

export function ConnectRepository({ config, onConnected }: { config: WriterPublicConfig; onConnected: (token: string) => void }): JSX.Element {
  const [token, setToken] = useState("");
  const [remember, setRemember] = useState(false);
  const [status, setStatus] = useState("");
  const [error, setError] = useState<string>();

  async function connect(): Promise<void> {
    setStatus("Checking repository...");
    setError(undefined);
    try {
      await createRepositoryAdapter(config, token).validateConnection();
      if (remember) rememberToken(token);
      onConnected(token);
    } catch (err) {
      setStatus("");
      setError(err instanceof Error ? err.message : "Connection failed.");
    }
  }

  if (config.provider === "local") {
    return (
      <main className="connect-screen">
        <div className="connect-stack">
          <img className="connect-logo" src="./icons/inkstead-192.png" alt="" />
          <Dialog>
            <p className="eyebrow">Inkstead Writer</p>
            <h1>Local writing</h1>
            <p className="muted">The dev server is using the local filesystem adapter. Changes will be written to this working copy.</p>
            <div className="connect-actions">
              <Button onClick={() => onConnected("")}>Open Writer</Button>
            </div>
          </Dialog>
        </div>
      </main>
    );
  }

  return (
    <main className="connect-screen">
      <div className="connect-stack">
        <img className="connect-logo" src="./icons/inkstead-192.png" alt="" />
        <Dialog>
          <p className="eyebrow">Inkstead Writer</p>
          <h1>Connect repository</h1>
          <p className="muted">{providerTokenHelp(config)}</p>
          <TextInput type="password" value={token} onChange={(event) => setToken(event.target.value)} placeholder={`${providerName(config.provider)} token`} autoFocus />
          <label className="check-row">
            <input type="checkbox" checked={remember} onChange={(event) => setRemember(event.target.checked)} />
            Remember on this device
          </label>
          <div className="connect-actions">
            <Button onClick={connect} disabled={!token}>Connect</Button>
          </div>
          {status ? <p className="status-line">{status}</p> : null}
          {error ? <p className="error">{error}</p> : null}
        </Dialog>
      </div>
    </main>
  );
}
