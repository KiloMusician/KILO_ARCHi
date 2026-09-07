import { describe, expect, it } from "vitest";
import {
  MAX_JOURNEY_ARCHIVE_BYTES,
  MAX_JOURNEY_ARCHIVE_EVENTS,
  compareJourneyLineage,
  inspectJourneyArchive,
  serializeJourneyArchive,
} from "./journey-portability";
import {
  advanceRelayAttempt,
  collectEcho,
  commitCareAction,
  commitRelayCompletion,
  commitSession,
  createCareIntent,
  createJourney,
  createPlaySession,
  createRelayAttempt,
  deriveActivityMilestones,
  revisionForJourney,
  serializeJourney,
  sha256String,
  type Journey,
  type RelayAction,
} from "./model";

const originTime = "2026-08-30T12:00:00.000Z";
const exportTime = "2026-08-30T12:10:00.000Z";

function withCare(journey: Journey, action: "greet" | "tend", at: string): Journey {
  return commitCareAction(journey, createCareIntent(journey, action), at);
}

function withPlay(journey: Journey, at: string): Journey {
  let session = createPlaySession(journey);
  for (const echo of session.echoes.slice(0, 3)) session = collectEcho(session, echo.id);
  return commitSession(journey, session, session.proposals[0], at);
}

function mixedJourney(): Journey {
  let journey = createJourney("portable-opal", originTime);
  journey = withCare(journey, "greet", "2026-08-30T12:01:00.000Z");
  journey = withPlay(journey, "2026-08-30T12:02:00.000Z");
  return journey;
}

function withRelay(journey: Journey): Journey {
  const actions: RelayAction[] = [
    { type: "START" }, { type: "REDIRECT", node: 2 }, { type: "REDIRECT", node: 1 }, { type: "REDIRECT", node: 3 },
    { type: "INSPECT", id: "A" }, { type: "INSPECT", id: "B" }, { type: "INSPECT", id: "C" }, { type: "RESOLVE", id: "B" },
  ];
  const attempt = actions.reduce(advanceRelayAttempt, createRelayAttempt(journey, "portable-relay-session"));
  return commitRelayCompletion(journey, attempt, attempt.sessionId, "2026-08-30T12:03:00.000Z");
}

function parsedArchive(journey = mixedJourney()): Record<string, any> {
  return JSON.parse(serializeJourneyArchive(journey, exportTime)) as Record<string, any>;
}

describe("ARCHi Journey portability", () => {
  it("round-trips a complete mixed care and play Journey", () => {
    const journey = mixedJourney();
    const inspection = inspectJourneyArchive(serializeJourneyArchive(journey, exportTime));
    expect(inspection.status).toBe("valid");
    if (inspection.status !== "valid") return;
    expect(inspection.preview.journey).toEqual(journey);
    expect(inspection.preview.revision).toBe(revisionForJourney(journey));
    expect(inspection.preview.eventCount).toBe(2);
  });

  it("creates deterministic archive bytes for a fixed export time", () => {
    const journey = mixedJourney();
    expect(serializeJourneyArchive(journey, exportTime)).toBe(serializeJourneyArchive(journey, exportTime));
  });

  it("archives only origin, provenance, and event authority", () => {
    const archive = parsedArchive();
    expect(Object.keys(archive.authority)).toEqual([
      "version",
      "seed",
      "createdAt",
      "careStartedAt",
      "provenance",
      "events",
    ]);
    expect(archive.authority).not.toHaveProperty("bond");
    expect(archive.authority).not.toHaveProperty("care");
    expect(archive.authority).not.toHaveProperty("affinities");
    expect(archive.authority).not.toHaveProperty("core");
  });

  it("rejects invalid, duplicate-key, trailing, and oversized JSON", () => {
    expect(inspectJourneyArchive("not json")).toMatchObject({ status: "invalid", code: "invalid-json" });
    expect(inspectJourneyArchive('{"format":"archi-journey","format":"archi-journey"}')).toMatchObject({
      status: "invalid",
      code: "invalid-json",
    });
    expect(inspectJourneyArchive(`${serializeJourneyArchive(mixedJourney(), exportTime)} true`)).toMatchObject({
      status: "invalid",
      code: "invalid-json",
    });
    expect(inspectJourneyArchive(" ".repeat(MAX_JOURNEY_ARCHIVE_BYTES + 1))).toMatchObject({
      status: "invalid",
      code: "archive-too-large",
    });
  });

  it("never exports an archive that the same build refuses for size or replay work", () => {
    const oversized = createJourney("s".repeat(MAX_JOURNEY_ARCHIVE_BYTES), originTime);
    expect(() => serializeJourneyArchive(oversized, exportTime)).toThrow(/larger than one local archive/i);

    const sampleEvent = mixedJourney().events[0];
    const tooManyEvents = {
      ...mixedJourney(),
      events: Array.from({ length: MAX_JOURNEY_ARCHIVE_EVENTS + 1 }, () => sampleEvent),
    } as Journey;
    expect(() => serializeJourneyArchive(tooManyEvents, exportTime)).toThrow(/more events/i);

    const archive = parsedArchive();
    archive.authority.events = Array.from({ length: MAX_JOURNEY_ARCHIVE_EVENTS + 1 }, () => null);
    expect(inspectJourneyArchive(JSON.stringify(archive))).toMatchObject({
      status: "invalid",
      code: "archive-too-many-events",
    });
  });

  it("rejects unsupported archive, Journey, and event versions without reinterpretation", () => {
    const archiveVersion = parsedArchive();
    archiveVersion.archiveVersion = 2;
    expect(inspectJourneyArchive(JSON.stringify(archiveVersion))).toMatchObject({
      status: "invalid",
      code: "unsupported-archive-version",
    });

    const journeyVersion = parsedArchive();
    journeyVersion.authority.version = 99;
    expect(inspectJourneyArchive(JSON.stringify(journeyVersion))).toMatchObject({
      status: "invalid",
      code: "unsupported-journey-version",
    });

    const eventVersion = parsedArchive();
    eventVersion.authority.events[0].schema = 1;
    expect(inspectJourneyArchive(JSON.stringify(eventVersion))).toMatchObject({
      status: "invalid",
      code: "unsupported-event-schema",
    });
  });

  it("rejects a damaged or truncated event chain instead of accepting its prefix", () => {
    const damaged = parsedArchive();
    damaged.authority.events[1].eventId = "forged";
    expect(inspectJourneyArchive(JSON.stringify(damaged))).toMatchObject({
      status: "invalid",
      code: "incomplete-event-chain",
    });

    const truncated = parsedArchive();
    truncated.authority.events.pop();
    expect(inspectJourneyArchive(JSON.stringify(truncated))).toMatchObject({
      status: "invalid",
      code: "manifest-mismatch",
    });
  });

  it("rejects a manifest that does not bind the supplied authority", () => {
    const archive = parsedArchive();
    archive.manifest.authoritySha256 = "0".repeat(64);
    expect(inspectJourneyArchive(JSON.stringify(archive))).toMatchObject({
      status: "invalid",
      code: "manifest-mismatch",
    });
  });

  it("imports an empty but complete Journey", () => {
    const journey = createJourney("empty-portable", originTime);
    const inspection = inspectJourneyArchive(serializeJourneyArchive(journey, exportTime));
    expect(inspection.status).toBe("valid");
    if (inspection.status !== "valid") return;
    expect(inspection.preview.eventCount).toBe(0);
    expect(inspection.preview.headEventId).toBeNull();
  });

  it("classifies same, advancing, rewinding, divergent, and unrelated lineages", () => {
    const origin = createJourney("lineage-portable", originTime);
    const greet = withCare(origin, "greet", "2026-08-30T12:01:00.000Z");
    const greetThenPlay = withPlay(greet, "2026-08-30T12:02:00.000Z");
    const tend = withCare(origin, "tend", "2026-08-30T12:01:00.000Z");
    const unrelated = createJourney("another-origin", originTime);

    expect(compareJourneyLineage(greet, greet)).toBe("same");
    expect(compareJourneyLineage(greet, greetThenPlay)).toBe("advance");
    expect(compareJourneyLineage(greetThenPlay, greet)).toBe("rewind");
    expect(compareJourneyLineage(greet, tend)).toBe("divergent");
    expect(compareJourneyLineage(greet, unrelated)).toBe("different-origin");
  });

  it("keeps original v3 manifest verification and authority bytes without upgrading on import", () => {
    const old = mixedJourney();
    const serialized = serializeJourneyArchive(old, exportTime);
    const envelope = JSON.parse(serialized);
    const originalHash = sha256String(serializeJourney(old));
    expect(envelope.archiveVersion).toBe(1);
    expect(envelope.authority.version).toBe(3);
    expect(envelope.manifest.authoritySha256).toBe(originalHash);
    const inspected = inspectJourneyArchive(serialized);
    expect(inspected.status).toBe("valid");
    if (inspected.status !== "valid") return;
    expect(inspected.preview.journey.version).toBe(3);
    expect(inspected.preview.authoritySha256).toBe(originalHash);
    expect(serializeJourney(inspected.preview.journey)).toBe(serializeJourney(old));
    expect(serializeJourneyArchive(inspected.preview.journey, exportTime)).toBe(serialized);
    const changedVersion = { ...envelope, authority: { ...envelope.authority, version: 4 } };
    expect(inspectJourneyArchive(JSON.stringify(changedVersion)).status).toBe("invalid");
  });

  it("round-trips v4 through the same archive envelope with its complete activity receipt", () => {
    const journey = withRelay(mixedJourney());
    const serialized = serializeJourneyArchive(journey, exportTime);
    const envelope = JSON.parse(serialized);
    expect(envelope.archiveVersion).toBe(1);
    expect(envelope.authority.version).toBe(4);
    expect(envelope.authority).not.toHaveProperty("milestones");
    const inspected = inspectJourneyArchive(serialized);
    expect(inspected.status).toBe("valid");
    if (inspected.status !== "valid") return;
    expect(inspected.preview.journey).toEqual(journey);
    expect(inspected.preview.eventCount).toBe(3);
    expect(deriveActivityMilestones(inspected.preview.journey)).toEqual(deriveActivityMilestones(journey));
    expect(serializeJourneyArchive(inspected.preview.journey, exportTime)).toBe(serialized);
  });

  it("retains lineage across v3→v4 and later care without minting another origin", () => {
    const original = mixedJourney();
    const relay = withRelay(original);
    const later = withCare(relay, "greet", "2026-08-30T12:04:00.000Z");
    expect(compareJourneyLineage(original, relay)).toBe("advance");
    expect(compareJourneyLineage(relay, original)).toBe("rewind");
    expect(compareJourneyLineage(relay, later)).toBe("advance");
    const otherBranch = withCare(original, "tend", "2026-08-30T12:04:00.000Z");
    expect(compareJourneyLineage(relay, otherBranch)).toBe("divergent");
    const inspected = inspectJourneyArchive(serializeJourneyArchive(later, exportTime));
    expect(inspected.status).toBe("valid");
    if (inspected.status === "valid") expect(compareJourneyLineage(original, inspected.preview.journey)).toBe("advance");
  });

  it("rejects v4 receipts inside a v3 envelope authority and unsupported v4 event schemas", () => {
    const archived = parsedArchive(withRelay(mixedJourney()));
    archived.authority.version = 3;
    expect(inspectJourneyArchive(JSON.stringify(archived))).toMatchObject({ status: "invalid", code: "unsupported-event-schema" });
    archived.authority.version = 4;
    archived.authority.events[2].schema = 99;
    expect(inspectJourneyArchive(JSON.stringify(archived))).toMatchObject({ status: "invalid", code: "unsupported-event-schema" });
  });

  it("never prepares a damaged or truncated v4 chain, including a valid prefix before the damage", () => {
    const journey = withCare(withRelay(mixedJourney()), "greet", "2026-08-30T12:04:00.000Z");
    for (const index of [0, 1, 2, 3]) {
      const damaged = parsedArchive(journey);
      damaged.authority.events[index].eventId = "damaged";
      expect(inspectJourneyArchive(JSON.stringify(damaged)).status).toBe("invalid");
      expect(() => serializeJourneyArchive({ ...journey, events: damaged.authority.events }, exportTime)).toThrow(/complete valid/i);
    }
    const truncated = parsedArchive(journey);
    truncated.authority.events.pop();
    expect(inspectJourneyArchive(JSON.stringify(truncated))).toMatchObject({ status: "invalid", code: "manifest-mismatch" });
    const unknownTail = parsedArchive(journey);
    unknownTail.authority.events.push({ schema: 3, kind: "unknown" });
    expect(inspectJourneyArchive(JSON.stringify(unknownTail)).status).toBe("invalid");
  });

  it("rejects altered receipts and duplicate keys inside v4 accepted steps", () => {
    const serialized = serializeJourneyArchive(withRelay(mixedJourney()), exportTime);
    const altered = JSON.parse(serialized);
    altered.authority.events[2].actions[7].id = "A";
    expect(inspectJourneyArchive(JSON.stringify(altered)).status).toBe("invalid");
    const duplicate = serialized.replace('"type": "START"', '"type": "START", "type": "START"');
    expect(inspectJourneyArchive(duplicate)).toMatchObject({ status: "invalid", code: "invalid-json" });
  });
});
