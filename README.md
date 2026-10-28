# Lychrel

Searches a range of numbers for Lychrel candidates using the reverse-and-add process: reverse a number's digits, add the result to the original, and repeat until you hit a palindrome. Numbers that don't reach one within a set number of steps are flagged as likely Lychrel numbers (196 is the famous smallest candidate).

Arithmetic is arbitrary-precision, so values can grow as large as they need to. By default numbers are held as packed BCD and each reverse-and-add step is vectorized with SIMD (see [Algorithms](#algorithms)). The range is checked in parallel across all CPU cores.

## Targets

- **lychrel**: command-line tool (`crunch/`)
- **LychrelGUI**: SwiftUI macOS app (`LychrelGUI/`)

Both link the shared core logic from **LychrelKit** (`LychrelKit/`), a local Swift package. Its `Package.swift` builds the core optimized even in Debug, since the SIMD code is several times slower unoptimized.

## Command-line usage

```
lychrel [-lower N] [-bound N] [-max N] [-algo NAME] [-csv PATH]
```

| Flag | Default | Meaning |
|---|---|---|
| `-lower` | `1` | First number to check |
| `-bound` | `1000000` | Last number to check |
| `-max` | `1000` | Reverse-and-add steps before giving up on a number |
| `-algo` | `packedBCD` | Algorithm: `packedBCD` or `digitArray` (see [Algorithms](#algorithms)) |
| `-csv` | `results.csv` | Output file |

It shows a live progress bar while running, then prints a summary (palindromes found, Lychrel candidates, and calc/sort/write timings).

## GUI

Set the bounds, max iterations, algorithm and CSV path, then press Start. The window shows live progress and a running count of Lychrel candidates, and finishes with a summary and a Reveal in Finder button. Cancel stops a run early and writes no CSV.

- The Algorithm radio buttons choose between Packed BCD and Digit array. The summary shows which one ran, so comparing the calc-phase times shows the difference.
- "Use commas" displays the number fields with thousands separators.
- Settings are remembered between launches.

## Algorithms

Two implementations of the reverse-and-add loop are available. They produce identical results, and the CSV is byte-for-byte the same.

- **Packed BCD** (default): the number is stored as `UInt64` words of 16 decimal digits each, one digit per nibble. Reversing a word is a byte swap plus a nibble swap, and addition is a short run of integer ops that adds all 16 digits at once and fixes up the decimal carries. Reverse, palindrome check and add are fused into a single pass over `SIMD2<UInt64>` word pairs, so each NEON operation handles 32 digits. Numbers of up to 6 words (96 digits) use a scalar version of the same step, because the vector pass has a fixed latency that doesn't pay off at that size. The pass assumes each word's carry-in from the word below and redoes the step with a scalar add on the rare all-9s case where that is wrong. Buffers are allocated once per number, with no per-step allocation.
- **Digit array**: the original implementation, one decimal digit per byte, added in base-10000 chunks. It is kept as a simple reference to check the BCD path against.

Checking 1 to 1,000,000 with `-max 1000` on Apple Silicon takes roughly 0.25 s with Packed BCD and around 4 s with the digit array. On an M4 Max the SIMD pass cut that run from about 303 ms to 227 ms compared with the earlier scalar BCD loop; gains vary by chip. The 6-word scalar threshold and the other SIMD tuning were measured on that M4 Max and may not be optimal elsewhere.

### Build settings that matter

SwiftPM builds packages with `-Onone` in Debug, and unoptimized SIMD code is several times slower than even the scalar version, because every vector operation becomes a generic function call. So `LychrelKit/Package.swift` adds `-O` for Debug, and the GUI runs the fast core from Xcode's ⌘R. It also passes `-Xllvm -align-loops=64`: identical machine code was running the SIMD loop 25 to 30% slower depending on where the loop landed in memory, and 64-byte loop alignment removes that slow mode.

## CSV output

One row per number checked:

```
number,palindrome,steps,overflowed,exceeded_maxiter
```

- `palindrome`: the palindrome reached, blank if none was found
- `steps`: reverse-and-add iterations performed
- `overflowed`: always `0` now that arithmetic is arbitrary-precision (kept for schema compatibility)
- `exceeded_maxiter`: `1` if the number hit the `-max` limit

## Building

Open `Lychrel.xcodeproj` in Xcode and build either scheme (Release for the CLI, LychrelGUI for the app). Requires macOS 26.3 or later.

## Credits

The vectorized packed BCD step (including the build-setting findings above) and the move of the shared core into the LychrelKit package were contributed by [TioHerko](https://github.com/TioHerko) in pull requests [#1](https://github.com/peterw5000/Lychrel/pull/1) and [#2](https://github.com/peterw5000/Lychrel/pull/2).

## Licence

MIT. See [LICENSE](LICENSE).
