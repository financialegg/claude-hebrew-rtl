// Rewrites a message's markdown with Unicode bidi controls so the surface's
// own renderer lays out Hebrew/Arabic correctly. A plugin cannot set `dir`
// or CSS, so direction is expressed in the text itself:
//
// - RLM (U+200F) opening a block: the desktop Code tab's native detector
//   reads the block's first strong character (RLM counts as RTL), so a Hebrew
//   block that starts with a filename, inline code or an English term, or a
//   list/table whose first item/header is English, still gets dir="rtl".
// - RLI/LRI ... PDI isolates: keep a line, list item or table cell of the
//   other direction, inline code and arithmetic/LaTeX in their own order.

import { blockDir, cellDir, mathRanges, tableDirFromCells } from './rtl-core'
import type { Dir } from './rtl-core'

export const RLM = '\u200F'
export const LRI = '\u2066'
export const RLI = '\u2067'
export const PDI = '\u2069'

const isolate = (text: string, dir: Dir) =>
  text.trim() === '' ? text : (dir === 'rtl' ? RLI : LRI) + text + PDI

const FENCE = /^\s{0,3}(`{3,}|~{3,})/
const MATH_BLOCK = /^\s*\$\$\s*$/
const HEADING = /^(\s{0,3}#{1,6}\s+)(.*)$/
const QUOTE = /^(\s{0,3}>\s?)(.*)$/
const LIST_ITEM = /^(\s*(?:[-*+]|\d{1,9}[.)])\s+(?:\[[ xX]\]\s+)?)(.*)$/
const HR = /^\s{0,3}(?:(?:-\s*){3,}|(?:\*\s*){3,}|(?:_\s*){3,})$/
const TABLE_SEP = /^\s*\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)*\|?\s*$/
const isBlank = (line: string) => line.trim() === ''
const isTableRow = (line: string) => line.includes('|') && !isBlank(line)

// Wrap inline code spans and math islands of RTL content in LTR isolates.
// Link destinations and bare URLs are masked so nothing lands inside them.
export function isolateInline(text: string): string {
  const cuts: Array<[number, number]> = []
  let masked = text
  const mask = (s: number, e: number) => {
    masked = masked.slice(0, s) + '#'.repeat(e - s) + masked.slice(e)
  }

  for (const m of text.matchAll(/(`+)(?:(?!\1)[\s\S])+?\1/g)) {
    cuts.push([m.index!, m.index! + m[0].length])
    mask(m.index!, m.index! + m[0].length)
  }
  for (const m of masked.matchAll(/\]\([^)]*\)|<[a-z][\w+.-]*:[^>\s]*>|https?:\/\/\S+/gi)) {
    mask(m.index!, m.index! + m[0].length)
  }
  for (const [s, e] of mathRanges(masked)) {
    if (!/#/.test(masked.slice(s, e))) cuts.push([s, e])
  }

  let out = text
  for (const [s, e] of cuts.sort((a, b) => b[0] - a[0])) {
    out = out.slice(0, s) + LRI + out.slice(s, e) + PDI + out.slice(e)
  }

  return out
}

// A block's content in direction `dir`; RLM first when it opens an RTL block.
function content(text: string, dir: Dir | null, isOpening: boolean): string {
  if (dir !== 'rtl') return text
  const body = isolateInline(text)

  return isOpening ? RLM + body : body
}

function splitCells(row: string): { lead: string; cells: string[]; trail: string } {
  const lead = /^\s*\|?/.exec(row)![0]
  const trail = /\|?\s*$/.exec(row.slice(lead.length))![0]
  const inner = row.slice(lead.length, row.length - trail.length)
  const cells: string[] = []
  let cell = ''
  let ticks = 0
  for (let i = 0; i < inner.length; i++) {
    const ch = inner[i]
    if (ch === '`') ticks ^= 1
    if (ch === '\\' && inner[i + 1] === '|') {
      cell += '\\|'
      i++
      continue
    }
    if (ch === '|' && ticks === 0) {
      cells.push(cell)
      cell = ''
      continue
    }
    cell += ch
  }
  cells.push(cell)

  return { lead, cells, trail }
}

function table(rows: string[]): string[] {
  const parsed = rows.map(splitCells)
  const header = parsed[0]!.cells
  const body = parsed.slice(2)
  const dir =
    tableDirFromCells(
      header.map(c => cellDir(c.trim())),
      body.map(r => cellDir((r.cells[0] ?? '').trim())),
    ) ?? 'ltr'

  return parsed.map(({ lead, cells, trail }, r) => {
    if (r === 1) return rows[1]!
    const out = cells.map((raw, c) => {
      const text = raw.trim()
      const own = cellDir(text) ?? dir
      let cell = own === 'rtl' ? isolateInline(text) : text
      if (own !== dir) cell = isolate(cell, own)
      // The native renderer flips a table by its first header cell alone.
      if (r === 0 && c === 0 && dir === 'rtl') cell = RLM + cell
      const pad = raw.match(/^\s*/)![0]
      const end = raw.match(/\s*$/)![0]

      return text === '' ? raw : pad + cell + end
    })

    return lead + out.join('|') + trail
  })
}

// A run of list items (with their continuation lines and blank gaps).
function list(lines: string[]): string[] {
  const items = lines.map(l => LIST_ITEM.exec(l))
  const dir =
    blockDir(
      items
        .filter((m): m is RegExpExecArray => m !== null)
        .map(m => m[2])
        .join('\n'),
    ) ?? 'ltr'
  let opened: number[] = []

  return lines.map((line, i) => {
    const m = items[i]
    if (!m) {
      if (isBlank(line)) return line
      const indent = line.match(/^\s*/)![0]
      const own = blockDir(line.trim()) ?? dir
      const text = own === 'rtl' ? isolateInline(line.trim()) : line.trim()

      return indent + (own === dir ? text : isolate(text, own))
    }
    const marker = m[1]!
    const body = m[2]!
    const depth = marker.search(/\S/)
    opened = opened.filter(d => d <= depth)
    const isFirstAtDepth = !opened.includes(depth)
    if (isFirstAtDepth) opened.push(depth)
    const own = blockDir(body) ?? dir
    let text = own === 'rtl' ? isolateInline(body) : body
    if (own !== dir) text = isolate(text, own)
    // Native judges a list by its first item: open each RTL list with RLM.
    if (dir === 'rtl' && (isFirstAtDepth || own === 'rtl')) text = RLM + text

    return marker + text
  })
}

function paragraph(lines: string[]): string[] {
  const dir = blockDir(lines.join('\n'))
  if (dir === null) return lines
  const dirs = lines.map(l => blockDir(l) ?? dir)
  const isMixed = dirs.some(d => d !== dir)

  return lines.map((line, i) => {
    const own = dirs[i]!
    const text = own === 'rtl' ? isolateInline(line) : line
    const lead = line.match(/^\s*/)![0]
    const body = text.slice(lead.length)
    const wrapped = isMixed && own !== dir ? isolate(body, own) : body

    return lead + (i === 0 && dir === 'rtl' ? RLM : '') + wrapped
  })
}

const startsBlock = (line: string, next: string | undefined) =>
  isBlank(line) ||
  FENCE.test(line) ||
  MATH_BLOCK.test(line) ||
  HEADING.test(line) ||
  QUOTE.test(line) ||
  LIST_ITEM.test(line) ||
  HR.test(line) ||
  (isTableRow(line) && next !== undefined && TABLE_SEP.test(next))

// Transforms markdown; returns it unchanged when it holds no RTL text.
export function rtlMarkdown(text: string): string {
  if (!/[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]|[\u{10800}-\u{10e7f}\u{1e800}-\u{1eeff}]/u.test(text)) {
    return text
  }
  const lines = text.split('\n')
  const at = (k: number) => lines[k] ?? ''
  const out: string[] = []
  let i = 0

  while (i < lines.length) {
    const line = lines[i]!

    const fence = FENCE.exec(line)
    if (fence) {
      const close = new RegExp('^\\s{0,3}' + fence[1]![0] + '{' + fence[1]!.length + ',}\\s*$')
      let j = i + 1
      while (j < lines.length && !close.test(at(j))) j++
      out.push(...lines.slice(i, j + 1))
      i = j + 1
      continue
    }

    if (MATH_BLOCK.test(line)) {
      let j = i + 1
      while (j < lines.length && !MATH_BLOCK.test(at(j))) j++
      out.push(...lines.slice(i, j + 1))
      i = j + 1
      continue
    }

    if (isBlank(line) || HR.test(line)) {
      out.push(line)
      i++
      continue
    }

    if (isTableRow(line) && i + 1 < lines.length && TABLE_SEP.test(at(i + 1))) {
      let j = i + 2
      while (j < lines.length && isTableRow(at(j))) j++
      out.push(...table(lines.slice(i, j)))
      i = j
      continue
    }

    const heading = HEADING.exec(line)
    if (heading) {
      out.push(heading[1]! + content(heading[2]!, blockDir(heading[2]!), true))
      i++
      continue
    }

    if (QUOTE.test(line)) {
      let j = i
      while (j < lines.length && QUOTE.test(at(j))) j++
      const quoted = lines.slice(i, j).map(l => QUOTE.exec(l)!)
      const inner = rtlMarkdown(quoted.map(m => m[2]!).join('\n')).split('\n')
      out.push(...inner.map((l, k) => quoted[k]![1] + l))
      i = j
      continue
    }

    if (LIST_ITEM.test(line)) {
      let j = i + 1
      while (j < lines.length) {
        const l = at(j)
        if (LIST_ITEM.test(l) || (/^\s+\S/.test(l) && !FENCE.test(l))) {
          j++
          continue
        }
        if (isBlank(l) && j + 1 < lines.length && LIST_ITEM.test(at(j + 1))) {
          j++
          continue
        }
        break
      }
      out.push(...list(lines.slice(i, j)))
      i = j
      continue
    }

    let j = i + 1
    while (j < lines.length && !startsBlock(at(j), at(j + 1))) j++
    out.push(...paragraph(lines.slice(i, j)))
    i = j
  }

  return out.join('\n')
}

// A user's message, drawn as typed: each line isolated in its own direction.
export function rtlPlain(text: string): string {
  if (!/[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]/.test(text)) return text
  const dir = blockDir(text) ?? 'ltr'

  return text
    .split('\n')
    .map((line, i) => {
      const own = blockDir(line) ?? dir
      // ponytail: the desktop user bubble ignores a leading RLM (no native detection
      // there), so every RTL line gets its own RLI..PDI to fix its reading order.
      const body = own === 'rtl' ? isolate(isolateInline(line), 'rtl') : line

      return (i === 0 && dir === 'rtl' ? RLM : '') + (own === 'rtl' || own === dir ? body : isolate(body, own))
    })
    .join('\n')
}
