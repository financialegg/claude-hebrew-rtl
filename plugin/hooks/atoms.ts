import { isRTL } from './rtl-core'

// The desktop strips bidi controls from what a plugin draws, so an RTL line is laid out
// by hand: cut into single-direction pieces in logical order, drawn in a row-reverse Box.
// An English run (with the spaces/punctuation inside it, "S&P 500") stays one piece;
// Hebrew is cut per word so lines wrap; a neutral between directions takes RTL, so its
// characters are reversed and brackets mirrored.
// ponytail: a hand-rolled slice of the bidi algorithm; numbers inside Hebrew ("5%") ride
// with the English class, which is how they read in Hebrew anyway.

const isLtr = (ch: string) => /[A-Za-z0-9]/.test(ch)
const MIRROR: Record<string, string> = { '(': ')', ')': '(', '[': ']', ']': '[', '{': '}', '}': '{', '<': '>', '>': '<' }
const NBSP = ' '
const RTL_SPLIT = /([^֐-ࣿיִ-﷿ﹰ-﻿]+)/

export type Atom = { text: string; dir: 'rtl' | 'ltr' | 'neutral' }

export function atomize(line: string): Atom[] {
  const chars = [...line]
  const cls = chars.map(ch => (isRTL(ch.codePointAt(0)!) ? 'r' : isLtr(ch) ? 'l' : 'n'))
  // A neutral run takes the class of strong neighbours that agree, else RTL (paragraph).
  for (let i = 0; i < cls.length; ) {
    if (cls[i] !== 'n') { i++; continue }
    let j = i
    while (j < cls.length && cls[j] === 'n') j++
    const before = cls[i - 1], after = cls[j]
    const resolved = before && before === after ? before : 'n'
    for (let k = i; k < j; k++) cls[k] = resolved
    i = j
  }
  const atoms: Atom[] = []
  let i = 0
  while (i < chars.length) {
    let j = i
    while (j < chars.length && cls[j] === cls[i]) j++
    const run = chars.slice(i, j).join('')
    if (cls[i] === 'l') atoms.push({ text: run.replace(/ /g, NBSP), dir: 'ltr' })
    // Hebrew letters stay whole words; everything between them (spaces, punctuation,
    // gershayim) is its own reversed piece, so nothing sits on the wrong side of a word.
    else for (const part of cls[i] === 'r' ? run.split(RTL_SPLIT) : [run]) {
      if (!part) continue
      if (cls[i] === 'r' && isRTL(part.codePointAt(0)!)) atoms.push({ text: part, dir: 'rtl' })
      else atoms.push({ text: [...part].reverse().map(c => MIRROR[c] ?? (c === ' ' ? NBSP : c)).join(''), dir: 'neutral' })
    }
    i = j
  }
  return atoms
}


// The native desktop bubble is LTR with no bidi help. It still reads right only for one
// line of Hebrew with no English letters that starts with a Hebrew letter and ends with
// one or a digit ("אפשרות 4"); anything else gets drawn by hand (and loses the native
// date/copy/rewind row, which a plugin can't draw).
export function nativeReadsRight(text: string): boolean {
  const t = text.trim()
  if (!t || t.includes('\n') || /[A-Za-z]/.test(t)) return false
  const first = t.codePointAt(0)!
  const last = [...t].pop()!
  return isRTL(first) && (isRTL(last.codePointAt(0)!) || /[0-9]/.test(last))
}
