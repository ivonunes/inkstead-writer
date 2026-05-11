import React from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App.js";
import { registerWriterServiceWorker } from "./core/pwa.js";
import "./styles/writer.css";

registerWriterServiceWorker();

createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
