import {
  hydrateJourney,
  revisionForJourney,
  serializeJourney,
  sha256String,
  type Journey,
} from "./model";
import { parseJsonWithoutDuplicateKeys } from "./strict-json";

export const JOURNEY_ARCHIVE_FORMAT = "archi-journey";
export const JOURNEY_ARCHIVE_VERSION = 1;
export const MAX_JOURNEY_ARCHIVE_BYTES = 2 * 1024 * 1024;
export const MAX_JOURNEY_ARCHIVE_EVENTS = 2048;

export type JourneyRelation = "same" | "advance" | "rewind" | "divergent" | "different-origin";

export type JourneyArchiveErrorCode =
  | "archive-too-large"
  | "archive-too-many-events"
  | "invalid-json"
  | "invalid-envelope"
  | "unsupported-archive-version"
  | "unsupported-journey-version"
  | "unsupported-event-schema"
  | "incomplete-event-chain"
  | "invalid-authority"
  | "manifest-mismatch";

export interface JourneyArchivePreview {
  exportedAt: string;
  journey: Journey;
  journeyId: string;
  revision: string;
  eventCount: number;
  headEventId: string | null;
  authoritySha256: string;
}

export type JourneyArchiveInspection =
  | { status: "valid"; preview: JourneyArchivePreview }
  | { status: "invalid"; code: JourneyArchiveErrorCode; message: string };

interface ArchiveManifest {
  journeyId: string;
  revision: string;
  eventCount: number;
  headEventId: string | null;
  authoritySha256: string;
}

function isCanonicalTimestamp(value: unknown): value is string {
  if (typeof value !== "string") return false;
  const milliseconds = Date.parse(value);
  return Number.isFinite(milliseconds) && new Date(milliseconds).toISOString() === value;
}

function invalid(code: JourneyArchiveErrorCode, message: string): JourneyArchiveInspection {
  return { status: "invalid", code, message };
}

function canonicalJourneyFromAuthority(authority: unknown): Journey | null {
  if (!authority || typeof authority !== "object") return null;
  const events = (authority as { events?: unknown }).events;
  if (!Array.isArray(events)) return null;
  const restored = hydrateJourney(authority);
  if (!restored || restored.version !== (authority as { version?: unknown }).version ||
      (restored.version !== 3 && restored.version !== 4 && restored.version !== 5) || restored.events.length !== events.length) return null;
  return restored;
}

function manifestFor(journey: Journey, authoritySha256: string): ArchiveManifest {
  return {
    journeyId: journey.id,
    revision: revisionForJourney(journey),
    eventCount: journey.events.length,
    headEventId: journey.events.at(-1)?.eventId ?? null,
    authoritySha256,
  };
}

export function serializeJourneyArchive(
  journey: Journey,
  exportedAt = new Date().toISOString(),
): string {
  if (!isCanonicalTimestamp(exportedAt)) {
    throw new Error("A Journey archive requires a canonical export timestamp.");
  }
  if (journey.events.length > MAX_JOURNEY_ARCHIVE_EVENTS) {
    throw new Error("This Journey has more events than one local archive can safely replay.");
  }
  const authorityText = serializeJourney(journey);
  if (new TextEncoder().encode(authorityText).byteLength > MAX_JOURNEY_ARCHIVE_BYTES) {
    throw new Error("This Journey is larger than one local archive can carry.");
  }
  const authority = JSON.parse(authorityText) as unknown;
  const canonical = canonicalJourneyFromAuthority(authority);
  if (!canonical) throw new Error("Only a complete valid v3, v4 or v5 Journey can be archived.");
  const authoritySha256 = sha256String(serializeJourney(canonical));
  const archive = `${JSON.stringify(
    {
      format: JOURNEY_ARCHIVE_FORMAT,
      archiveVersion: JOURNEY_ARCHIVE_VERSION,
      exportedAt,
      authority,
      manifest: manifestFor(canonical, authoritySha256),
    },
    null,
    2,
  )}\n`;
  if (new TextEncoder().encode(archive).byteLength > MAX_JOURNEY_ARCHIVE_BYTES) {
    throw new Error("This Journey is larger than one local archive can carry.");
  }
  return archive;
}

export function inspectJourneyArchive(source: string): JourneyArchiveInspection {
  if (new TextEncoder().encode(source).byteLength > MAX_JOURNEY_ARCHIVE_BYTES) {
    return invalid("archive-too-large", "This Journey file is larger than the local import limit.");
  }

  let parsed: unknown;
  try {
    parsed = parseJsonWithoutDuplicateKeys(source, "ARCHi Journey archive");
  } catch {
    return invalid("invalid-json", "This file is not unambiguous valid JSON.");
  }
  if (!parsed || typeof parsed !== "object") {
    return invalid("invalid-envelope", "This file is not an ARCHi Journey archive.");
  }

  const envelope = parsed as {
    format?: unknown;
    archiveVersion?: unknown;
    exportedAt?: unknown;
    authority?: unknown;
    manifest?: unknown;
  };
  if (envelope.format !== JOURNEY_ARCHIVE_FORMAT) {
    return invalid("invalid-envelope", "This file does not identify itself as an ARCHi Journey archive.");
  }
  if (envelope.archiveVersion !== JOURNEY_ARCHIVE_VERSION) {
    return invalid("unsupported-archive-version", "This Journey archive version is not supported by this build.");
  }
  if (!isCanonicalTimestamp(envelope.exportedAt)) {
    return invalid("invalid-envelope", "This Journey archive has an invalid export timestamp.");
  }
  if (!envelope.authority || typeof envelope.authority !== "object") {
    return invalid("invalid-authority", "This archive does not contain Journey authority.");
  }

  const authority = envelope.authority as { version?: unknown; events?: unknown };
  if (authority.version !== 3 && authority.version !== 4 && authority.version !== 5) {
    return invalid("unsupported-journey-version", "Only complete ARCHi Journey v3, v4 or v5 archives can be restored.");
  }
  if (!Array.isArray(authority.events)) {
    return invalid("invalid-authority", "This archive does not contain a Journey event chain.");
  }
  if (authority.events.length > MAX_JOURNEY_ARCHIVE_EVENTS) {
    return invalid(
      "archive-too-many-events",
      "This Journey contains more events than this build can safely replay from one file.",
    );
  }
  for (const event of authority.events) {
    if (event && typeof event === "object" && "schema" in event &&
        (event as { schema?: unknown }).schema !== 2 &&
        !((authority.version === 4 || authority.version === 5) && (event as { schema?: unknown }).schema === 3) &&
        !(authority.version === 5 && (event as { schema?: unknown }).schema === 4)) {
      return invalid("unsupported-event-schema", "This archive contains an unsupported Journey event schema.");
    }
  }

  const journey = hydrateJourney(authority);
  if (!journey) {
    return invalid("invalid-authority", "The Journey origin, provenance, or complete event authority is invalid.");
  }
  if (journey.events.length !== authority.events.length) {
    return invalid("incomplete-event-chain", "The Journey event chain is incomplete or damaged; no replacement was prepared.");
  }

  if (!envelope.manifest || typeof envelope.manifest !== "object") {
    return invalid("invalid-envelope", "This Journey archive does not contain an integrity manifest.");
  }
  const suppliedManifest = envelope.manifest as Partial<ArchiveManifest>;
  const authoritySha256 = sha256String(serializeJourney(journey));
  const expectedManifest = manifestFor(journey, authoritySha256);
  if (
    suppliedManifest.journeyId !== expectedManifest.journeyId ||
    suppliedManifest.revision !== expectedManifest.revision ||
    suppliedManifest.eventCount !== expectedManifest.eventCount ||
    suppliedManifest.headEventId !== expectedManifest.headEventId ||
    suppliedManifest.authoritySha256 !== expectedManifest.authoritySha256
  ) {
    return invalid("manifest-mismatch", "The Journey archive manifest does not match its event authority.");
  }

  return {
    status: "valid",
    preview: {
      exportedAt: envelope.exportedAt,
      journey,
      ...expectedManifest,
    },
  };
}

function sameOrigin(left: Journey, right: Journey): boolean {
  return JSON.stringify([left.seed, left.createdAt, left.careStartedAt, left.provenance]) ===
    JSON.stringify([right.seed, right.createdAt, right.careStartedAt, right.provenance]);
}

function isEventPrefix(prefix: Journey, complete: Journey): boolean {
  return prefix.events.every((event, index) => complete.events[index]?.eventId === event.eventId);
}

export function compareJourneyLineage(current: Journey, candidate: Journey): JourneyRelation {
  if (revisionForJourney(current) === revisionForJourney(candidate)) return "same";
  if (!sameOrigin(current, candidate)) return "different-origin";
  if (current.events.length < candidate.events.length && isEventPrefix(current, candidate)) return "advance";
  if (candidate.events.length < current.events.length && isEventPrefix(candidate, current)) return "rewind";
  return "divergent";
}
