export function parseJsonWithoutDuplicateKeys(source: string, label = "JSON"): unknown {
  let index = 0;

  function fail(message: string): never {
    throw new SyntaxError(`${label}: ${message} at UTF-16 offset ${index}`);
  }

  function skipWhitespace(): void {
    while (/[\t\n\r ]/.test(source[index] ?? "")) index += 1;
  }

  function scanString(): string {
    if (source[index] !== '"') fail("expected string");
    const start = index;
    index += 1;
    while (index < source.length) {
      const character = source[index];
      if (character === '"') {
        index += 1;
        return JSON.parse(source.slice(start, index)) as string;
      }
      if (character === "\\") {
        index += 1;
        const escaped = source[index];
        if (escaped === "u") {
          const codePoint = source.slice(index + 1, index + 5);
          if (!/^[a-fA-F0-9]{4}$/.test(codePoint)) fail("invalid Unicode escape");
          index += 5;
          continue;
        }
        if (!/["\\/bfnrt]/.test(escaped ?? "")) fail("invalid string escape");
        index += 1;
        continue;
      }
      if (character.charCodeAt(0) < 0x20) fail("unescaped control character");
      index += 1;
    }
    return fail("unterminated string");
  }

  function scanArray(): void {
    index += 1;
    skipWhitespace();
    if (source[index] === "]") {
      index += 1;
      return;
    }
    while (index < source.length) {
      scanValue();
      skipWhitespace();
      if (source[index] === "]") {
        index += 1;
        return;
      }
      if (source[index] !== ",") fail("expected comma or array end");
      index += 1;
      skipWhitespace();
    }
    fail("unterminated array");
  }

  function scanObject(): void {
    index += 1;
    const keys = new Set<string>();
    skipWhitespace();
    if (source[index] === "}") {
      index += 1;
      return;
    }
    while (index < source.length) {
      const key = scanString();
      if (keys.has(key)) fail(`duplicate JSON key ${JSON.stringify(key)}`);
      keys.add(key);
      skipWhitespace();
      if (source[index] !== ":") fail("expected colon");
      index += 1;
      scanValue();
      skipWhitespace();
      if (source[index] === "}") {
        index += 1;
        return;
      }
      if (source[index] !== ",") fail("expected comma or object end");
      index += 1;
      skipWhitespace();
    }
    fail("unterminated object");
  }

  function scanValue(): void {
    skipWhitespace();
    if (source[index] === "{") return scanObject();
    if (source[index] === "[") return scanArray();
    if (source[index] === '"') {
      scanString();
      return;
    }
    for (const literal of ["true", "false", "null"]) {
      if (source.startsWith(literal, index)) {
        index += literal.length;
        return;
      }
    }
    const number = source.slice(index).match(/^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/);
    if (number) {
      index += number[0].length;
      return;
    }
    fail("invalid JSON value");
  }

  scanValue();
  skipWhitespace();
  if (index !== source.length) fail("unexpected trailing content");
  return JSON.parse(source) as unknown;
}
