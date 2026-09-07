import { describe, expect, it } from 'vitest'
import {
  BROKEN_RELAY_FIELD_LOG,
  BROKEN_RELAY_ROUTE,
  BROKEN_RELAY_TRANSMISSIONS,
  createBrokenRelayState,
  relayCue,
  transitionBrokenRelay,
  type BrokenRelayState,
  type BrokenRelayEvent,
} from './broken-relay'

describe('runtime Broken Relay action boundary', () => {
  it.each([
    { type: 'REDIRECT', node: 4 }, { type: 'INSPECT', id: 'D' },
    { type: 'RESOLVE', id: 'D' }, { type: 'START', achievement: 'RELAY_RESTORED' },
    { type: 'COMPLETE' }, { type: 'REDIRECT' },
  ])('rejects malformed or extra action fields: %j', event => {
    expect(() => transitionBrokenRelay(createBrokenRelayState(), event as BrokenRelayEvent)).toThrow()
  })

  it('does not invoke an action accessor', () => {
    let reads = 0
    const event = { get type() { reads += 1; return 'START' } }
    expect(() => transitionBrokenRelay(createBrokenRelayState(), event as BrokenRelayEvent)).toThrow('plain data')
    expect(reads).toBe(0)
  })
})

function reachPuzzle(): BrokenRelayState {
  let state = transitionBrokenRelay(createBrokenRelayState(), { type: 'START' })
  for (const node of BROKEN_RELAY_ROUTE) {
    state = transitionBrokenRelay(state, { type: 'REDIRECT', node })
  }
  return state
}

function inspectMessages(state: BrokenRelayState): BrokenRelayState {
  for (const { id } of BROKEN_RELAY_TRANSMISSIONS) {
    state = transitionBrokenRelay(state, { type: 'INSPECT', id })
  }
  return state
}

function restoreRelay(): BrokenRelayState {
  return transitionBrokenRelay(inspectMessages(reachPuzzle()), { type: 'RESOLVE', id: 'B' })
}

describe('local Broken Relay rehearsal', () => {
  it('turns a protected Core into a clue puzzle and restores the relay from the conflicting message', () => {
    const initial = createBrokenRelayState()
    expect(initial).toMatchObject({ phase: 'READY', protectedSteps: 0, adaptation: 'BASE' })
    expect(relayCue(initial)).toBe('REST')

    const puzzle = reachPuzzle()
    expect(puzzle).toMatchObject({ phase: 'PUZZLE', protectedSteps: 3, readTransmissionIds: [] })
    expect(puzzle.feedback).toContain('memory scar')
    expect(relayCue(puzzle)).toBe('FOCUS')
    expect(BROKEN_RELAY_FIELD_LOG).toContain('18:40')
    expect(BROKEN_RELAY_FIELD_LOG).toContain('west bridge is closed')

    const restored = restoreRelay()
    expect(restored).toMatchObject({ phase: 'RESTORED', selectedTransmissionId: 'B', adaptation: 'BASE' })
    expect(restored.feedback).toContain('contradicts')
    expect(relayCue(restored)).toBe('REST')
  })

  it('keeps correct redirects when a player selects a wrong node and allows recovery', () => {
    let state = transitionBrokenRelay(createBrokenRelayState(), { type: 'START' })
    expect(relayCue(state)).toBe('FOCUS')
    state = transitionBrokenRelay(state, { type: 'REDIRECT', node: 2 })
    state = transitionBrokenRelay(state, { type: 'REDIRECT', node: 3 })
    expect(state).toMatchObject({ phase: 'INTERFERENCE', protectedSteps: 1 })
    expect(state.feedback).toContain('node 1 next')
    state = transitionBrokenRelay(state, { type: 'REDIRECT', node: 1 })
    state = transitionBrokenRelay(state, { type: 'REDIRECT', node: 3 })
    expect(state.phase).toBe('PUZZLE')
  })

  it('requires every transmission to be inspected, even when the player guesses the correct answer', () => {
    let state = reachPuzzle()
    state = transitionBrokenRelay(state, { type: 'INSPECT', id: 'B' })
    expect(state.selectedTransmissionId).toBe('B')
    state = transitionBrokenRelay(state, { type: 'INSPECT', id: 'B' })
    state = transitionBrokenRelay(state, { type: 'RESOLVE', id: 'B' })
    expect(state).toMatchObject({ phase: 'PUZZLE', protectedSteps: 3, readTransmissionIds: ['B'] })
    expect(state.feedback).toContain('Inspect all three')
    state = transitionBrokenRelay(state, { type: 'INSPECT', id: 'A' })
    state = transitionBrokenRelay(state, { type: 'INSPECT', id: 'C' })
    expect(transitionBrokenRelay(state, { type: 'RESOLVE', id: 'B' }).phase).toBe('RESTORED')
  })

  it.each(['A', 'C'] as const)('keeps the read clues and relay progress after incorrect answer %s', (id) => {
    const read = inspectMessages(reachPuzzle())
    const incorrect = transitionBrokenRelay(read, { type: 'RESOLVE', id })
    expect(incorrect).toMatchObject({
      phase: 'PUZZLE',
      protectedSteps: 3,
      selectedTransmissionId: id,
      readTransmissionIds: ['A', 'B', 'C'],
    })
    expect(incorrect.feedback).toContain('agrees with the field log')
    expect(transitionBrokenRelay(incorrect, { type: 'RESOLVE', id: 'B' }).phase).toBe('RESTORED')
  })

  it('allows a reversible Focus preview only after solving and preserves the repaired relay', () => {
    for (const state of [createBrokenRelayState(), reachPuzzle()]) {
      expect(transitionBrokenRelay(state, { type: 'TRY_FOCUS' })).toBe(state)
      expect(transitionBrokenRelay(state, { type: 'RESTORE_PROTO' })).toBe(state)
    }
    const restored = restoreRelay()
    const preview = transitionBrokenRelay(restored, { type: 'TRY_FOCUS' })
    expect(preview.adaptation).toBe('FOCUS_PREVIEW')
    expect(relayCue(preview)).toBe('FOCUS')
    expect(preview.feedback).toContain('nothing is saved')
    const base = transitionBrokenRelay(preview, { type: 'RESTORE_PROTO' })
    expect(base).toMatchObject({ phase: 'RESTORED', adaptation: 'BASE', selectedTransmissionId: 'B' })
    expect(relayCue(base)).toBe('REST')
  })

  it('cannot skip encounter phases with out-of-order actions or restart completed progress with START', () => {
    const ready = createBrokenRelayState()
    expect(transitionBrokenRelay(ready, { type: 'REDIRECT', node: 2 })).toBe(ready)
    expect(transitionBrokenRelay(ready, { type: 'INSPECT', id: 'A' })).toBe(ready)
    expect(transitionBrokenRelay(ready, { type: 'RESOLVE', id: 'B' })).toBe(ready)
    const active = transitionBrokenRelay(ready, { type: 'START' })
    expect(transitionBrokenRelay(active, { type: 'RESOLVE', id: 'B' })).toBe(active)
    const restored = restoreRelay()
    expect(transitionBrokenRelay(restored, { type: 'START' })).toBe(restored)
    expect(transitionBrokenRelay(restored, { type: 'INSPECT', id: 'A' })).toBe(restored)
    expect(transitionBrokenRelay(restored, { type: 'RESOLVE', id: 'C' })).toBe(restored)
  })

  it('resets every phase and removes the session-only adaptation and clue selections', () => {
    for (const state of [
      createBrokenRelayState(),
      reachPuzzle(),
      transitionBrokenRelay(restoreRelay(), { type: 'TRY_FOCUS' }),
    ]) {
      const reset = transitionBrokenRelay(state, { type: 'RESET' })
      expect(reset).toEqual(createBrokenRelayState())
      expect(reset.readTransmissionIds).not.toBe(state.readTransmissionIds)
    }
  })

  it('does not mutate prior state or its clue list while progressing the rehearsal', () => {
    const puzzle = Object.freeze({
      ...reachPuzzle(),
      readTransmissionIds: Object.freeze(['A'] as const),
    })
    const before = structuredClone(puzzle)
    const inspected = transitionBrokenRelay(puzzle, { type: 'INSPECT', id: 'B' })
    const selected = transitionBrokenRelay(inspected, { type: 'RESOLVE', id: 'B' })
    expect(puzzle).toEqual(before)
    expect(puzzle.readTransmissionIds).toEqual(['A'])
    expect(inspected.readTransmissionIds).toEqual(['A', 'B'])
    expect(puzzle.selectedTransmissionId).toBeNull()
    expect(inspected.selectedTransmissionId).toBe('B')
    expect(selected.selectedTransmissionId).toBe('B')
    expect(Object.isFrozen(BROKEN_RELAY_ROUTE)).toBe(true)
    expect(BROKEN_RELAY_TRANSMISSIONS.every(Object.isFrozen)).toBe(true)
  })
})
