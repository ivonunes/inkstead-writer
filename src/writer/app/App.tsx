import { type ReactNode, useEffect, useMemo, useRef, useState } from "react";
import { createRepositoryAdapter } from "./adapters/factory.js";
import type { RepositoryAdapter } from "./adapters/types.js";
import { loadWriterConfig, type WriterPublicConfig } from "./core/config.js";
import { getRememberedToken } from "./core/session.js";
import { ConnectRepository } from "./routes/ConnectRepository.js";
import { Editor } from "./routes/Editor.js";
import { PostList } from "./routes/PostList.js";
import { Preview } from "./routes/Preview.js";

type Route =
  | { name: "connect" }
  | { name: "posts" }
  | { name: "new" }
  | { name: "edit"; path: string }
  | { name: "preview"; path: string };

type TransitionDirection = "forward" | "back";

const routeDepth: Record<Route["name"], number> = {
  connect: 0,
  posts: 1,
  new: 2,
  edit: 2,
  preview: 3
};

function parseRoute(): Route {
  const hash = window.location.hash.replace(/^#/, "") || "/connect";
  const parts = hash.split("/");
  if (hash === "/posts") return { name: "posts" };
  if (hash === "/new") return { name: "new" };
  if (parts[1] === "edit" && parts[2]) return { name: "edit", path: decodeURIComponent(parts.slice(2).join("/")) };
  if (parts[1] === "preview" && parts[2]) return { name: "preview", path: decodeURIComponent(parts.slice(2).join("/")) };
  return { name: "connect" };
}

export function navigate(route: string): void {
  window.location.hash = route;
}

export function shouldRedirectConnectToPosts(config: WriterPublicConfig | undefined, token: string | undefined, route: Pick<Route, "name">): boolean {
  if (route.name !== "connect" || !config) return false;
  return config.provider === "local" || Boolean(token);
}

export function App(): JSX.Element {
  const [config, setConfig] = useState<WriterPublicConfig>();
  const [token, setToken] = useState<string | undefined>(() => getRememberedToken());
  const [route, setRoute] = useState<Route>(parseRoute);
  const [error, setError] = useState<string>();
  const [direction, setDirection] = useState<TransitionDirection>("forward");
  const previousRoute = useRef(route);
  const hasNavigated = useRef(false);

  useEffect(() => {
    loadWriterConfig().then(setConfig).catch((err: Error) => setError(err.message));
    const onHashChange = () => {
      const nextRoute = parseRoute();
      setDirection(routeDepth[nextRoute.name] < routeDepth[previousRoute.current.name] ? "back" : "forward");
      previousRoute.current = nextRoute;
      hasNavigated.current = true;
      setRoute(nextRoute);
    };
    window.addEventListener("hashchange", onHashChange);
    return () => window.removeEventListener("hashchange", onHashChange);
  }, []);

  const adapter = useMemo<RepositoryAdapter | undefined>(() => {
    if (!config) return undefined;
    if (config.provider !== "local" && !token) return undefined;
    return createRepositoryAdapter(config, token);
  }, [config, token]);

  useEffect(() => {
    if (shouldRedirectConnectToPosts(config, token, route)) navigate("/posts");
  }, [config, route.name, token]);

  function screen(content: ReactNode): JSX.Element {
    return <div key={`${route.name}${"path" in route ? route.path : ""}`} className={`route-screen ${hasNavigated.current ? `route-${direction}` : "route-initial"}`}>{content}</div>;
  }

  if (error) return screen(<main className="shell"><p className="error">{error}</p></main>);
  if (!config) return screen(<main className="shell"><p>Loading Writer...</p></main>);
  if (!adapter || route.name === "connect") {
    return screen(<ConnectRepository config={config} onConnected={(nextToken) => {
      setToken(nextToken);
      navigate("/posts");
    }} />);
  }
  if (route.name === "new") return screen(<Editor adapter={adapter} config={config} />);
  if (route.name === "edit") return screen(<Editor adapter={adapter} config={config} postPath={route.path} />);
  if (route.name === "preview") return screen(<Preview adapter={adapter} postPath={route.path} />);
  return screen(<PostList adapter={adapter} />);
}
