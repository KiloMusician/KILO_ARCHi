# ARCHi native desktop

Build the complete app from the repository root:

```sh
npm ci
./script/build_and_run.sh --verify --review
```

For package-only checks: `swift build --package-path desktop` and `swift test --package-path desktop`. Package-only execution lacks the bundled Habitat assets; use the full build script for the complete experience. Quit Development Review normally before replacing its generated bundle.

See [the root guide](../README.md) for model setup and persistence, [architecture](../docs/ARCHITECTURE.md) for component ownership, and [Alpha validation](../docs/ALPHA_VALIDATION.md) for actual evidence and limits.
