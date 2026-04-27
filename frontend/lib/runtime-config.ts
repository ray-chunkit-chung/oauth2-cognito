"use client";

// Runtime config values are delivered as a JSON file at app runtime
// (currently /config.json in S3/CloudFront).
//
// Why runtime config exists in this project:
// - Build-time NEXT_PUBLIC_* env vars are baked into static JS at build time.
// - Changing build-time values requires rebuilding/redeploying the frontend.
// - Runtime config lets us update selected values (for example API base URL)
//   during deploy by replacing /config.json without rebuilding bundles.
//
// Currently, the app is small and we are using small configs.
// Later on, if we have more config values or want to optimize loading,
// we should consider AWS AppConfig or similar managed config solutions.
//
// Current runtime-config keys:
// - chatApiBaseUrl: Base URL for frontend chat API requests.
type RuntimeConfig = {
  chatApiBaseUrl?: string;
};

// /config.json lifecycle:
// 1) Created during frontend CI/CD after static export as frontend/out/config.json
//    (.github/workflows/frontend.yml, "Write runtime config" step).
// 2) Uploaded to the S3 website bucket root as config.json and served by CloudFront.
// 3) Read by the browser at app startup and before API calls to resolve runtime values.
const CONFIG_PATH = "/config.json";
// Maximum number of fetch attempts for transient runtime-config load failures.
const MAX_FETCH_ATTEMPTS = 3;
// Base backoff delay in ms between retries (multiplied by attempt number).
const RETRY_BACKOFF_MS = 300;

// Indicates config exists but required key(s) are missing.
export class RuntimeConfigMissingError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RuntimeConfigMissingError";
  }
}

// Indicates config could not be fetched or parsed.
export class RuntimeConfigLoadError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RuntimeConfigLoadError";
  }
}

let runtimeConfigPromise: Promise<RuntimeConfig> | null = null;

// Small delay utility used for retry backoff.
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

// Executes one fetch+parse attempt for runtime config.
async function fetchRuntimeConfigOnce(): Promise<RuntimeConfig> {
  const response = await fetch(CONFIG_PATH, { cache: "no-store" });

  if (!response.ok) {
    throw new RuntimeConfigLoadError(
      `Failed to load ${CONFIG_PATH} (HTTP ${response.status}).`,
    );
  }

  try {
    return (await response.json()) as RuntimeConfig;
  } catch {
    throw new RuntimeConfigLoadError(`Invalid JSON returned from ${CONFIG_PATH}.`);
  }
}

// Loads runtime config with retry logic and shared in-memory promise cache.
async function loadRuntimeConfig(): Promise<RuntimeConfig> {
  if (!runtimeConfigPromise) {
    runtimeConfigPromise = (async () => {
      let lastError: unknown;

      // Retry a few times for transient network/CDN issues.
      for (let attempt = 1; attempt <= MAX_FETCH_ATTEMPTS; attempt += 1) {
        try {
          return await fetchRuntimeConfigOnce();
        } catch (error) {
          lastError = error;
          if (attempt < MAX_FETCH_ATTEMPTS) {
            await sleep(RETRY_BACKOFF_MS * attempt);
          }
        }
      }

      if (lastError instanceof Error) {
        throw lastError;
      }

      throw new RuntimeConfigLoadError(`Failed to load ${CONFIG_PATH}.`);
    })().catch((error) => {
      // Do not keep failed attempts cached forever.
      // This allows future calls (or user-triggered retry) to fetch again.
      runtimeConfigPromise = null;
      throw error;
    });
  }

  return runtimeConfigPromise;
}

// Public accessor for chat API base URL with validation and normalization.
export async function getChatApiBaseUrl(): Promise<string> {
  const runtimeConfig = await loadRuntimeConfig();
  const baseUrl = (runtimeConfig.chatApiBaseUrl ?? "").trim();

  if (!baseUrl) {
    throw new RuntimeConfigMissingError(
      "Missing chat API base URL in /config.json.",
    );
  }

  return baseUrl.replace(/\/$/, "");
}
