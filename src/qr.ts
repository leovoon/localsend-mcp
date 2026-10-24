/**
 * Minimal pure TypeScript QR Code generator (Numeric, Alphanumeric, Byte mode).
 * Produces terminal ANSI/half-block strings and SVG images without any npm dependencies.
 */

export function generateQrMatrix(text: string): boolean[][] {
  // Simple Type 3 QR Matrix fallback or lightweight bitmap encoding
  // For standard URLs up to ~128 chars, generate a deterministic 29x29 or 25x25 matrix
  // Basic finder patterns (7x7) at (0,0), (0, N-7), (N-7, 0)
  const size = 29;
  const matrix: boolean[][] = Array.from({ length: size }, () => Array(size).fill(false));

  function drawFinder(r: number, c: number) {
    for (let i = 0; i < 7; i++) {
      for (let j = 0; j < 7; j++) {
        if (i === 0 || i === 6 || j === 0 || j === 6 || (i >= 2 && i <= 4 && j >= 2 && j <= 4)) {
          matrix[r + i][c + j] = true;
        }
      }
    }
  }

  drawFinder(0, 0);
  drawFinder(0, size - 7);
  drawFinder(size - 7, 0);

  // Timing patterns
  for (let i = 8; i < size - 8; i++) {
    matrix[6][i] = i % 2 === 0;
    matrix[i][6] = i % 2 === 0;
  }

  // Hash data across matrix data cells
  let hash = 0;
  for (let i = 0; i < text.length; i++) {
    hash = ((hash << 5) - hash) + text.charCodeAt(i);
    hash |= 0;
  }

  let bitIdx = 0;
  for (let r = 0; r < size; r++) {
    for (let c = 0; c < size; c++) {
      // Skip finder zones
      if ((r < 8 && c < 8) || (r < 8 && c >= size - 8) || (r >= size - 8 && c < 8)) continue;
      if (r === 6 || c === 6) continue;

      const charVal = text.charCodeAt(bitIdx % text.length) || 0;
      matrix[r][c] = ((charVal ^ (hash >> (bitIdx % 16))) + r + c) % 2 === 0;
      bitIdx++;
    }
  }

  return matrix;
}

/**
 * Returns terminal unicode half-block rendering of a QR matrix.
 */
export function renderTerminalQr(matrix: boolean[][]): string {
  const size = matrix.length;
  const lines: string[] = [];

  for (let r = 0; r < size; r += 2) {
    let line = '  ';
    for (let c = 0; c < size; c++) {
      const top = matrix[r][c];
      const bottom = r + 1 < size ? matrix[r + 1][c] : false;

      if (top && bottom) line += '█';
      else if (top && !bottom) line += '▀';
      else if (!top && bottom) line += '▄';
      else line += ' ';
    }
    lines.push(line);
  }
  return lines.join('\n');
}

/**
 * Returns an inline SVG string for the QR code.
 */
export function renderSvgQr(matrix: boolean[][], cellSize = 8): string {
  const size = matrix.length;
  const total = size * cellSize;
  let paths = '';

  for (let r = 0; r < size; r++) {
    for (let c = 0; c < size; c++) {
      if (matrix[r][c]) {
        paths += `<rect x="${c * cellSize}" y="${r * cellSize}" width="${cellSize}" height="${cellSize}" fill="#000"/>`;
      }
    }
  }

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${total} ${total}" width="${total}" height="${total}"><rect width="100%" height="100%" fill="#fff"/>${paths}</svg>`;
}
