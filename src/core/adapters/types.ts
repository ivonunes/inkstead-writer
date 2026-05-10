import type { NormalizedPost } from "../content/types.js";

export interface GeneratedFile {
  path: string;
  content: string;
}

export interface AdapterRequirement {
  name: string;
  type: "secret" | "config";
  required: boolean;
  description: string;
  environmentVariable?: string;
  githubSecretName?: string;
}

export interface DoctorCheck {
  status: "pass" | "fail" | "warn";
  label: string;
  message?: string;
}

export interface DoctorContext {
  root: string;
  env: NodeJS.ProcessEnv;
}

export interface GenerateWorkflowOptions {
  environmentVariables: string[];
  deploymentProvider?: string;
  buildOutput?: string;
  hasSyndication?: boolean;
}

export interface DeploymentContext {
  root: string;
  distDir: string;
  projectName?: string;
  env: NodeJS.ProcessEnv;
}

export interface SyndicationContext {
  root: string;
  env: NodeJS.ProcessEnv;
}

export interface SyndicationResult {
  status: "published" | "failed";
  url?: string;
  id?: string;
  uri?: string;
  cid?: string;
  publishedAt?: string;
  error?: string;
}

export interface CiProvider {
  name: string;
  requirements(): AdapterRequirement[];
  generateWorkflow(options: GenerateWorkflowOptions): GeneratedFile[];
  doctor(context: DoctorContext): Promise<DoctorCheck[]>;
}

export interface DeploymentProvider {
  name: string;
  requirements(): AdapterRequirement[];
  prepare?(context: DeploymentContext): Promise<GeneratedFile[]>;
  deploy(context: DeploymentContext): Promise<void>;
  doctor(context: DoctorContext): Promise<DoctorCheck[]>;
}

export interface SyndicationProvider {
  name: string;
  requirements(): AdapterRequirement[];
  canSyndicate(post: NormalizedPost): boolean;
  publish(post: NormalizedPost, context: SyndicationContext): Promise<SyndicationResult>;
  doctor(context: DoctorContext): Promise<DoctorCheck[]>;
}
