# Pyrethrum

**Multi-language static analyzer for exhaustive exception handling.**

Pyrethrum verifies that all declared exceptions are properly handled in your code. It analyzes JSON input from language-specific tools (like [Pyrethrin](https://github.com/yourusername/pyrethrin) for Python) and catches missing exception handlers before runtime.

---

## Table of Contents

- [Overview](#overview)
- [Supported Languages](#supported-languages)
- [Installation](#installation)
- [Usage](#usage)
- [Input Format](#input-format)
- [Output Format](#output-format)
- [Error Codes](#error-codes)
- [Development](#development)
- [License](#license)

---

## Overview

Pyrethrum is the core static analyzer that powers exhaustive exception handling across multiple languages. It receives a JSON representation of:

- **Function signatures** - What exceptions each function declares
- **Match expressions** - How callers handle those exceptions
- **Unhandled calls** - Calls to functions that return Result/Option without handling

It then verifies exhaustiveness and reports any missing handlers.

---

## Supported Languages

| Language | Library | Status |
|----------|---------|--------|
| Python | [Pyrethrin](https://github.com/yourusername/pyrethrin) | Available |
| TypeScript | - | Planned |
| Go | - | Planned |
| Java | - | Planned |

---

## Installation

### From Binary

Pyrethrum is bundled with language-specific libraries. Install the library for your language (e.g., Pyrethrin for Python) to get both the runtime and the analyzer.

### From Source

**Prerequisites:**
- OCaml 5.2+ (5.1+ works; avoid 5.4 on ARM64 due to assembler bug)
- opam 2.0+
- dune 3.0+

**Build:**

```bash
# Create OCaml switch
opam switch create pyrethrum 5.2.1
eval $(opam env)

# Install dependencies
opam install dune yojson ppx_deriving cmdliner fmt alcotest

# Build
dune build

# Run tests
dune runtest

# Install locally
dune install
```

---

## Usage

### Basic Commands

```bash
# Analyze from file
pyrethrum check input.json

# Analyze from stdin
cat input.json | pyrethrum check --stdin

# JSON output format
pyrethrum check --format=json input.json

# Strict mode (warnings become errors)
pyrethrum check --strict input.json
```

### Integration with Language Tools

Pyrethrum receives JSON from language-specific AST extractors:

```bash
# Python (via Pyrethrin) - automatic invocation at runtime
# Or manually:
python -c "from pyrethrin._ast_dump import dump_file_json; print(dump_file_json('file.py'))" \
  | pyrethrum check --stdin
```

---

## Input Format

Pyrethrum accepts JSON with three main sections:

```json
{
  "language": "python",
  "signatures": [...],
  "matches": [...],
  "unhandled_calls": [...]
}
```

### Signatures

Function declarations with their exceptions:

```json
{
  "name": "get_user",
  "qualified_name": "UserService.get_user",
  "declared_exceptions": [
    {"kind": "name", "name": "UserNotFound"},
    {"kind": "qualified", "module": "errors", "name": "InvalidId"}
  ],
  "loc": {"file": "service.py", "line": 10, "col": 4, "end_line": 20, "end_col": 0},
  "is_async": false,
  "signature_type": "raises"
}
```

### Matches

How callers handle the exceptions:

```json
{
  "func_name": "get_user",
  "handlers": [
    {"kind": "name", "name": "UserNotFound"},
    {"kind": "name", "name": "InvalidId"}
  ],
  "has_ok_handler": true,
  "has_some_handler": false,
  "has_nothing_handler": false,
  "loc": {"file": "handler.py", "line": 30, "col": 0, "end_line": 40, "end_col": 0},
  "kind": "statement"
}
```

### Unhandled Calls

Calls that don't use match:

```json
{
  "func_name": "risky_function",
  "loc": {"file": "handler.py", "line": 50, "col": 4, "end_line": 50, "end_col": 25},
  "signature_type": "raises"
}
```

### Reference Tables

**Signature Types:**

| Type | Description |
|------|-------------|
| `raises` | Returns Result type (Ok/Err with exceptions) |
| `option` | Returns Option type (Some/Nothing) |

**Exception Kinds:**

| Kind | Description | Example |
|------|-------------|---------|
| `name` | Simple name | `{"kind": "name", "name": "ValueError"}` |
| `qualified` | Module-qualified | `{"kind": "qualified", "module": "errors", "name": "NotFound"}` |
| `union` | Union of types | `{"kind": "union", "types": [...]}` |
| `ok` | Success case | `{"kind": "ok"}` |
| `some` | Some case | `{"kind": "some"}` |
| `nothing` | Nothing case | `{"kind": "nothing"}` |

**Match Kinds:**

| Kind | Description |
|------|-------------|
| `statement` | Pattern match statement (`match result:`) |
| `function_call` | Match function call (`match(fn)({...})`) |

---

## Output Format

### Text (default)

```
service.py:30:0: error [EXH001]: Non-exhaustive match on `get_user`: missing InvalidId
handler.py:50:4: error [EXH007]: Result from `risky_function` must be handled with match
```

### JSON

```json
{
  "diagnostics": [
    {
      "file": "service.py",
      "line": 30,
      "column": 0,
      "endLine": 40,
      "endColumn": 0,
      "severity": "error",
      "code": "EXH001",
      "message": "Non-exhaustive match on `get_user`: missing InvalidId",
      "suggestions": [{"action": "add_handler", "exception": "InvalidId"}]
    }
  ]
}
```

---

## Error Codes

| Code | Severity | Description |
|------|----------|-------------|
| EXH001 | Error | Missing handlers for declared exceptions |
| EXH002 | Warning | Handlers for undeclared exceptions |
| EXH003 | Error | Missing Ok handler |
| EXH004 | Warning | Unknown function (no signature found) |
| EXH005 | Error | Missing Some handler (Option) |
| EXH006 | Error | Missing Nothing handler (Option) |
| EXH007 | Error | Result not handled with match |
| EXH008 | Error | Option not handled with match |

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | No errors (or only warnings in non-strict mode) |
| 1 | Exhaustiveness errors found |
| 2 | Invalid arguments or parse error |

---

## Exhaustiveness Rules

### Result Type (`signature_type: "raises"`)

- **Required:** `has_ok_handler: true`
- **Required:** Handler for every declared exception
- **Warning:** Handlers for undeclared exceptions

### Option Type (`signature_type: "option"`)

- **Required:** `has_some_handler: true`
- **Required:** `has_nothing_handler: true`
- **Forbidden:** Exception handlers (Options don't have exceptions)

### Unhandled Calls

Any call in `unhandled_calls` generates an error:
- `signature_type: "raises"` generates EXH007
- `signature_type: "option"` generates EXH008

---

## Multi-Language Support

Pyrethrum uses the `language` field for language-appropriate error messages:

| Language | Decorator Syntax | Match Syntax |
|----------|------------------|--------------|
| Python | `@raises(...)` | `match` / `match()` |
| TypeScript | `raises(...)` | `match()` |
| Java | `@Raises(...)` | `Match.on()` |
| Go | `raises(...)` | `Match()` |

---

## Development

### Project Structure

```
pyrethrum/
├── bin/
│   └── main.ml           # CLI entry point
├── lib/
│   ├── ast.ml            # Core types
│   ├── parse.ml          # JSON parsing
│   ├── exhaustiveness.ml # Analysis algorithm
│   ├── diagnostics.ml    # Error formatting
│   └── config.ml         # Configuration
├── test/
│   └── test_pyrethrum.ml # Unit tests
├── dune-project
└── pyrethrum.opam
```

### Running Tests

```bash
dune runtest

# Verbose output
dune runtest --force
```

### Building for Release

```bash
dune build --release
# Binary at _build/default/bin/main.exe
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Language Tooling                         │
├─────────────────────┬───────────────────┬───────────────────┤
│      Pyrethrin      │   TypeScript SDK  │      Go SDK       │
│      (Python)       │    (planned)      │    (planned)      │
├─────────────────────┴───────────────────┴───────────────────┤
│                      JSON Format                            │
│    {signatures: [...], matches: [...], unhandled_calls: []} │
├─────────────────────────────────────────────────────────────┤
│                       Pyrethrum                             │
│              (OCaml Static Analyzer)                        │
├─────────────────────────────────────────────────────────────┤
│  Parse  │  Exhaustiveness  │  Diagnostics  │   Output      │
│  JSON   │     Check        │   Generation  │   Formatter   │
└─────────────────────────────────────────────────────────────┘
```

---

## License

MIT
