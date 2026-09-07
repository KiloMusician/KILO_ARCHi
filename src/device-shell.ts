import { readDesktopHostBootstrap } from "./desktop-host";

export type DeviceShellPhase =
  | "desktop-host"
  | "browser"
  | "registered-next-launch"
  | "shell-active"
  | "offline-active"
  | "installed"
  | "installed-shell-pending"
  | "unavailable"
  | "error";

export interface DeviceShellSnapshot {
  phase: DeviceShellPhase;
  supported: boolean;
  production: boolean;
  online: boolean;
  standalone: boolean;
  installPromptAvailable: boolean;
  installOutcome: "none" | "accepted" | "dismissed";
  registrationReady: boolean;
  controlled: boolean;
  scope: string | null;
  workerUrl: string | null;
  updateViaCache: ServiceWorkerUpdateViaCache | null;
}

interface InstallChoice {
  outcome: "accepted" | "dismissed";
  platform: string;
}

interface BrowserInstallPrompt extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<InstallChoice>;
}

interface DeviceShellElements {
  installButton: HTMLButtonElement;
  stateLabel: HTMLElement;
  copy: HTMLElement;
  onSnapshot?: (snapshot: DeviceShellSnapshot) => void;
}

const production = import.meta.env.PROD;
const desktopHosted = readDesktopHostBootstrap(window) !== null;
const serviceWorkerSupported = !desktopHosted && production && "serviceWorker" in navigator;
const standaloneQuery = window.matchMedia("(display-mode: standalone)");
const appleStandalone = (navigator as Navigator & { standalone?: boolean }).standalone === true;
const appleBrowser = /Apple/i.test(navigator.vendor) && /Mac|iPhone|iPad|iPod/i.test(navigator.userAgent);
const canonicalWorkerUrl = new URL("/service-worker.js", window.location.origin).href;
const canonicalScope = new URL("/", window.location.origin).href;

function isCanonicalWorker(worker: ServiceWorker | null | undefined): worker is ServiceWorker {
  return worker?.scriptURL === canonicalWorkerUrl;
}

const snapshot: DeviceShellSnapshot = {
  phase: serviceWorkerSupported ? "browser" : "unavailable",
  supported: serviceWorkerSupported,
  production,
  online: navigator.onLine,
  standalone: !desktopHosted && (standaloneQuery.matches || appleStandalone),
  installPromptAvailable: false,
  installOutcome: "none",
  registrationReady: false,
  controlled: serviceWorkerSupported && isCanonicalWorker(navigator.serviceWorker.controller),
  scope: null,
  workerUrl:
    serviceWorkerSupported && isCanonicalWorker(navigator.serviceWorker.controller) ? canonicalWorkerUrl : null,
  updateViaCache: null,
};

let deferredInstallPrompt: BrowserInstallPrompt | null = null;
let elements: DeviceShellElements | null = null;

function derivePhase(): DeviceShellPhase {
  if (desktopHosted) return "desktop-host";
  if (!snapshot.supported) return "unavailable";
  if (snapshot.phase === "error") return "error";
  if (snapshot.standalone) return snapshot.controlled ? "installed" : "installed-shell-pending";
  if (snapshot.controlled) return snapshot.online ? "shell-active" : "offline-active";
  if (snapshot.registrationReady) return "registered-next-launch";
  return "browser";
}

function phaseLabel(phase: DeviceShellPhase): string {
  switch (phase) {
    case "desktop-host":
      return "Desktop play workspace";
    case "installed":
      return "Installed app shell";
    case "installed-shell-pending":
      return "App installed · reopen once";
    case "shell-active":
      return "App shell active";
    case "offline-active":
      return "Offline shell active";
    case "registered-next-launch":
      return "Shell registered · reopen once";
    case "browser":
      return "Browser tab";
    case "error":
      return "Shell unavailable";
    case "unavailable":
      return production ? "Browser install unavailable" : "Development preview";
  }
}

function phaseCopy(phase: DeviceShellPhase): string {
  const storageBoundary =
    "Installation adds a launch surface. The offline cache stores app files, never this Journey. Browser and installed copies may use separate local storage. To transfer a Journey, Download a copy, then Review and explicitly Replace it in the other copy.";
  switch (phase) {
    case "desktop-host":
      return "Play is hosted inside ARCHi. This workspace keeps its own on-device Journey. To transfer progress, Download a copy, then Review and explicitly Replace it here. Browser installation is not needed in this workspace.";
    case "installed":
      return `ARCHi is running from an installed shell. When its browser-managed cache remains available, it can reopen offline. ${storageBoundary}`;
    case "installed-shell-pending":
      return `Close and reopen ARCHi once to let the registered shell take control. ${storageBoundary}`;
    case "shell-active":
      return `The verified ARCHi shell controls this page. Its browser-managed cache can be cleared by the browser or you. ${storageBoundary}`;
    case "offline-active":
      return `The cached app shell is active without a network connection. ${storageBoundary}`;
    case "registered-next-launch":
      return `The verified shell is registered. Close and reopen ARCHi once to let it control the page. ${storageBoundary}`;
    case "browser":
      return `${
        appleBrowser
          ? "Use File or Share → Add to Dock / Add to Home Screen when your browser offers it."
          : "Use Install when it appears here, or your browser’s install command."
      } ${storageBoundary}`;
    case "error":
      return `The offline shell could not be prepared. The current local Journey is unchanged. ${storageBoundary}`;
    case "unavailable":
      return production
        ? `This browser does not expose the offline app-shell capability. ${storageBoundary}`
        : "Install and offline behavior are enabled only in the verified production build.";
  }
}

function renderDeviceShellState(): void {
  snapshot.phase = derivePhase();
  if (!elements) return;
  elements.stateLabel.textContent = phaseLabel(snapshot.phase);
  elements.copy.textContent = phaseCopy(snapshot.phase);
  elements.installButton.hidden = !snapshot.installPromptAvailable || snapshot.standalone;
  elements.onSnapshot?.({ ...snapshot });
}

function refreshControlState(): void {
  if (!serviceWorkerSupported) return;
  const controller = navigator.serviceWorker.controller;
  snapshot.controlled = isCanonicalWorker(controller);
  snapshot.workerUrl = snapshot.controlled ? canonicalWorkerUrl : null;
  renderDeviceShellState();
}

async function prepareServiceWorker(): Promise<void> {
  if (!serviceWorkerSupported) {
    renderDeviceShellState();
    return;
  }
  try {
    const registration = navigator.onLine
      ? await navigator.serviceWorker.register("/service-worker.js", {
          scope: "/",
          updateViaCache: "none",
        })
      : await navigator.serviceWorker.getRegistration("/");
    if (!registration) {
      renderDeviceShellState();
      return;
    }
    const ready = await navigator.serviceWorker.ready;
    const canonicalRegistration = ready.scope === canonicalScope && isCanonicalWorker(ready.active);
    snapshot.registrationReady = canonicalRegistration;
    snapshot.scope = canonicalRegistration ? ready.scope : null;
    snapshot.updateViaCache = canonicalRegistration ? ready.updateViaCache : null;
    snapshot.workerUrl = canonicalRegistration ? canonicalWorkerUrl : null;
    refreshControlState();
  } catch {
    snapshot.phase = "error";
    snapshot.registrationReady = false;
    renderDeviceShellState();
  }
}

async function requestInstall(): Promise<void> {
  const prompt = deferredInstallPrompt;
  if (!prompt) return;
  deferredInstallPrompt = null;
  snapshot.installPromptAvailable = false;
  renderDeviceShellState();
  try {
    await prompt.prompt();
    const choice = await prompt.userChoice;
    snapshot.installOutcome = choice.outcome;
  } catch {
    snapshot.installOutcome = "dismissed";
  }
  renderDeviceShellState();
}

export function setupDeviceShell(nextElements: DeviceShellElements): void {
  elements = nextElements;
  renderDeviceShellState();
  // Native bundles its app files and owns launch/update handling. Browser behavior stays unchanged.
  if (desktopHosted) return;
  elements.installButton.addEventListener("click", () => void requestInstall());

  window.addEventListener("beforeinstallprompt", ((event: Event) => {
    event.preventDefault();
    if (snapshot.standalone) return;
    deferredInstallPrompt = event as BrowserInstallPrompt;
    snapshot.installPromptAvailable = true;
    snapshot.installOutcome = "none";
    renderDeviceShellState();
  }) as EventListener);
  window.addEventListener("appinstalled", () => {
    deferredInstallPrompt = null;
    snapshot.installPromptAvailable = false;
    snapshot.installOutcome = "accepted";
    renderDeviceShellState();
  });
  window.addEventListener("online", () => {
    snapshot.online = true;
    renderDeviceShellState();
  });
  window.addEventListener("offline", () => {
    snapshot.online = false;
    renderDeviceShellState();
  });
  standaloneQuery.addEventListener("change", (event) => {
    snapshot.standalone = event.matches || appleStandalone;
    renderDeviceShellState();
  });
  if (serviceWorkerSupported) navigator.serviceWorker.addEventListener("controllerchange", refreshControlState);
  window.addEventListener("load", () => void prepareServiceWorker(), { once: true });
}

export function deviceShellSnapshot(): DeviceShellSnapshot {
  return { ...snapshot };
}
