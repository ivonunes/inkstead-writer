import type { ButtonHTMLAttributes, PropsWithChildren, ReactNode } from "react";

export function Button({ children, className = "", icon, ...props }: PropsWithChildren<ButtonHTMLAttributes<HTMLButtonElement> & { icon?: ReactNode }>): JSX.Element {
  return (
    <button className={`button ${icon ? "has-icon" : ""} ${className}`.trim()} {...props}>
      {icon}
      <span className="button-label">{children}</span>
    </button>
  );
}
