"use client";

type RuntimeConfig = {
  chatApiBaseUrl?: string;
};

let runtimeConfigPromise: Promise<RuntimeConfig> | null = null;

async function loadRuntimeConfig(): Promise<RuntimeConfig> {
  if (!runtimeConfigPromise) {
    runtimeConfigPromise = fetch("/config.json", { cache: "no-store" })
      .then(async (response) => {
        if (!response.ok) {
          return {};
        }
        return (await response.json()) as RuntimeConfig;
      })
      .catch(() => ({}));
  }

  return runtimeConfigPromise;
}

export async function getChatApiBaseUrl(): Promise<string> {
  const runtimeConfig = await loadRuntimeConfig();
  const baseUrl = (runtimeConfig.chatApiBaseUrl ?? "").trim();

  if (!baseUrl) {
    throw new Error("Missing chat API base URL in /config.json.");
  }

  return baseUrl.replace(/\/$/, "");
}
