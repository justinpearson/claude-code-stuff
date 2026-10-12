import { describe, expect, mock, test } from 'claude-code/testing'

const BAND = {
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 160 },
} as const

const MINUTE = 60_000
const START = Date.UTC(2026, 9, 9, 18, 0) // the mocked clock's starting time

type On = Parameters<Parameters<typeof test>[1]>[1]
type Dollar = Parameters<Parameters<typeof test>[1]>[0]

// The same local-time formatting the mod uses, so expectations hold in any timezone.
const clockTime = (ms: number) => new Date(ms).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })
const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

// Stands in for the engine: answers each call the mod makes with fixed values.
function fakeSession(
  on: On,
  overrides: { noCost?: boolean; percent?: number | (() => number); noRepo?: boolean; rateLimits?: unknown[]; settings?: Record<string, unknown> } = {},
) {
  const percentOf = () => (typeof overrides.percent === 'function' ? overrides.percent() : overrides.percent)
  on('session.usage', () => ({
    value: {
      startedAt: START - 95 * MINUTE,
      context: percentOf() === undefined ? { window: 200000 } : { tokens: percentOf()! * 2000, window: 200000, percent: percentOf() },
      rateLimits: overrides.rateLimits ?? [{ kind: 'five_hour', percentUsed: 12 }],
      ...(overrides.noCost ? {} : { cost: { usd: 1.234 } }),
    },
  }))
  on('session.model', () => ({ value: 'Opus 5.5' }))
  on('session.cwd', () => ({ value: '/Users/me/agents/app' }))
  on('session.root', () => ({ value: '/Users/me/agents' }))
  on('session.repo', () => ({
    value: overrides.noRepo ? null : { root: '/Users/me/agents', remote: 'git@github.com:me/agents.git', internal: false, name: null },
  }))
  on('settings.read', () => ({ value: overrides.settings ?? {} }))
  on('env.get', () => ({ value: '/Users/me' }))
  on('turn.step', async function* (_$, e) {
    return { turnId: e.turnId, index: e.index, answer: 'ok', toolUses: [] } as never
  })
}

// Runs one main-conversation model request through the hooks, as the engine does.
async function modelRequest($: Dollar, effort = 'high') {
  const stream = $.turn.step({ turnId: 't1', index: 0, model: 'opus', effort, messageCount: 1 } as never)
  for await (const _ of stream as AsyncIterable<unknown>) {
    // drain the stream
  }
}

describe('session-info-in-footer', () => {
  test('draws two lines with every field on terminal and desktop', async ($, on) => {
    mock.clock(on, { now: START })
    fakeSession(on, { percent: 4 })
    await modelRequest($)

    for (const surface of ['terminal', 'desktop'] as const) {
      const ui = await $.ui.mount({ plugin: 'session-info-in-footer', surface, ...BAND })
      expect(await ui.find({ type: 'Text', text: /Opus 5\.5/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /· high/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /█{9}░ 96% ctx/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /\$1\.23 · 1h35m/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: new RegExp(escape(`🕐 ${clockTime(START)}`)) })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /📁 ~\/agents\/app/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /proj: ~\/agents/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /repo: me\/agents/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /subagent/ })).toBeUndefined()
      await ui.unmount()
    }
  })

  test('colors the context bar green from 70% left, orange from 40%, red below', async ($, on) => {
    mock.clock(on, { now: START })
    let current = 0
    fakeSession(on, { percent: () => current })
    for (const [percentUsed, color] of [[30, 'success'], [31, 'warning'], [60, 'warning'], [61, 'error']] as const) {
      current = percentUsed
      const ui = await $.ui.mount({ plugin: 'session-info-in-footer', surface: 'terminal', ...BAND })
      const line = await ui.find({ type: 'Text', text: /% ctx/ })
      const segment = (line?.children as { props: { color?: string }; children: unknown[] }[]).find(c =>
        c.children?.join('').includes(`${100 - percentUsed}% ctx`),
      )
      expect(segment?.props.color).toBe(color)
      await ui.unmount()
    }
  })

  test('tracks the prompt cache from the last request: warm, warning, cold', async ($, on) => {
    const clock = mock.clock(on, { now: START })
    fakeSession(on, { percent: 50 })
    const toasts: string[] = []
    on('ui.toast', (_$, e) => {
      toasts.push(e.text)
      return { value: undefined }
    })

    const expires = clockTime(START + 60 * MINUTE)
    await modelRequest($)
    let ui = await $.ui.mount({ plugin: 'session-info-in-footer', surface: 'desktop', ...BAND })
    expect(await ui.find({ type: 'Text', text: new RegExp(escape(`cache warm until ${expires}`)) })).toBeDefined()
    await ui.unmount()

    // Five minutes before a one-hour cache lapses: one toast, and the band says so.
    await clock.advance(55 * MINUTE)
    expect(toasts).toHaveLength(1)
    expect(toasts[0]).toMatch(/cache expires/)
    expect(toasts[0]).toMatch(/100K tokens/)
    ui = await $.ui.mount({ plugin: 'session-info-in-footer', surface: 'desktop', ...BAND })
    expect(await ui.find({ type: 'Text', text: new RegExp(escape(`cache expires ${expires}`)) })).toBeDefined()
    await ui.unmount()

    await clock.advance(5 * MINUTE)
    ui = await $.ui.mount({ plugin: 'session-info-in-footer', surface: 'desktop', ...BAND })
    expect(await ui.find({ type: 'Text', text: new RegExp(escape(`cache cold since ${expires}`)) })).toBeDefined()
    await ui.unmount()
    expect(toasts).toHaveLength(1)
  })

  test('uses a five-minute cache off a subscription, warning a minute ahead', async ($, on) => {
    const clock = mock.clock(on, { now: START })
    fakeSession(on, { percent: 50, rateLimits: [] })
    const toasts: string[] = []
    on('ui.toast', (_$, e) => {
      toasts.push(e.text)
      return { value: undefined }
    })

    await modelRequest($)
    const ui = await $.ui.mount({ plugin: 'session-info-in-footer', surface: 'desktop', ...BAND })
    expect(await ui.find({ type: 'Text', text: new RegExp(escape(`cache warm until ${clockTime(START + 5 * MINUTE)}`)) })).toBeDefined()
    await ui.unmount()
    await clock.advance(4 * MINUTE)
    expect(toasts).toHaveLength(1)
  })

  test('the promptCacheTtl setting overrides the guess', async ($, on) => {
    mock.clock(on, { now: START })
    fakeSession(on, { percent: 50, settings: { promptCacheTtl: '5m' } })

    await modelRequest($)
    const ui = await $.ui.mount({ plugin: 'session-info-in-footer', surface: 'desktop', ...BAND })
    expect(await ui.find({ type: 'Text', text: new RegExp(escape(`cache warm until ${clockTime(START + 5 * MINUTE)}`)) })).toBeDefined()
    await ui.unmount()
  })

  test('leaves out what is not known yet', async ($, on) => {
    mock.clock(on, { now: START })
    fakeSession(on, { noCost: true, noRepo: true })

    const ui = await $.ui.mount({ plugin: 'session-info-in-footer', surface: 'desktop', ...BAND })
    expect(await ui.find({ type: 'Text', text: /Opus 5\.5/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /\$/ })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /ctx/ })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /repo:/ })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /cache/ })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /· high/ })).toBeUndefined()
    await ui.unmount()
  })
})
