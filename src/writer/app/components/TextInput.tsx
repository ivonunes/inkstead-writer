import type { InputHTMLAttributes } from "react";

export function TextInput(props: InputHTMLAttributes<HTMLInputElement>): JSX.Element {
  return <input className="text-input" {...props} />;
}
