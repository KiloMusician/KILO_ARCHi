function decodedCodePoint(value, radix) {
  const codePoint = Number.parseInt(value, radix);
  return Number.isInteger(codePoint) && codePoint >= 0 && codePoint <= 0x10ffff
    ? String.fromCodePoint(codePoint)
    : "";
}

export function normalizeBoundaryText(value) {
  let normalized = String(value).toLowerCase();

  for (let pass = 0; pass < 4; pass += 1) {
    const decoded = normalized
      .replace(/%([0-9a-f]{2})/gi, (_, value) => decodedCodePoint(value, 16))
      .replace(/&#x([0-9a-f]+);?/gi, (_, value) => decodedCodePoint(value, 16))
      .replace(/&#([0-9]+);?/g, (_, value) => decodedCodePoint(value, 10))
      .replace(/\\x([0-9a-f]{2})/gi, (_, value) => decodedCodePoint(value, 16))
      .replace(/\\u\{([0-9a-f]{1,6})\}/gi, (_, value) => decodedCodePoint(value, 16))
      .replace(/\\u([0-9a-f]{4})/gi, (_, value) => decodedCodePoint(value, 16))
      .replaceAll("\\", "/");
    if (decoded === normalized) break;
    normalized = decoded;
  }

  return normalized;
}
