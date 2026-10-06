import type { Register } from 'claude-code'

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

  // The user's own prompts are never redrawn on the desktop: a plugin-drawn row loses the
  // native date/copy/rewind actions. Their order comes from the input-box helper, whose
  // U+202B mark travels with the prompt, and the native bubble honours it. The desktop
  // also strips the controls rtlPlain adds, so it is left alone there entirely.
  on('ui.render', { component: 'UserMessage' }, ($, e, next) => {
    if (e.surface === 'terminal' || e.surface === 'desktop' || !isEnabled) return next(e)
    const text = rtlPlain(e.props.text)

    return text === e.props.text ? next(e) : next({ ...e, props: { ...e.props, text } })
  })
}
