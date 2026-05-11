import type { SVGProps } from "react";

type IconProps = SVGProps<SVGSVGElement>;

function IconBase({ children, ...props }: IconProps): JSX.Element {
  return (
    <svg className="button-icon" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" {...props}>
      {children}
    </svg>
  );
}

export function ArrowLeftIcon(props: IconProps): JSX.Element {
  return <IconBase {...props}><path d="m12 19-7-7 7-7" /><path d="M19 12H5" /></IconBase>;
}

export function ImageIcon(props: IconProps): JSX.Element {
  return <IconBase {...props}><rect x="3" y="5" width="18" height="14" rx="2" /><circle cx="8.5" cy="10.5" r="1.5" /><path d="m21 15-5-5L5 19" /></IconBase>;
}

export function SaveIcon(props: IconProps): JSX.Element {
  return <IconBase {...props}><path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2Z" /><path d="M17 21v-8H7v8" /><path d="M7 3v5h8" /></IconBase>;
}

export function UploadIcon(props: IconProps): JSX.Element {
  return <IconBase {...props}><path d="M12 3v12" /><path d="m17 8-5-5-5 5" /><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" /></IconBase>;
}

export function EyeIcon(props: IconProps): JSX.Element {
  return <IconBase {...props}><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z" /><circle cx="12" cy="12" r="3" /></IconBase>;
}

export function TrashIcon(props: IconProps): JSX.Element {
  return <IconBase {...props}><path d="M3 6h18" /><path d="M8 6V4h8v2" /><path d="M19 6l-1 14H6L5 6" /><path d="M10 11v5" /><path d="M14 11v5" /></IconBase>;
}

export function PlusIcon(props: IconProps): JSX.Element {
  return <IconBase {...props}><path d="M12 5v14" /><path d="M5 12h14" /></IconBase>;
}
