// Adapted from SigGraph Hackathon; provenance and deltas are recorded in
// docs/siggraph-local-companion-integration.md. No renderer owner is imported.
export type BrokenRelayCue = 'REST' | 'FOCUS'

export type BrokenRelayPhase = 'READY' | 'INTERFERENCE' | 'PUZZLE' | 'RESTORED'
export type BrokenRelayNode = 1 | 2 | 3
export type BrokenRelayTransmissionId = 'A' | 'B' | 'C'
export type BrokenRelayAdaptation = 'BASE' | 'FOCUS_PREVIEW'

export interface BrokenRelayState {
  readonly phase: BrokenRelayPhase
  readonly protectedSteps: number
  readonly readTransmissionIds: readonly BrokenRelayTransmissionId[]
  readonly selectedTransmissionId: BrokenRelayTransmissionId | null
  readonly feedback: string
  readonly adaptation: BrokenRelayAdaptation
}

export type BrokenRelayEvent =
  | { type: 'START' }
  | { type: 'REDIRECT'; node: BrokenRelayNode }
  | { type: 'INSPECT'; id: BrokenRelayTransmissionId }
  | { type: 'RESOLVE'; id: BrokenRelayTransmissionId }
  | { type: 'TRY_FOCUS' }
  | { type: 'RESTORE_PROTO' }
  | { type: 'RESET' }

export const BROKEN_RELAY_ROUTE: readonly BrokenRelayNode[] = Object.freeze([2, 1, 3])

export const BROKEN_RELAY_FIELD_LOG =
  '18:40 — The west bridge is closed until inspection. The north path is open. No later inspection or reopening has been recorded.'

export const BROKEN_RELAY_TRANSMISSIONS = Object.freeze([
  Object.freeze({
    id: 'A' as const,
    title: 'North route',
    text: '18:42 — Use the north path. It remains open after 18:40.',
  }),
  Object.freeze({
    id: 'B' as const,
    title: 'West bridge',
    text: '18:44 — The west bridge is clear. Send the convoy west now.',
  }),
  Object.freeze({
    id: 'C' as const,
    title: 'West beacon',
    text: '18:45 — Keep the west beacon offline until the bridge inspection is recorded.',
  }),
])

export function createBrokenRelayState(): BrokenRelayState {
  return {
    phase: 'READY',
    protectedSteps: 0,
    readTransmissionIds: [],
    selectedTransmissionId: null,
    feedback: 'Protect the relay Core, then trace the damaged message channel.',
    adaptation: 'BASE',
  }
}

/** A local game rehearsal only: these transitions have no external effects. */
export function transitionBrokenRelay(
  state: BrokenRelayState,
  event: BrokenRelayEvent,
): BrokenRelayState {
  if (!event || typeof event !== 'object' || Object.getPrototypeOf(event) !== Object.prototype) {
    throw new Error('Unknown Broken Relay action.')
  }
  const descriptors = Object.getOwnPropertyDescriptors(event)
  if (Object.values(descriptors).some(descriptor => !('value' in descriptor))) {
    throw new Error('Broken Relay actions must contain plain data.')
  }
  const keys = event.type === 'REDIRECT' ? ['type', 'node']
    : event.type === 'INSPECT' || event.type === 'RESOLVE' ? ['type', 'id'] : ['type']
  if (Reflect.ownKeys(event).length !== keys.length || keys.some(key => !Object.hasOwn(event, key))
    || !['START', 'REDIRECT', 'INSPECT', 'RESOLVE', 'TRY_FOCUS', 'RESTORE_PROTO', 'RESET'].includes(event.type)
    || (event.type === 'REDIRECT' && ![1, 2, 3].includes(event.node))
    || ((event.type === 'INSPECT' || event.type === 'RESOLVE') && !['A', 'B', 'C'].includes(event.id))) {
    throw new Error('Unknown Broken Relay action.')
  }
  switch (event.type) {
    case 'RESET':
      return createBrokenRelayState()
    case 'START':
      return state.phase === 'READY'
        ? {
            ...state,
            phase: 'INTERFERENCE',
            feedback: 'Redirect the interference through nodes 2 → 1 → 3 to protect the Core.',
          }
        : state
    case 'REDIRECT': {
      if (state.phase !== 'INTERFERENCE') return state
      const nextNode = BROKEN_RELAY_ROUTE[state.protectedSteps]
      if (event.node !== nextNode) {
        return {
          ...state,
          feedback: `That route is unstable. Progress is safe; redirect through node ${nextNode} next.`,
        }
      }
      const protectedSteps = state.protectedSteps + 1
      if (protectedSteps === BROKEN_RELAY_ROUTE.length) {
        return {
          ...state,
          phase: 'PUZZLE',
          protectedSteps,
          feedback: 'Core protected. A memory scar has scrambled the message channel. Read all three transmissions and compare them with the field log.',
        }
      }
      return {
        ...state,
        protectedSteps,
        feedback: `Node ${event.node} secured. Redirect through node ${BROKEN_RELAY_ROUTE[protectedSteps]} next.`,
      }
    }
    case 'INSPECT':
      if (state.phase !== 'PUZZLE') return state
      return {
        ...state,
        selectedTransmissionId: event.id,
        readTransmissionIds: state.readTransmissionIds.includes(event.id)
          ? state.readTransmissionIds
          : [...state.readTransmissionIds, event.id],
        feedback: `Transmission ${event.id} inspected. Compare its claim with the field log before choosing the false message.`,
      }
    case 'RESOLVE': {
      if (state.phase !== 'PUZZLE') return state
      const selection = { ...state, selectedTransmissionId: event.id }
      if (!BROKEN_RELAY_TRANSMISSIONS.every(({ id }) => state.readTransmissionIds.includes(id))) {
        return {
          ...selection,
          feedback: 'Inspect all three transmissions before choosing. Your relay progress is preserved.',
        }
      }
      if (event.id !== 'B') {
        return {
          ...selection,
          feedback: 'That message agrees with the field log. Look for a bridge reopening without a recorded inspection; your progress is preserved.',
        }
      }
      return {
        ...selection,
        phase: 'RESTORED',
        feedback: 'Relay restored. Transmission B contradicts the recorded west-bridge closure. You can now try a reversible Focus preview for Proto.',
      }
    }
    case 'TRY_FOCUS':
      return state.phase === 'RESTORED'
        ? {
            ...state,
            adaptation: 'FOCUS_PREVIEW',
            feedback: 'Focus preview active for this rehearsal. Restore Proto at any time; nothing is saved as an evolution.',
          }
        : state
    case 'RESTORE_PROTO':
      return state.phase === 'RESTORED'
        ? {
            ...state,
            adaptation: 'BASE',
            feedback: 'Proto restored to its base presentation. The repaired relay remains available until Reset.',
          }
        : state
  }
}

export function relayCue(state: BrokenRelayState): BrokenRelayCue {
  if (state.phase === 'READY') return 'REST'
  if (state.phase === 'RESTORED' && state.adaptation === 'BASE') return 'REST'
  return 'FOCUS'
}
