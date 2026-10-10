import type { EngineInterface, Register } from 'claude-code'

const MINUTE = 60_000

// A mod is a module that exports `register`. The engine calls it once per load
// and hands it `on`, which attaches hooks to engine events. Plain variables
// below last until the mod reloads.
export const register: Register = on => {
  // No getter reports the session's effort level, but each model request
  // carries it. Remember the main conversation's (a subagent's has an agentId).
  let effort: string | undefined

  // When the main conversation last sent a model request, and how long its
  // prompt cache lives. The cache stays warm for one TTL after each request.
  const cache: CacheState = { lastRequestAt: undefined, ttl: 60 * MINUTE, timers: [] }

  on('turn.step', async function* ($, e, next) {
    if (e.agentId !== undefined) {
      return yield* next(e)
    }
    if (e.effort !== undefined) {
      effort = String(e.effort)
    }
    cache.lastRequestAt = await $.clock.now()
    cache.ttl = await cacheTtl($)
    scheduleCacheWarning($, cache)
    return yield* next(e)
  })

  // Compaction and /clear start a new conversation prefix, so the old expiry no longer applies.
  on('session.compact', async ($, e, next) => {
    const result = await next(e)
    forgetCache($, cache)
    return result
  })
  on('session.end', async ($, e, next) => {
    if (e.reason === 'clear') {
      forgetCache($, cache)
    }
    return next(e)
  })

  // Redraw at the top of each minute so the clock and elapsed time stay current.
  on('session.start', async ($, e, next) => {
    const now = await $.clock.now()
    $.clock.after(MINUTE - (now % MINUTE), () => {
      $.ui.invalidate('ui.render')
      $.clock.every(MINUTE, () => $.ui.invalidate('ui.render'))
    })
    return next(e)
  })

  // The engine raises `ui.render` whenever it draws the band above the prompt.
  // Returning a tree draws ours; returning `next(e)` leaves the band as it was.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) {
      return next(e)
    }

    const [usage, model, cwd, root, repo, home, now] = await Promise.all([
      $.session.usage(),
      $.session.model(),
      $.session.cwd(),
      $.session.root(),
      $.session.repo(),
      $.env.get('HOME'),
      $.clock.now(),
    ])
    const { Box, Text } = $.ui.resolve(e)
    const tilde = (path: string) => (home && path.startsWith(home) ? '~' + path.slice(home.length) : path)

    // Line 1: model, effort, context remaining, cost, elapsed, cache, clock.
    const percentUsed = usage.context.percent
    const remaining = percentUsed === undefined ? undefined : Math.max(0, Math.min(100, 100 - percentUsed))
    const elapsedMinutes = Math.max(0, Math.floor((now - usage.startedAt) / MINUTE))
    const elapsed = elapsedMinutes >= 60 ? `${Math.floor(elapsedMinutes / 60)}h${String(elapsedMinutes % 60).padStart(2, '0')}m` : `${elapsedMinutes}m`

    let cacheText = null
    if (cache.lastRequestAt !== undefined) {
      const expiresAt = cache.lastRequestAt + cache.ttl
      if (now >= expiresAt) {
        cacheText = <Text dimColor>{'   '}cache cold since {clockTime(expiresAt)}</Text>
      } else if (now >= expiresAt - warningLead(cache.ttl)) {
        cacheText = <Text color="warning">{'   '}cache expires {clockTime(expiresAt)}</Text>
      } else {
        cacheText = <Text dimColor>{'   '}cache warm until {clockTime(expiresAt)}</Text>
      }
    }

    // Line 2: the repository as owner/name from its origin remote, else its folder name.
    const repoLabel = repo
      ? (repo.remote?.match(/[:/]([^/:]+\/[^/]+?)(?:\.git)?$/)?.[1] ?? repo.root.split('/').pop())
      : undefined

    return (
      <Box flexDirection="column">
        <Text>
          <Text color="suggestion" bold>{model}</Text>
          {effort ? <Text color="warning"> · {effort}</Text> : null}
          {remaining !== undefined ? (
            <Text color={contextColor(remaining)}>{'   '}{bar(remaining)} {remaining}% ctx</Text>
          ) : null}
          <Text dimColor>
            {'   '}
            {usage.cost ? `$${usage.cost.usd.toFixed(2)} · ` : ''}
            {elapsed}
          </Text>
          {cacheText}
          <Text dimColor>{'   '}🕐 {clockTime(now)}</Text>
        </Text>
        <Text>
          <Text color="ide">📁 {tilde(cwd)}</Text>
          {root !== cwd ? <Text dimColor>{'   '}proj: {tilde(root)}</Text> : null}
          {repoLabel ? <Text color="success">{'   '}repo: {repoLabel}</Text> : null}
        </Text>
      </Box>
    )
  })
}

type CacheState = {
  lastRequestAt: number | undefined
  ttl: number
  timers: { cancel: () => void }[]
}

function forgetCache($: EngineInterface, cache: CacheState) {
  cache.lastRequestAt = undefined
  cache.timers.forEach(t => t.cancel())
  cache.timers = []
  $.ui.invalidate('ui.render')
}

// Shortly before the cache lapses, raise one toast and redraw; redraw again when it lapses.
function scheduleCacheWarning($: EngineInterface, cache: CacheState) {
  cache.timers.forEach(t => t.cancel())
  const expiresAt = cache.lastRequestAt! + cache.ttl
  const warnIn = cache.ttl - warningLead(cache.ttl)
  cache.timers = [
    $.clock.after(warnIn, async () => {
      const { context } = await $.session.usage()
      const tokens = context.tokens === undefined ? '' : ` (${Math.round(context.tokens / 1000)}K tokens)`
      $.ui.toast(
        `Prompt cache expires at ${clockTime(expiresAt)}. After that, your next message re-sends the whole context${tokens} at the cache-write price. If you're stepping away, /compact now shrinks what gets re-sent.`,
        { timeoutMs: 30_000 },
      )
      $.ui.invalidate('ui.render')
    }),
    $.clock.after(cache.ttl, () => $.ui.invalidate('ui.render')),
  ]
}

// The main conversation's cache TTL, following Claude Code's documented rules:
// the promptCacheTtl setting when set; otherwise one hour on a subscription
// within plan usage (rate-limit windows are reported only on a subscription),
// and five minutes otherwise, including once usage credits kick in past a limit.
async function cacheTtl($: EngineInterface): Promise<number> {
  const [settings, usage] = await Promise.all([$.settings.read(), $.session.usage()])
  if (settings.promptCacheTtl === '5m') return 5 * MINUTE
  if (settings.promptCacheTtl === '1h') return 60 * MINUTE
  const onPlan = usage.rateLimits.length > 0 && usage.rateLimits.every(r => r.percentUsed < 100)
  return onPlan ? 60 * MINUTE : 5 * MINUTE
}

// How far ahead of expiry to warn: five minutes for a one-hour cache, one for a five-minute cache.
function warningLead(ttl: number): number {
  return ttl >= 60 * MINUTE ? 5 * MINUTE : MINUTE
}

function clockTime(ms: number): string {
  return new Date(ms).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })
}

// A 10-cell bar whose filled cells are the context still available.
function bar(remaining: number): string {
  const filled = Math.floor(remaining / 10)
  return '█'.repeat(filled) + '░'.repeat(10 - filled)
}

// Theme colors for the context left: plenty (70%+), getting low (40%+), low.
function contextColor(remaining: number): string {
  if (remaining >= 70) return 'success'
  if (remaining >= 40) return 'warning'
  return 'error'
}
