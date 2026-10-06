import { describe, expect, test } from 'claude-code/testing'
import { atomize, nativeReadsRight } from './atoms'

import { LRI, PDI, RLI, RLM, rtlMarkdown, rtlPlain } from './transform'

describe('rtlMarkdown', () => {
  test('leaves English and code-only text untouched', () => {
    const md = 'Hello world\n\n```js\nconst x = 1\n```'
    expect(rtlMarkdown(md)).toBe(md)
  })

  test('opens a Hebrew paragraph that starts with a filename with RLM', () => {
    expect(rtlMarkdown('index.js הוא הקובץ הראשי')).toBe(RLM + 'index.js הוא הקובץ הראשי')
  })

  test('isolates inline code and arithmetic in Hebrew text', () => {
    expect(rtlMarkdown('הריצו `npm test` ואז 2 + 3 = 5 בדיוק')).toBe(
      RLM + 'הריצו ' + LRI + '`npm test`' + PDI + ' ואז ' + LRI + '2 + 3 = 5' + PDI + ' בדיוק',
    )
  })

  test('never touches fenced code inside a Hebrew reply', () => {
    const out = rtlMarkdown('שלום\n```\nשלום = 1 + 2\n```')
    expect(out).toBe(RLM + 'שלום\n```\nשלום = 1 + 2\n```')
  })

  test('a Hebrew list whose first item is English still opens RTL', () => {
    const out = rtlMarkdown('- React\n- רכיב שני\n- רכיב שלישי')
    expect(out).toBe(
      ['- ' + RLM + LRI + 'React' + PDI, '- ' + RLM + 'רכיב שני', '- ' + RLM + 'רכיב שלישי'].join('\n'),
    )
  })

  test('a Hebrew table with an English first header flips and isolates cells', () => {
    const out = rtlMarkdown('| Name | תיאור | מחיר |\n|---|---|---|\n| x | ok | 5 |').split('\n')
    expect(out[0]).toBe('| ' + RLM + LRI + 'Name' + PDI + ' | תיאור | מחיר |')
    expect(out[1]).toBe('|---|---|---|')
    expect(out[2]).toBe('| ' + LRI + 'x' + PDI + ' | ' + LRI + 'ok' + PDI + ' | 5 |')
  })

  test('an English line inside a Hebrew paragraph keeps its own order', () => {
    expect(rtlMarkdown('שורה בעברית\nAn English line')).toBe(
      RLM + 'שורה בעברית\n' + LRI + 'An English line' + PDI,
    )
  })

  test('a Hebrew quote in an English paragraph is isolated RTL', () => {
    expect(rtlMarkdown('He said this in the meeting:\nשלום לכולם')).toBe('He said this in the meeting:\n' + RLI + 'שלום לכולם' + PDI)
  })

  test('keeps headings and blockquote markers in place', () => {
    expect(rtlMarkdown('## כותרת\n> ציטוט')).toBe('## ' + RLM + 'כותרת\n> ' + RLM + 'ציטוט')
  })

  test('nothing lands inside a link destination', () => {
    const out = rtlMarkdown('ראו [כאן](https://x.com/a-1+2=3)')
    expect(out).toBe(RLM + 'ראו [כאן](https://x.com/a-1+2=3)')
  })
})

describe('rtlPlain', () => {
  test('a Hebrew user prompt opens with RLM', () => {
    const out = rtlPlain('תקן את הבאג ב-app.ts')
    expect(out.startsWith(RLM + RLI)).toBe(true)
    expect(out.endsWith(PDI)).toBe(true)
  })
  test('more Hebrew words than English ones is RTL, even with fewer letters', () => {
    const s = 'Nvidia, מה ההבדל בין GPU ל-CPU?'
    const out = rtlPlain(s)
    expect(out.startsWith(RLM + RLI)).toBe(true)
    expect(out.endsWith(PDI)).toBe(true)
    expect(out.replace(/[‏⁦-⁩]/g, '')).toBe(s)
  })
  test('each RTL line of a multi-line prompt is isolated on its own', () => {
    const out = rtlPlain('שורה ראשונה\nשורה שנייה')
    expect(out).toBe(RLM + RLI + 'שורה ראשונה' + PDI + '\n' + RLI + 'שורה שנייה' + PDI)
  })
  test('an English sentence with one Hebrew word stays LTR', () => {
    const s = 'Please fix the build for שלום today'
    expect(rtlPlain(s)).toBe(s)
  })
})

describe('hooks', () => {
  for (const surface of ['desktop', 'vscode', 'terminal'] as const) {
    test(`AssistantMessage on ${surface}`, async ($, on) => {
      let drawn = ''
      on('ui.render', { component: 'AssistantMessage' }, ($, e) => {
        drawn = e.props.text

        return { type: 'Text', children: [e.props.text] }
      })
      await $.ui.render({
        component: 'AssistantMessage',
        surface,
        requestId: 'm1',
        props: { text: 'קובץ index.js', isFirstOfReply: true },
      })
      expect(drawn).toBe(surface === 'terminal' ? 'קובץ index.js' : RLM + 'קובץ index.js')
    })
  }
})

describe('atomize', () => {
  const show = (s: string) => atomize(s).map(a => a.text.replace(/ /g, '_')).join('|')
  test('splits a mixed prompt into single-direction pieces in logical order', () => {
    expect(show('Nvidia, מה ההבדל בין GPU ל-CPU?')).toBe('Nvidia|_,|מה|_|ההבדל|_|בין|_|GPU|_|ל|-|CPU|?')
  })
  test('keeps an English run whole and mirrors brackets between directions', () => {
    expect(show('מניית S&P 500 (מדד) עלתה')).toBe('מניית|_|S&P_500|)_|מדד|_(|עלתה')
  })
})

describe('nativeReadsRight', () => {
  test('one plain Hebrew line keeps the native bubble', () => {
    expect(nativeReadsRight('אפשרות 4')).toBe(true)
    expect(nativeReadsRight('תמשיך עם המשימות')).toBe(true)
  })
  test('punctuation at an end, English, or several lines need the hand layout', () => {
    expect(nativeReadsRight('בסשן חדש:')).toBe(false)
    expect(nativeReadsRight('תבדוק את NVDA')).toBe(false)
    expect(nativeReadsRight('שורה\nשנייה')).toBe(false)
    expect(nativeReadsRight('4 אפשרויות')).toBe(false)
  })
})
