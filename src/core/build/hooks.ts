import { spawn } from "node:child_process";

export async function runHookCommands(commands: string[] | undefined, root: string): Promise<void> {
  for (const command of commands ?? []) {
    await runHookCommand(command, root);
  }
}

function runHookCommand(command: string, root: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, {
      cwd: root,
      shell: true,
      stdio: "inherit",
      env: process.env
    });
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`Hook command failed (${code}): ${command}`));
      }
    });
  });
}
