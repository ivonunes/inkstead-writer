import type { PropsWithChildren } from "react";

export function Dialog({ children }: PropsWithChildren): JSX.Element {
  return <div className="dialog">{children}</div>;
}
