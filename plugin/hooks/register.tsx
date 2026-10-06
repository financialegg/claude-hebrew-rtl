import type { Register } from 'claude-code'

import { atomize, nativeReadsRight } from './atoms'
import { blockDir } from './rtl-core'
import { rtlMarkdown, rtlPlain } from './transform'

const STORE_KEY = 'isEnabled'

export const register: Register = on => {
  // ponytail: a module variable, not $.state, so the render hooks answer synchronously:
  // an awaited state read per message let the native (wrong) bubble show first.
  let isEnabled = true

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'rtl',
      description: 'Toggle RTL (Hebrew/Arabic) direction fixes for messages',
    })
    const stored = await $.store.get(STORE_KEY)
    if (typeof stored === 'boolean') isEnabled = stored

    return next(e)
  })

  on('command.run', { command: 'rtl' }, async $ => {
    isEnabled = !isEnabled
    await $.store.set(STORE_KEY, isEnabled)
    $.ui.invalidate('ui.render')

    return { text: isEnabled ? 'RTL fixes on.' : 'RTL fixes off.' }
  })

  // The terminal has no bidi layout to steer, and the controls would print
  // as stray glyphs in some terminals: only the remote surfaces are touched.
  on('ui.render', { component: 'AssistantMessage' }, ($, e, next) => {
    if (e.surface === 'terminal' || !isEnabled) return next(e)
    const text = rtlMarkdown(e.props.text)

    return text === e.props.text ? next(e) : next({ ...e, props: { ...e.props, text } })
  })

  // The desktop strips bidi controls from what a plugin draws, so Hebrew is laid out by
  // hand there: each line a row-reverse Box of single-direction pieces (atoms.ts).
  const lines = (Box: any, Text: any, text: string, isDim = false) =>
    text.split('\n').map(line => (
      <Box flexDirection="row-reverse" flexWrap="wrap">
        {line ? atomize(line).map(a => <Text dimColor={isDim}>{a.text}</Text>) : <Text>{' '}</Text>}
      </Box>
    ))

  on('ui.render', { component: 'UserMessage' }, ($, e, next) => {
    if (e.surface === 'terminal' || !isEnabled) return next(e)
    // A prompt the AutoHotkey input helper seeded with U+202B (RLE) carries its own
    // direction: the native bubble lays it out and keeps its date/copy/rewind row.
    if (/^\s*‫/.test(e.props.text)) return next(e)
    if (e.surface === 'desktop' && !e.props.task && !e.props.from && blockDir(e.props.text) === 'rtl' && !nativeReadsRight(e.props.text)) {
      const { Box, Text } = $.ui.resolve(e)

      // ponytail: the native bubble color sampled from the light theme (no theme key
      // reaches the desktop); a dark-theme user needs another color here.
      return (
        <Box flexDirection="column" alignItems="flex-end">
          <Box flexDirection="column" alignItems="flex-end" backgroundColor="#f0f0ef" paddingX={1} paddingY={1}>
            {lines(Box, Text, e.props.text)}
          </Box>
        </Box>
      )
    }
    // The desktop strips the controls rtlPlain adds (leaving a stray glyph): leave it be.
    if (e.surface === 'desktop') return next(e)
    const text = rtlPlain(e.props.text)

    return text === e.props.text ? next(e) : next({ ...e, props: { ...e.props, text } })
  })
}
