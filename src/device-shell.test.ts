import { afterEach, describe, expect, it, vi } from "vitest";

afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); vi.resetModules(); });

function browserEnvironment(native: boolean, valid = true) {
  const listeners = new Map<string, (() => void)[]>();
  const register = vi.fn(async () => ({}));
  const handler = { postMessage: vi.fn() };
  const windowObject = {
    location: { origin: "http://127.0.0.1:43822", search: "?desktop=true&host=archi-desktop" },
    matchMedia: () => ({ matches: native, addEventListener: vi.fn() }),
    addEventListener: vi.fn((name: string, listener: () => void) => listeners.set(name, [...(listeners.get(name) ?? []), listener])),
    ...(native ? {
      __ARCHI_DESKTOP_BOOTSTRAP__: {
        version: valid ? 1 : 2, host: "archi-desktop", sessionId: "8A123456-ABCD-4BCD-8BCD-123456789ABC", visible: true,
      },
      webkit: { messageHandlers: { archiJourneyProjection: handler } },
    } : {}),
  };
  const navigatorObject = {
    vendor: "Apple", userAgent: "Mac", onLine: true,
    serviceWorker: { controller: null, register, addEventListener: vi.fn(), ready: new Promise(() => {}) },
  };
  vi.stubEnv("PROD", true);
  vi.stubGlobal("window", windowObject);
  vi.stubGlobal("navigator", navigatorObject);
  const install = { hidden: false, addEventListener: vi.fn() };
  const state = { textContent: "" };
  const copy = { textContent: "" };
  return { listeners, register, install, state, copy };
}

describe("native host app-shell exception", () => {
  it("disables browser registration and install handling only for the valid injected host", async () => {
    const env = browserEnvironment(true);
    const module = await import("./device-shell");
    module.setupDeviceShell({ installButton: env.install as unknown as HTMLButtonElement, stateLabel: env.state as HTMLElement, copy: env.copy as HTMLElement });
    expect(module.deviceShellSnapshot()).toMatchObject({ phase: "desktop-host", supported: false, standalone: false, controlled: false, registrationReady: false });
    expect(env.install.hidden).toBe(true);
    expect(env.install.addEventListener).not.toHaveBeenCalled();
    expect(env.listeners.has("load")).toBe(false);
    expect(env.listeners.has("beforeinstallprompt")).toBe(false);
    expect(env.register).not.toHaveBeenCalled();
    expect(env.copy.textContent).toMatch(/own on-device Journey.*Review.*Replace/);
  });

  it("a query string alone retains ordinary browser registration and installation behavior", async () => {
    const env = browserEnvironment(false);
    const module = await import("./device-shell");
    module.setupDeviceShell({ installButton: env.install as unknown as HTMLButtonElement, stateLabel: env.state as HTMLElement, copy: env.copy as HTMLElement });
    expect(module.deviceShellSnapshot()).toMatchObject({ phase: "browser", supported: true, standalone: false });
    expect(env.listeners.has("beforeinstallprompt")).toBe(true);
    expect(env.install.addEventListener).toHaveBeenCalled();
    env.listeners.get("load")![0]();
    expect(env.register).toHaveBeenCalledExactlyOnceWith("/service-worker.js", { scope: "/", updateViaCache: "none" });
  });

  it("an unsupported native-bootstrap version does not bypass installed-shell interlock", async () => {
    const env = browserEnvironment(true, false);
    const module = await import("./device-shell");
    module.setupDeviceShell({ installButton: env.install as unknown as HTMLButtonElement, stateLabel: env.state as HTMLElement, copy: env.copy as HTMLElement });
    expect(module.deviceShellSnapshot()).toMatchObject({ phase: "installed-shell-pending", supported: true, standalone: true, controlled: false });
    expect(env.listeners.has("load")).toBe(true);
  });
});
