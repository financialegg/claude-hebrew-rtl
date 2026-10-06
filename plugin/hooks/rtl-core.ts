// Pure RTL / LaTeX / arithmetic detection. Ported from the detection core of
// claude-desktop-rtl-patch by shraga100 (MIT).

export type Dir = 'rtl' | 'ltr'

// Strong-RTL code-point ranges, [lo, hi] inclusive, incl. RLM/RLE/RLO/RLI.
const RTL_RANGES: ReadonlyArray<readonly [number, number]> = [
  [0x0590, 0x05ff], // Hebrew
  [0x0600, 0x06ff], // Arabic
  [0x0700, 0x074f], // Syriac
  [0x0750, 0x077f], // Arabic Supplement
  [0x0780, 0x07bf], // Thaana
  [0x07c0, 0x07ff], // NKo
  [0x0800, 0x083f], // Samaritan
  [0x0840, 0x085f], // Mandaic
  [0x0860, 0x086f], // Syriac Supplement
  [0x0870, 0x089f], // Arabic Extended-B
  [0x08a0, 0x08ff], // Arabic Extended-A
  [0x200f, 0x200f], // RLM
  [0x202b, 0x202b], // RLE
  [0x202e, 0x202e], // RLO
  [0x2067, 0x2067], // RLI
  [0xfb1d, 0xfb4f], // Hebrew presentation forms
  [0xfb50, 0xfdff], // Arabic presentation forms-A
  [0xfe70, 0xfeff], // Arabic presentation forms-B
  [0x10800, 0x1083f],
  [0x10840, 0x1085f],
  [0x10a00, 0x10a5f],
  [0x10e60, 0x10e7f],
  [0x1e800, 0x1e8df],
  [0x1e900, 0x1e95f],
  [0x1ee00, 0x1eeff],
]

export function isRTL(cp: number): boolean {
  return RTL_RANGES.some(([lo, hi]) => cp >= lo && cp <= hi)
}

const isLatin = (cp: number) => (cp >= 0x41 && cp <= 0x5a) || (cp >= 0x61 && cp <= 0x7a)

export function hasRTL(text: string): boolean {
  for (const ch of text) {
    if (isRTL(ch.codePointAt(0)!)) return true
  }
  return false
}

// Direction of the first strong character, or null when there is none.
export function firstStrong(text: string): Dir | null {
  for (const ch of text) {
    const cp = ch.codePointAt(0)!
    if (isRTL(cp)) return 'rtl'
    if (isLatin(cp)) return 'ltr'
  }
  return null
}

// Hebrew-first: words with an RTL letter at least match Latin-only words.
// ponytail: counts words, not letters (upstream), so "Nvidia, מה ההבדל בין GPU ל-CPU?" is RTL.
export function rtlMajority(text: string): boolean {
  let r = 0
  let l = 0
  for (const word of text.split(/[\s\-]+/)) {
    const cps = [...word].map(ch => ch.codePointAt(0)!)
    if (cps.some(isRTL)) r++
    else if (cps.some(isLatin)) l++
  }
  return r >= l
}

// Drop leading LTR-only noise (filenames, URLs, paths, inline code).
export function stripLeadingLTR(text: string): string {
  return text
    .replace(/^[\s]*(?:[\w.\-]+\.[\w]{1,5})\s*/g, '')
    .replace(/https?:\/\/\S+/g, '')
    .replace(/[\w.\-]+[\/\\][\w.\-\/\\]+/g, '')
    .replace(/`[^`]+`/g, '')
}

const LATEX_SIGNAL =
  /[\\^_{}]|\b(?:frac|sqrt|sum|prod|int|lim|infty|cdot|times|div|leq|geq|neq|approx|partial|nabla|alpha|beta|gamma|delta|theta|lambda|mu|pi|sigma|omega|matrix|begin|end|left|right|text|mathbb|mathcal|vec|hat|bar|overline|underline)\b/

type Range = [number, number]

export function findLatexRanges(text: string): Range[] {
  const ranges: Range[] = []
  const overlaps = (s: number, e: number) => ranges.some(r => s < r[1] && e > r[0])
  const claim = (re: RegExp, requireSignal: boolean, cut: number) => {
    for (const m of text.matchAll(re)) {
      const start = m.index!
      const end = start + m[0].length
      if (overlaps(start, end)) continue
      if (requireSignal && !LATEX_SIGNAL.test(m[0].slice(cut, m[0].length - cut))) continue
      ranges.push([start, end])
    }
  }
  claim(/\$\$[\s\S]+?\$\$/g, false, 0)
  claim(/\\\[[\s\S]+?\\\]/g, false, 0)
  claim(/\\\([\s\S]+?\\\)/g, false, 0)
  claim(/\$[^$\n]+?\$/g, true, 1)

  return ranges.sort((a, b) => a[0] - b[0])
}

const MATH_OP_CHARS = '+\\-*/=<>%\u00D7\u00F7\u00B1\u2212\u2264\u2265\u2260\u2248\u2192\u00B7\u2022\u2219\u2217\u22C5\u221A'
const MATH_OP_RE = new RegExp('[' + MATH_OP_CHARS + ']')
const MATH_DIGIT_RE = /[0-9]/
const MATH_TOKEN_RE = new RegExp('^(?:[0-9.,:;()\\[\\]{}|' + MATH_OP_CHARS + ']+|[A-Za-z])$')

const isMathyToken = (tok: string) => MATH_TOKEN_RE.test(tok)
const isOperandToken = (tok: string) => MATH_DIGIT_RE.test(tok) || /^[A-Za-z]$/.test(tok)

// Bare arithmetic runs ("2 + 3 = 5") that bidi would mirror inside RTL text.
export function findMathRanges(text: string): Range[] {
  const ranges: Range[] = []
  if (!MATH_OP_RE.test(text) || !MATH_DIGIT_RE.test(text)) return ranges

  let off = 0
  for (const line of text.split('\n')) {
    const toks = [...line.matchAll(/\S+/g)].map(m => ({
      v: m[0],
      start: m.index!,
      end: m.index! + m[0].length,
    }))
    let i = 0
    while (i < toks.length) {
      if (!isMathyToken(toks[i]!.v)) {
        i++
        continue
      }
      let j = i
      while (j + 1 < toks.length && isMathyToken(toks[j + 1]!.v)) j++
      let a = i
      let b = j
      while (a <= b && !isOperandToken(toks[a]!.v)) a++
      while (b >= a && !isOperandToken(toks[b]!.v)) b--
      if (a <= b) {
        let s = off + toks[a]!.start
        let e = off + toks[b]!.end
        while (e > s && '.,:;'.includes(text.charAt(e - 1))) e--
        while (e > s && ',:;'.includes(text.charAt(s))) s++
        const sub = text.slice(s, e)
        if (e - s >= 2 && MATH_DIGIT_RE.test(sub) && MATH_OP_RE.test(sub)) ranges.push([s, e])
      }
      i = j + 1
    }
    off += line.length + 1
  }

  return ranges
}

// LaTeX islands plus bare arithmetic, LaTeX winning where they overlap.
export function mathRanges(text: string): Range[] {
  const ranges = findLatexRanges(text)
  for (const n of findMathRanges(text)) {
    if (!ranges.some(r => n[0] < r[1] && n[1] > r[0])) ranges.push(n)
  }

  return ranges.sort((a, b) => a[0] - b[0])
}

// A table cell is RTL if it contains any RTL char; neutral cells are null.
export function cellDir(text: string): Dir | null {
  if (hasRTL(text)) return 'rtl'
  if (firstStrong(text) === 'ltr') return 'ltr'
  return null
}

export function majorityDir(dirs: ReadonlyArray<Dir | null>): Dir | null {
  const r = dirs.filter(d => d === 'rtl').length
  const l = dirs.filter(d => d === 'ltr').length
  if (r > l) return 'rtl'
  if (l > r) return 'ltr'
  return null
}

// Table column direction: header majority, first column as tie-breaker.
export function tableDirFromCells(
  headerDirs: ReadonlyArray<Dir | null>,
  firstColDirs: ReadonlyArray<Dir | null>,
): Dir | null {
  if (headerDirs[0] === 'rtl' && firstColDirs[0] === 'rtl') return 'rtl'
  const h = majorityDir(headerDirs)
  if (h === 'rtl') return 'rtl'
  if (h === 'ltr') return null
  return majorityDir(firstColDirs) === 'rtl' ? 'rtl' : null
}

// Three-layer block detector: without inline code, then with
// leading LTR noise stripped, then majority of strong characters.
export function blockDir(text: string): Dir | null {
  if (!hasRTL(text)) return firstStrong(text)
  const noCode = text.replace(/`+[^`]*`+/g, '')
  if (firstStrong(noCode) === 'rtl') return 'rtl'
  if (firstStrong(stripLeadingLTR(text)) === 'rtl') return 'rtl'
  return rtlMajority(text) ? 'rtl' : 'ltr'
}
