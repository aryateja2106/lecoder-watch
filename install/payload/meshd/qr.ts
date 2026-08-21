// qr.ts — a QR encoder with no dependencies, because the payload ships as plain .ts
// files that bun runs in place: an npm package here would mean an install step on
// every machine the curl one-liner touches, on a box that may have no network left
// after the daemon binds. `mesh pair` renders this matrix as half-block characters so
// a phone can scan the pairing URL straight off the terminal.
//
// Scope is deliberately narrow: byte mode, error-correction level M, versions 1-10
// (213 bytes — a pairing URL is ~60). Alphanumeric/kanji modes would shrink the code
// for some inputs but need their own tables; versions past 10 are 57+ modules wide and
// stop being scannable off a terminal anyway.
//
// The algorithm is the one in ISO/IEC 18004, arranged the way Nayuki's reference
// generator arranges it: segment bits -> Reed-Solomon blocks -> zigzag placement ->
// mask by penalty score. Correctness is not eyeballed — `bun qr.ts --check` reads the
// finished matrix back through a separately written decoder (own function-module map,
// own format-info reader, RS syndromes) and demands the original bytes come out.

const MIN_VERSION = 1;
const MAX_VERSION = 10;

// EC level M only. Indexed by version, so slot 0 is a placeholder. From ISO/IEC 18004
// tables 13-22; the resulting data-codeword counts are asserted against the published
// byte capacities in --check, which is what pins these numbers down.
const ECC_PER_BLOCK = [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26];
const BLOCKS = /*  */ [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5];
const FORMAT_BITS_M = 0b00; // L=01, M=00, Q=11, H=10 — not the level ordering
const BYTE_MODE = 0b0100;

// Penalty weights from the standard: long runs, 2x2 blocks, finder-lookalikes, and
// dark/light imbalance.
const PENALTY_N1 = 3, PENALTY_N2 = 3, PENALTY_N3 = 40, PENALTY_N4 = 10;

type Grid = {
  version: number;
  size: number;
  modules: boolean[][];  // [y][x], true = dark
  fn: boolean[][];       // [y][x], true = function module (never carries data, never masked)
};

// ------------------------------------------------------------------ capacity

/** Total modules usable for data+ECC codewords, before the /8 truncation. */
function numRawDataModules(ver: number): number {
  let result = (16 * ver + 128) * ver + 64;
  if (ver >= 2) {
    const numAlign = Math.floor(ver / 7) + 2;
    result -= (25 * numAlign - 10) * numAlign - 55;  // alignment patterns, minus timing overlap
    if (ver >= 7) result -= 36;                      // two 6x3 version-information blocks
  }
  return result;
}

function numDataCodewords(ver: number): number {
  return Math.floor(numRawDataModules(ver) / 8) - ECC_PER_BLOCK[ver] * BLOCKS[ver];
}

/** Byte mode's character-count field widens at version 10. */
function charCountBits(ver: number): number {
  return ver <= 9 ? 8 : 16;
}

function maxBytes(ver: number): number {
  return Math.floor((numDataCodewords(ver) * 8 - 4 - charCountBits(ver)) / 8);
}

function pickVersion(byteLen: number): number {
  for (let ver = MIN_VERSION; ver <= MAX_VERSION; ver++) if (byteLen <= maxBytes(ver)) return ver;
  throw new Error(
    `qr: ${byteLen} bytes is too long — version ${MAX_VERSION} at EC level M holds ${maxBytes(MAX_VERSION)}`,
  );
}

// ---------------------------------------------------------------- field math

/** GF(2^8) product, primitive polynomial x^8+x^4+x^3+x^2+1 (0x11D) — the QR field. */
function gfMul(x: number, y: number): number {
  let z = 0;
  for (let i = 7; i >= 0; i--) {
    z = (z << 1) ^ ((z >>> 7) * 0x11d);  // shift, reducing whenever bit 8 would appear
    z ^= ((y >>> i) & 1) * x;
  }
  return z;
}

/** Coefficients of (x - a^0)(x - a^1)...(x - a^(degree-1)), highest power omitted. */
function rsDivisor(degree: number): Uint8Array {
  const result = new Uint8Array(degree);
  result[degree - 1] = 1;
  let root = 1;
  for (let i = 0; i < degree; i++) {
    for (let j = 0; j < degree; j++) {
      result[j] = gfMul(result[j], root);
      if (j + 1 < degree) result[j] ^= result[j + 1];
    }
    root = gfMul(root, 0x02);
  }
  return result;
}

function rsRemainder(data: ArrayLike<number>, divisor: Uint8Array): Uint8Array {
  const result = new Uint8Array(divisor.length);
  for (let i = 0; i < data.length; i++) {
    const factor = data[i] ^ result[0];
    result.copyWithin(0, 1);
    result[result.length - 1] = 0;
    for (let j = 0; j < result.length; j++) result[j] ^= gfMul(divisor[j], factor);
  }
  return result;
}

// -------------------------------------------------------------- data encoding

function encodeData(data: Uint8Array, version: number): Uint8Array {
  const bits: number[] = [];
  const push = (val: number, len: number) => { for (let i = len - 1; i >= 0; i--) bits.push((val >>> i) & 1); };

  push(BYTE_MODE, 4);
  push(data.length, charCountBits(version));
  for (const b of data) push(b, 8);

  const capacity = numDataCodewords(version) * 8;
  push(0, Math.min(4, capacity - bits.length));   // terminator, truncated if it does not fit
  push(0, (8 - (bits.length % 8)) % 8);           // to the byte boundary
  // Alternating pad bytes, per the standard. Any constant would decode the same; the
  // standard picks these two so the pad region does not mask into a flat field.
  for (let pad = 0xec; bits.length < capacity; pad ^= 0xec ^ 0x11) push(pad, 8);

  const out = new Uint8Array(bits.length / 8);
  bits.forEach((bit, i) => { out[i >>> 3] |= bit << (7 - (i & 7)); });
  return out;
}

/**
 * Split into RS blocks, append each block's ECC, then interleave. Interleaving is what
 * makes a scratch across the symbol survivable: a burst hits one codeword per block
 * instead of wiping a single block past its correction budget.
 */
function addEccAndInterleave(data: Uint8Array, version: number): Uint8Array {
  const numBlocks = BLOCKS[version];
  const eccLen = ECC_PER_BLOCK[version];
  const rawCodewords = Math.floor(numRawDataModules(version) / 8);
  const numShort = numBlocks - (rawCodewords % numBlocks);
  const shortLen = Math.floor(rawCodewords / numBlocks);

  const divisor = rsDivisor(eccLen);
  const blocks: number[][] = [];
  for (let i = 0, k = 0; i < numBlocks; i++) {
    const len = shortLen - eccLen + (i < numShort ? 0 : 1);
    const dat = Array.from(data.slice(k, k + len));
    k += len;
    const ecc = Array.from(rsRemainder(dat, divisor));
    // Pad short blocks to a common length so the interleaver is a plain column walk;
    // the dummy byte is skipped on the way out, never transmitted.
    if (i < numShort) dat.push(0);
    blocks.push(dat.concat(ecc));
  }

  const out: number[] = [];
  for (let i = 0; i < blocks[0].length; i++) {
    for (let j = 0; j < numBlocks; j++) {
      if (i !== shortLen - eccLen || j >= numShort) out.push(blocks[j][i]);
    }
  }
  return Uint8Array.from(out);
}

// ------------------------------------------------------------------- drawing

function newGrid(version: number): Grid {
  const size = version * 4 + 17;
  const grid = (): boolean[][] => Array.from({ length: size }, () => new Array<boolean>(size).fill(false));
  return { version, size, modules: grid(), fn: grid() };
}

function setFn(g: Grid, x: number, y: number, dark: boolean): void {
  if (x < 0 || y < 0 || x >= g.size || y >= g.size) return;
  g.modules[y][x] = dark;
  g.fn[y][x] = true;
}

/** 7x7 concentric squares plus the light separator ring, clipped at the border. */
function drawFinder(g: Grid, cx: number, cy: number): void {
  for (let dy = -4; dy <= 4; dy++) {
    for (let dx = -4; dx <= 4; dx++) {
      const dist = Math.max(Math.abs(dx), Math.abs(dy));  // Chebyshev distance = ring index
      setFn(g, cx + dx, cy + dy, dist !== 2 && dist !== 4);
    }
  }
}

function drawAlignment(g: Grid, cx: number, cy: number): void {
  for (let dy = -2; dy <= 2; dy++) {
    for (let dx = -2; dx <= 2; dx++) setFn(g, cx + dx, cy + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
  }
}

/** Centre coordinates of the alignment pattern grid, per the standard's spacing rule. */
function alignPositions(version: number): number[] {
  if (version === 1) return [];
  const numAlign = Math.floor(version / 7) + 2;
  const step = Math.ceil((version * 4 + 4) / (numAlign * 2 - 2)) * 2;
  const result = [6];
  for (let pos = version * 4 + 17 - 7; result.length < numAlign; pos -= step) result.splice(1, 0, pos);
  return result;
}

function drawFunctionPatterns(g: Grid): void {
  for (let i = 0; i < g.size; i++) {
    setFn(g, 6, i, i % 2 === 0);   // vertical timing
    setFn(g, i, 6, i % 2 === 0);   // horizontal timing
  }
  drawFinder(g, 3, 3);
  drawFinder(g, g.size - 4, 3);
  drawFinder(g, 3, g.size - 4);

  const pos = alignPositions(g.version);
  for (let i = 0; i < pos.length; i++) {
    for (let j = 0; j < pos.length; j++) {
      // The three corners are occupied by finder patterns.
      const corner = (i === 0 && j === 0) || (i === 0 && j === pos.length - 1) || (i === pos.length - 1 && j === 0);
      if (!corner) drawAlignment(g, pos[i], pos[j]);
    }
  }

  drawFormatBits(g, 0);  // placeholder: reserves the modules so drawCodewords skips them
  drawVersion(g);
}

/** 15 bits: 2 EC-level + 3 mask, BCH(15,5) with generator 0x537, XORed with 0x5412. */
function drawFormatBits(g: Grid, mask: number): void {
  const data = (FORMAT_BITS_M << 3) | mask;
  let rem = data;
  for (let i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
  // The XOR mask exists so an all-light symbol cannot produce a valid format string.
  const bits = ((data << 10) | rem) ^ 0x5412;
  const bit = (i: number) => ((bits >>> i) & 1) !== 0;

  // Copy one, wrapped around the top-left finder.
  for (let i = 0; i <= 5; i++) setFn(g, 8, i, bit(i));
  setFn(g, 8, 7, bit(6));
  setFn(g, 8, 8, bit(7));
  setFn(g, 7, 8, bit(8));
  for (let i = 9; i < 15; i++) setFn(g, 14 - i, 8, bit(i));

  // Copy two, split between the other two finders, so a torn corner still decodes.
  for (let i = 0; i < 8; i++) setFn(g, g.size - 1 - i, 8, bit(i));
  for (let i = 8; i < 15; i++) setFn(g, 8, g.size - 15 + i, bit(i));
  setFn(g, 8, g.size - 8, true);  // the always-dark module
}

/** 18 bits: 6 version + BCH(18,6), two copies. Only versions 7 and up carry it. */
function drawVersion(g: Grid): void {
  if (g.version < 7) return;
  let rem = g.version;
  for (let i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >>> 11) * 0x1f25);
  const bits = (g.version << 12) | rem;
  for (let i = 0; i < 18; i++) {
    const dark = ((bits >>> i) & 1) !== 0;
    const a = g.size - 11 + (i % 3);
    const b = Math.floor(i / 3);
    setFn(g, a, b, dark);
    setFn(g, b, a, dark);
  }
}

/** The zigzag: two-module-wide columns, right to left, alternating up and down. */
function drawCodewords(g: Grid, data: Uint8Array): void {
  let i = 0;  // bit index
  for (let right = g.size - 1; right >= 1; right -= 2) {
    if (right === 6) right = 5;  // the vertical timing line is not part of a column pair
    for (let vert = 0; vert < g.size; vert++) {
      for (let j = 0; j < 2; j++) {
        const x = right - j;
        const upward = ((right + 1) & 2) === 0;
        const y = upward ? g.size - 1 - vert : vert;
        if (!g.fn[y][x] && i < data.length * 8) {
          g.modules[y][x] = ((data[i >>> 3] >>> (7 - (i & 7))) & 1) !== 0;
          i++;
        }
      }
    }
  }
  // Any leftover modules stay light: the standard's remainder bits, which carry nothing.
}

function maskAt(mask: number, x: number, y: number): boolean {
  switch (mask) {
    case 0: return (x + y) % 2 === 0;
    case 1: return y % 2 === 0;
    case 2: return x % 3 === 0;
    case 3: return (x + y) % 3 === 0;
    case 4: return (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0;
    case 5: return ((x * y) % 2) + ((x * y) % 3) === 0;
    case 6: return (((x * y) % 2) + ((x * y) % 3)) % 2 === 0;
    case 7: return (((x + y) % 2) + ((x * y) % 3)) % 2 === 0;
    default: throw new Error(`qr: mask ${mask} out of range`);
  }
}

/** XOR is its own inverse, so this both applies and undoes a mask. */
function applyMask(g: Grid, mask: number): void {
  for (let y = 0; y < g.size; y++) {
    for (let x = 0; x < g.size; x++) if (!g.fn[y][x] && maskAt(mask, x, y)) g.modules[y][x] = !g.modules[y][x];
  }
}

// ------------------------------------------------------- mask penalty scoring

/** Rule 3: 1:1:3:1:1 surrounded by 4 light modules — a run of five looking like a finder. */
function finderPenaltyCount(history: number[]): number {
  const n = history[1];
  const core = n > 0 && history[2] === n && history[3] === n * 3 && history[4] === n && history[5] === n;
  return (core && history[0] >= n * 4 && history[6] >= n ? 1 : 0)
    + (core && history[6] >= n * 4 && history[0] >= n ? 1 : 0);
}

function finderPenaltyPush(size: number, runLength: number, history: number[]): void {
  if (history[0] === 0) runLength += size;  // the quiet zone counts as light before the first run
  history.pop();
  history.unshift(runLength);
}

function finderPenaltyEnd(size: number, runColor: boolean, runLength: number, history: number[]): number {
  if (runColor) { finderPenaltyPush(size, runLength, history); runLength = 0; }
  runLength += size;  // quiet zone after the last run
  finderPenaltyPush(size, runLength, history);
  return finderPenaltyCount(history);
}

function penaltyScore(g: Grid): number {
  let result = 0;
  const size = g.size;

  // Rules 1 and 3, once per row and once per column.
  for (let pass = 0; pass < 2; pass++) {
    for (let a = 0; a < size; a++) {
      let runColor = false, run = 0;
      const history = [0, 0, 0, 0, 0, 0, 0];
      for (let b = 0; b < size; b++) {
        const dark = pass === 0 ? g.modules[a][b] : g.modules[b][a];
        if (dark === runColor) {
          run++;
          if (run === 5) result += PENALTY_N1;
          else if (run > 5) result++;
        } else {
          finderPenaltyPush(size, run, history);
          if (!runColor) result += finderPenaltyCount(history) * PENALTY_N3;
          runColor = dark;
          run = 1;
        }
      }
      result += finderPenaltyEnd(size, runColor, run, history) * PENALTY_N3;
    }
  }

  // Rule 2: every 2x2 block of one colour.
  for (let y = 0; y < size - 1; y++) {
    for (let x = 0; x < size - 1; x++) {
      const c = g.modules[y][x];
      if (c === g.modules[y][x + 1] && c === g.modules[y + 1][x] && c === g.modules[y + 1][x + 1]) result += PENALTY_N2;
    }
  }

  // Rule 4: how far the dark share strays from 50%, in 5% steps.
  let dark = 0;
  for (const row of g.modules) for (const c of row) if (c) dark++;
  const total = size * size;
  const k = Math.ceil(Math.abs(dark * 20 - total * 10) / total) - 1;
  return result + k * PENALTY_N4;
}

// ---------------------------------------------------------------- public API

/**
 * Encode `text` (UTF-8, byte mode, EC level M) as a module matrix: `m[y][x] === true`
 * means a dark module. No quiet zone is included — the renderer adds it.
 * Throws if the text needs more than version 10.
 */
export function qrMatrix(text: string): boolean[][] {
  const data = new TextEncoder().encode(text);
  const version = pickVersion(data.length);
  const g = newGrid(version);
  drawFunctionPatterns(g);
  drawCodewords(g, addEccAndInterleave(encodeData(data, version), version));

  // Mask selection: score all eight, lowest wins, ties to the lowest number. The format
  // bits are part of the scored image, so they are rewritten for each candidate.
  let best = 0, bestScore = Infinity;
  for (let mask = 0; mask < 8; mask++) {
    applyMask(g, mask);
    drawFormatBits(g, mask);
    const score = penaltyScore(g);
    if (score < bestScore) { bestScore = score; best = mask; }
    applyMask(g, mask);
  }
  applyMask(g, best);
  drawFormatBits(g, best);
  return g.modules;
}

// --- self-check: bun install/payload/meshd/qr.ts --check ---
//
// The decoder below is written against the standard rather than against the encoder
// above: it derives its own function-module map, reads the format information out of
// the drawn modules, un-masks, walks the zigzag, de-interleaves, and checks every
// Reed-Solomon block's syndromes before parsing the segment back to bytes. A layout or
// table mistake that both halves shared would show up as a nonzero syndrome, because
// the syndromes are algebra over the codewords and not a re-run of the encoder.
if (import.meta.main && process.argv.includes("--check")) {
  const fail = (msg: string) => { console.error(`FAIL: ${msg}`); process.exit(1); };
  const assert = (ok: boolean, msg: string) => { if (!ok) fail(msg); };

  // Field arithmetic first: everything below inherits from it, and a self-consistent
  // wrong field would still produce zero syndromes, so it needs known answers.
  // (x+1)(x^2+x+1) = x^3+1 = 9, and 128*2 = 29 only under 0x11D.
  assert(gfMul(3, 7) === 9, "gfMul(3,7) must be 9");
  assert(gfMul(128, 2) === 29, "gfMul(128,2) must be 29 (primitive polynomial 0x11D)");
  assert(gfMul(0, 200) === 0 && gfMul(1, 200) === 200, "gfMul identities");

  // Capacity tables against the published byte capacities for EC level M.
  const PUBLISHED_M_BYTES = [-1, 14, 26, 42, 62, 84, 106, 122, 152, 180, 213];
  for (let v = MIN_VERSION; v <= MAX_VERSION; v++) {
    assert(maxBytes(v) === PUBLISHED_M_BYTES[v], `version ${v} byte capacity is ${maxBytes(v)}, want ${PUBLISHED_M_BYTES[v]}`);
    assert(pickVersion(PUBLISHED_M_BYTES[v]) === v, `${PUBLISHED_M_BYTES[v]} bytes must select version ${v}`);
    if (v > MIN_VERSION) {
      assert(pickVersion(PUBLISHED_M_BYTES[v - 1] + 1) === v, `${PUBLISHED_M_BYTES[v - 1] + 1} bytes must roll up to version ${v}`);
    }
  }
  let threw = false;
  try { qrMatrix("x".repeat(PUBLISHED_M_BYTES[MAX_VERSION] + 1)); } catch { threw = true; }
  assert(threw, "one byte past the version 10 capacity must throw");

  // ---- decoder ----

  /** Function modules, derived from the geometry alone — deliberately not the encoder's map. */
  const functionMap = (size: number, version: number): boolean[][] => {
    const fn = Array.from({ length: size }, () => new Array<boolean>(size).fill(false));
    const mark = (x: number, y: number) => { if (x >= 0 && y >= 0 && x < size && y < size) fn[y][x] = true; };
    // Three reserved corners: 9x9 top-left (finder, separator, both halves of format
    // copy one), 8x9 top-right and 9x8 bottom-left (finder, separator, format copy two
    // plus the always-dark module).
    for (let y = 0; y <= 8; y++) for (let x = 0; x <= 8; x++) mark(x, y);
    for (let y = 0; y <= 8; y++) for (let x = size - 8; x < size; x++) mark(x, y);
    for (let y = size - 8; y < size; y++) for (let x = 0; x <= 8; x++) mark(x, y);
    for (let i = 0; i < size; i++) { mark(6, i); mark(i, 6); }  // timing
    const pos = alignPositions(version);
    for (let i = 0; i < pos.length; i++) {
      for (let j = 0; j < pos.length; j++) {
        const corner = (i === 0 && j === 0) || (i === 0 && j === pos.length - 1) || (i === pos.length - 1 && j === 0);
        if (corner) continue;
        for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) mark(pos[i] + dx, pos[j] + dy);
      }
    }
    if (version >= 7) {
      for (let i = 0; i < 18; i++) {
        const a = size - 11 + (i % 3), b = Math.floor(i / 3);
        mark(a, b); mark(b, a);
      }
    }
    return fn;
  };

  /** Read one 15-bit format copy, undo the 0x5412 XOR, and check the BCH remainder. */
  const readFormat = (m: boolean[][], cells: Array<[number, number]>): { ecl: number; mask: number } => {
    let bits = 0;
    cells.forEach(([x, y], i) => { if (m[y][x]) bits |= 1 << i; });
    const value = bits ^ 0x5412;
    let rem = value;
    for (let i = 14; i >= 10; i--) if ((rem >>> i) & 1) rem ^= 0x537 << (i - 10);
    assert(rem === 0, "format information fails its BCH(15,5) check");
    return { ecl: (value >>> 13) & 0b11, mask: (value >>> 10) & 0b111 };
  };

  /** Evaluate the block polynomial at a^0..a^(eccLen-1); a valid codeword is zero at all of them. */
  const syndromesZero = (block: number[], eccLen: number): boolean => {
    for (let i = 0; i < eccLen; i++) {
      const root = (() => { let r = 1; for (let k = 0; k < i; k++) r = gfMul(r, 2); return r; })();
      let acc = 0;
      for (const c of block) acc = gfMul(acc, root) ^ c;  // Horner, highest power first
      if (acc !== 0) return false;
    }
    return true;
  };

  const decode = (m: boolean[][], label: string): { bytes: Uint8Array; mask: number; version: number } => {
    const size = m.length;
    assert(m.every((row) => row.length === size), `${label}: matrix is not square`);
    assert((size - 17) % 4 === 0, `${label}: size ${size} is not a QR size`);
    const version = (size - 17) / 4;
    assert(version >= MIN_VERSION && version <= MAX_VERSION, `${label}: version ${version} out of range`);

    // (a) finder patterns and their separators, at three corners.
    const FINDER = [
      "1111111", "1000001", "1011101", "1011101", "1011101", "1000001", "1111111",
    ].map((r) => [...r].map((c) => c === "1"));
    for (const [ox, oy] of [[0, 0], [size - 7, 0], [0, size - 7]] as Array<[number, number]>) {
      for (let y = 0; y < 7; y++) {
        for (let x = 0; x < 7; x++) {
          assert(m[oy + y][ox + x] === FINDER[y][x], `${label}: finder at ${ox},${oy} wrong at ${x},${y}`);
        }
      }
      // Separator: the light ring on the inward sides of the 7x7 block.
      for (let i = -1; i <= 7; i++) {
        const sx = ox === 0 ? 7 : ox - 1;              // the column just inside the symbol
        const sy = oy === 0 ? 7 : oy - 1;
        const cy = oy + i, cx = ox + i;
        if (cy >= 0 && cy < size) assert(!m[cy][sx], `${label}: separator column of finder ${ox},${oy} is dark at y=${cy}`);
        if (cx >= 0 && cx < size) assert(!m[sy][cx], `${label}: separator row of finder ${ox},${oy} is dark at x=${cx}`);
      }
    }

    // (b) timing patterns alternate, dark on even coordinates, between the finders.
    for (let i = 8; i < size - 8; i++) {
      assert(m[6][i] === (i % 2 === 0), `${label}: horizontal timing wrong at x=${i}`);
      assert(m[i][6] === (i % 2 === 0), `${label}: vertical timing wrong at y=${i}`);
    }
    assert(m[size - 8][8], `${label}: the always-dark module is light`);

    // (c) format information: both copies, BCH-valid, level M, agreeing on the mask.
    const copy1: Array<[number, number]> = [];
    for (let i = 0; i <= 5; i++) copy1.push([8, i]);
    copy1.push([8, 7], [8, 8], [7, 8]);
    for (let i = 9; i < 15; i++) copy1.push([14 - i, 8]);
    const copy2: Array<[number, number]> = [];
    for (let i = 0; i < 8; i++) copy2.push([size - 1 - i, 8]);
    for (let i = 8; i < 15; i++) copy2.push([8, size - 15 + i]);
    const f1 = readFormat(m, copy1), f2 = readFormat(m, copy2);
    assert(f1.ecl === f2.ecl && f1.mask === f2.mask, `${label}: the two format copies disagree`);
    assert(f1.ecl === FORMAT_BITS_M, `${label}: format says EC level ${f1.ecl}, want M (${FORMAT_BITS_M})`);
    assert(f1.mask >= 0 && f1.mask <= 7, `${label}: mask ${f1.mask} out of range`);

    // (d) un-mask, walk the zigzag, de-interleave, verify syndromes, re-read the payload.
    const fn = functionMap(size, version);
    const un = m.map((row, y) => row.map((c, x) => (!fn[y][x] && maskAt(f1.mask, x, y) ? !c : c)));

    const bits: number[] = [];
    for (let right = size - 1; right >= 1; right -= 2) {
      if (right === 6) right = 5;
      for (let vert = 0; vert < size; vert++) {
        for (let j = 0; j < 2; j++) {
          const x = right - j;
          const y = ((right + 1) & 2) === 0 ? size - 1 - vert : vert;
          if (!fn[y][x]) bits.push(un[y][x] ? 1 : 0);
        }
      }
    }
    const rawCodewords = Math.floor(numRawDataModules(version) / 8);
    assert(Math.floor(bits.length / 8) === rawCodewords, `${label}: zigzag yielded ${bits.length} bits, want ${rawCodewords} codewords`);
    const raw: number[] = [];
    for (let i = 0; i + 8 <= rawCodewords * 8; i += 8) {
      let b = 0;
      for (let j = 0; j < 8; j++) b = (b << 1) | bits[i + j];
      raw.push(b);
    }

    const numBlocks = BLOCKS[version], eccLen = ECC_PER_BLOCK[version];
    const numShort = numBlocks - (rawCodewords % numBlocks);
    const shortLen = Math.floor(rawCodewords / numBlocks);
    const blocks: number[][] = Array.from({ length: numBlocks }, () => []);
    let idx = 0;
    for (let i = 0; i <= shortLen; i++) {
      for (let j = 0; j < numBlocks; j++) {
        if (i === shortLen - eccLen && j < numShort) continue;  // the skipped pad byte
        blocks[j].push(raw[idx++]);
      }
    }
    assert(idx === rawCodewords, `${label}: de-interleave consumed ${idx} of ${rawCodewords} codewords`);

    let payload: number[] = [];
    for (let j = 0; j < numBlocks; j++) {
      assert(syndromesZero(blocks[j], eccLen), `${label}: block ${j} has nonzero Reed-Solomon syndromes`);
      payload = payload.concat(blocks[j].slice(0, blocks[j].length - eccLen));
    }

    // Segment header, then the bytes.
    const ccBits = charCountBits(version);
    let bitPos = 0;
    const take = (n: number) => {
      let v = 0;
      for (let i = 0; i < n; i++, bitPos++) v = (v << 1) | ((payload[bitPos >> 3] >>> (7 - (bitPos & 7))) & 1);
      return v;
    };
    assert(take(4) === BYTE_MODE, `${label}: mode indicator is not byte mode`);
    const len = take(ccBits);
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) bytes[i] = take(8);
    return { bytes, mask: f1.mask, version };
  };

  // ---- payloads ----

  const long = "meshwatch://pair?h=100.64.1.2&p=8899&c=K7M4QP2X&n=" + "mac-studio-in-the-closet".repeat(5) + "&v=2";
  assert(long.length >= 170 && long.length <= 200, `long payload is ${long.length} chars, want ~180`);
  const payloads = [
    "OK",
    "meshwatch://pair?h=100.64.1.2&p=8899&c=K7M4QP2X",
    long,
    "café ☕ 日本語 — pairing",
  ];
  // One payload per version, so every row of the ECC tables is exercised.
  for (let v = MIN_VERSION; v <= MAX_VERSION; v++) payloads.push("A".repeat(PUBLISHED_M_BYTES[v]));

  for (const text of payloads) {
    const label = JSON.stringify(text.length > 40 ? text.slice(0, 37) + "..." : text);
    const m = qrMatrix(text);
    const got = decode(m, label);

    const want = new TextEncoder().encode(text);
    assert(got.bytes.length === want.length, `${label}: decoded ${got.bytes.length} bytes, want ${want.length}`);
    for (let i = 0; i < want.length; i++) {
      assert(got.bytes[i] === want[i], `${label}: byte ${i} decoded as ${got.bytes[i]}, want ${want[i]}`);
    }
    assert(new TextDecoder().decode(got.bytes) === text, `${label}: text does not round-trip`);
    assert(got.version === pickVersion(want.length), `${label}: matrix version ${got.version} is not the selected one`);

    // The mask written into the format information must also be the argmin of the
    // penalty score — otherwise a scanner reads the symbol fine and the mask rule is
    // silently doing nothing.
    const g: Grid = { version: got.version, size: m.length, modules: m.map((r) => r.slice()), fn: functionMap(m.length, got.version) };
    applyMask(g, got.mask);  // back to the unmasked image
    let bestMask = 0, bestScore = Infinity;
    for (let mask = 0; mask < 8; mask++) {
      applyMask(g, mask);
      drawFormatBits(g, mask);
      const score = penaltyScore(g);
      if (score < bestScore) { bestScore = score; bestMask = mask; }
      applyMask(g, mask);
    }
    assert(got.mask === bestMask, `${label}: mask ${got.mask} was used but mask ${bestMask} scores lower`);
  }

  console.log(`check-pair-qr: OK (${payloads.length} payloads round-tripped through an independent decoder)`);
}
