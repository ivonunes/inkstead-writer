export type CiProviderName = "github-actions" | "gitlab-ci" | "forgejo-actions";
export type DeployProviderName = "cloudflare-workers" | "github-pages" | "gitlab-pages" | "netlify";
export type SyndicationProviderName = "mastodon" | "bluesky" | "flickr";
export type WriterProviderName = "github" | "gitlab" | "forgejo" | "local";

export interface WriterConfig {
  enabled?: boolean;
  path?: string;
  provider: WriterProviderName;
  owner?: string;
  repo?: string;
  branch?: string;
  instanceUrl?: string;
  categories?: string[];
}

export type PublicWriterConfig = Omit<WriterConfig, "enabled" | "path"> & {
  postsPath: string;
  mediaPath: string;
  syndicationProviders: SyndicationProviderName[];
  categories: string[];
};

export interface InksteadConfig {
  site: {
    title: string;
    url: string;
    author: string;
    description?: string;
    lang?: string;
    timezone?: string;
    email?: string;
    avatar?: string;
    bio?: string;
    navigation?: Array<{ name: string; url: string; icon?: string; className?: string }>;
    social?: Array<{ name: string; url: string; relMe?: boolean; icon?: string; className?: string }>;
  };
  content: {
    posts: string;
    pages: string;
    media: string;
  };
  build?: {
    output?: string;
  };
  hooks?: {
    beforeBuild?: string[];
    afterBuild?: string[];
  };
  urls?: {
    posts?: "dated" | "slug";
  };
  markdown?: {
    html?: boolean;
    breaks?: boolean;
  };
  assets?: {
    passthrough?: Array<{ from: string; to?: string }>;
  };
  photos?: {
    optimize?: boolean;
    maxWidth?: number;
    maxHeight?: number;
    quality?: number;
  };
  theme?: {
    path?: string;
    showPoweredBy?: boolean;
  };
  pagination?: {
    postsPerPage?: number;
  };
  feeds?: {
    limit?: number;
  };
  writer?: WriterConfig;
  ci?: {
    provider: CiProviderName;
  };
  deploy?:
    | { provider: "cloudflare-workers"; projectName: string }
    | { provider: "github-pages"; projectName?: string }
    | { provider: "gitlab-pages"; projectName?: string }
    | { provider: "netlify" };
  syndication?: {
    providers: SyndicationProviderName[];
  };
}
