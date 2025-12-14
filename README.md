# Pyrethrum - Static Exhaustiveness Analyzer

Pyrethrum is an OCaml-based static analyzer that verifies exhaustive handling of Result and Option types across multiple programming languages. It receives JSON input describing function signatures and match statements, then checks that all possible cases are handled.

## Table of Contents

1. [Overview](#overview)
2. [Installation & Usage](#installation--usage)
3. [JSON Input Format](#json-input-format)
4. [Error Codes](#error-codes)
5. [Exhaustiveness Checking Logic](#exhaustiveness-checking-logic)
6. [Module Architecture](#module-architecture)
7. [Language Support](#language-support)
8. [Output Formats](#output-formats)

---

## Overview

Pyrethrum enforces a critical safety property: **every function that can fail must have all its failure cases explicitly handled**. This applies to:

1. **Result types** (functions decorated with `@raises`) - Must handle `Ok` plus all declared exceptions
2. **Option types** (functions decorated with `@returns_option`) - Must handle both `Some` and `Nothing`

### Design Philosophy

- **Exhaustive by default**: You cannot ignore error cases
- **Static analysis**: Errors caught before runtime
- **Language agnostic**: Core algorithm works across Python, TypeScript, Go, Java, PHP
- **Clear diagnostics**: Actionable error messages with fix suggestions

---

## Installation & Usage

### Building from Source

```bash
cd Pyrethrum
opam install . --deps-only
dune build
```

### CLI Usage

```bash
# Check a JSON file
./pyrethrum check input.json

# Read from stdin
cat input.json | ./pyrethrum check --stdin

# JSON output format
./pyrethrum check --format json input.json

# Strict mode (warnings become errors)
./pyrethrum check --strict input.json
```

### Options

| Option | Description |
|--------|-------------|
| `--stdin` | Read JSON from standard input |
| `--format FORMAT` | Output format: `text` (default) or `json` |
| `--strict` | Treat warnings as errors |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | No errors (warnings OK unless `--strict`) |
| 1 | Exhaustiveness errors found |
| 2 | Invalid arguments or parse error |

---

## JSON Input Format

Pyrethrum supports two input formats:

1. **Raw AST Format** (recommended) - Language-specific AST JSON, parsed by plugins
2. **Processed Format** - Pre-extracted signatures and matches

### Raw AST Format (Python)

The preferred format passes the raw Python AST to Pyrethrum, letting OCaml handle all parsing:

```json
{
  "language": "python",
  "source_file": "path/to/file.py",
  "ast": {
    "_type": "Module",
    "body": [
      {
        "_type": "FunctionDef",
        "name": "get_user",
        "decorator_list": [...],
        "body": [...],
        "lineno": 10,
        "col_offset": 0,
        "end_lineno": 25,
        "end_col_offset": 0
      }
    ]
  }
}
```

The Python plugin (`python_plugin.ml`) detects this format when:
- The JSON has an `ast` field
- No `signatures` field is present
- Language is "python" or unspecified

### Processed Format (Legacy)

The processed format pre-extracts signatures and matches:

### Complete Schema

```json
{
  "language": "python",
  "signatures": [
    {
      "name": "get_user",
      "qualified_name": "UserService.get_user",
      "declared_exceptions": [
        {"kind": "name", "name": "UserNotFound"},
        {"kind": "name", "name": "DatabaseError"}
      ],
      "loc": {
        "file": "service.py",
        "line": 10,
        "col": 0,
        "end_line": 25,
        "end_col": 0
      },
      "is_async": false,
      "signature_type": "raises"
    }
  ],
  "matches": [
    {
      "func_name": "get_user",
      "handlers": [
        {"kind": "name", "name": "UserNotFound"},
        {"kind": "name", "name": "DatabaseError"}
      ],
      "has_ok_handler": true,
      "has_some_handler": false,
      "has_nothing_handler": false,
      "loc": {
        "file": "service.py",
        "line": 30,
        "col": 4,
        "end_line": 45,
        "end_col": 0
      },
      "kind": "statement"
    }
  ],
  "unhandled_calls": [
    {
      "func_name": "risky_operation",
      "loc": {
        "file": "service.py",
        "line": 50,
        "col": 8,
        "end_line": 50,
        "end_col": 30
      },
      "signature_type": "raises"
    }
  ]
}
```

### Field Reference

#### Top Level

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `language` | string | No | Programming language (default: "Unknown") |
| `signatures` | array | Yes | Function declarations with exception metadata |
| `matches` | array | Yes | Match expressions handling function results |
| `unhandled_calls` | array | No | Function calls not wrapped in match |

#### Signature Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Function name |
| `qualified_name` | string | No | Full path (e.g., `Module.Class.method`) |
| `declared_exceptions` | array | Yes | Exception types this function can raise |
| `loc` | object | Yes | Source location |
| `is_async` | boolean | Yes | Whether function is async |
| `signature_type` | string | No | `"raises"` (default) or `"option"` |

#### Exception Type Object

Four variants are supported:

```json
// Simple name
{"kind": "name", "name": "ValueError"}

// Module-qualified name
{"kind": "qualified", "module": "errors", "name": "CustomError"}

// Union of types
{"kind": "union", "types": [
  {"kind": "name", "name": "ValueError"},
  {"kind": "name", "name": "KeyError"}
]}

// Special types for Result/Option
{"kind": "ok"}       // Success case
{"kind": "some"}     // Some(value) case
{"kind": "nothing"}  // Nothing/None case
```

#### Match Call Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `func_name` | string | Yes | Function being matched |
| `handlers` | array | Yes | Exception handlers provided |
| `has_ok_handler` | boolean | Yes | True if Ok case handled |
| `has_some_handler` | boolean | No | True if Some case handled |
| `has_nothing_handler` | boolean | No | True if Nothing case handled |
| `loc` | object | Yes | Source location |
| `kind` | string | Yes | `"statement"` or `"function_call"` |

#### Location Object

| Field | Type | Description |
|-------|------|-------------|
| `file` | string | Source file path |
| `line` | int | Starting line (1-indexed) |
| `col` | int | Starting column (0-indexed) |
| `end_line` | int | Ending line |
| `end_col` | int | Ending column |

---

## Error Codes

### EXH001 - Missing Exception Handlers

**Severity**: Error

**Condition**: A match statement is missing handlers for one or more declared exceptions.

**Example**:
```python
@raises(ValueError, KeyError, TypeError)
def parse_config(data):
    ...

# ERROR: Missing KeyError, TypeError handlers
match parse_config(data):
    case Ok(config): use(config)
    case Err(ValueError() as e): handle(e)
    # Missing: KeyError, TypeError
```

**Message**: `Non-exhaustive match on 'parse_config': missing KeyError, TypeError`

---

### EXH002 - Extra Handlers (Warning)

**Severity**: Warning

**Condition**: A match statement has handlers for exceptions not declared in `@raises`.

**Example**:
```python
@raises(ValueError)
def validate(x):
    ...

# WARNING: RuntimeError not declared
match validate(x):
    case Ok(v): use(v)
    case Err(ValueError() as e): handle(e)
    case Err(RuntimeError() as e): handle(e)  # Extra!
```

**Message**: `Match on 'validate' has handlers for undeclared exceptions: RuntimeError`

---

### EXH003 - Missing Ok Handler

**Severity**: Error

**Condition**: A Result match is missing the Ok/success case handler.

**Example**:
```python
@raises(NetworkError)
def fetch_data(url):
    ...

# ERROR: No Ok handler
match fetch_data(url):
    case Err(NetworkError() as e): retry()
    # Missing: case Ok(data)
```

**Message**: `Match on 'fetch_data' is missing handler for Ok case`

---

### EXH004 - Unknown Function (Warning)

**Severity**: Warning

**Condition**: `match()` called on a function with no `@raises` signature found.

**Example**:
```python
def undecorated_function():
    return 42

# WARNING: No signature found
match(undecorated_function, )({...})
```

**Message**: `match() called on 'undecorated_function' which has no @raises signature`

---

### EXH005 - Missing Some Handler

**Severity**: Error

**Condition**: An Option match is missing the Some case handler.

**Example**:
```python
@returns_option
def find_user(user_id):
    ...

# ERROR: No Some handler
match find_user("123"):
    case Nothing(): return None
    # Missing: case Some(user)
```

**Message**: `Match on 'find_user' is missing handler for Some case`

---

### EXH006 - Missing Nothing Handler

**Severity**: Error

**Condition**: An Option match is missing the Nothing case handler.

**Example**:
```python
@returns_option
def find_user(user_id):
    ...

# ERROR: No Nothing handler
match find_user("123"):
    case Some(user): return user
    # Missing: case Nothing()
```

**Message**: `Match on 'find_user' is missing handler for Nothing case`

---

### EXH007 - Unhandled Result

**Severity**: Error

**Condition**: A function returning Result is called but the result is not handled with match.

**Example**:
```python
@raises(IOError)
def read_file(path):
    ...

def process():
    data = read_file("config.txt")  # ERROR: Result not matched!
    print(data)  # This is wrong - data is Result, not the actual value
```

**Message**: `Result from 'read_file' must be handled with match or match-case`

---

### EXH008 - Unhandled Option

**Severity**: Error

**Condition**: A function returning Option is called but the result is not handled with match.

**Example**:
```python
@returns_option
def find_user(user_id):
    ...

def greet():
    user = find_user("123")  # ERROR: Option not matched!
    print(f"Hello {user.name}")  # This could crash if Nothing
```

**Message**: `Option from 'find_user' must be handled with match or match-case`

---

## Exhaustiveness Checking Logic

### For Result Types (`signature_type: "raises"`)

The algorithm ensures all possible outcomes are handled:

```
Required handlers = declared_exceptions + {Ok}
Provided handlers = handlers + {Ok if has_ok_handler}

missing = Required - Provided  → EXH001 (or EXH003 if Ok missing)
extra = Provided - Required    → EXH002 (warning)
```

**Validation Rules**:
1. `has_ok_handler` MUST be `true` → else EXH003
2. Every exception in `declared_exceptions` MUST have a handler → else EXH001
3. No handlers for undeclared exceptions → else EXH002 (warning)

### For Option Types (`signature_type: "option"`)

Simpler checking - only two cases exist:

```
Required = {Some, Nothing}
```

**Validation Rules**:
1. `has_some_handler` MUST be `true` → else EXH005
2. `has_nothing_handler` MUST be `true` → else EXH006
3. `handlers` array MUST be empty → else EXH002 (Options don't have exceptions)

### For Unhandled Calls

Any function call in `unhandled_calls` generates an error:
- If `signature_type: "raises"` → EXH007
- If `signature_type: "option"` → EXH008

---

## Module Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        main.ml                              │
│                    (CLI Interface)                          │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      plugin.ml                              │
│              (Plugin System & Input Router)                 │
│                                                             │
│  • LANGUAGE_PLUGIN module type                              │
│  • register_plugin / find_plugin                            │
│  • parse_input (routes to plugin or parse.ml)               │
└─────────────────────────────────────────────────────────────┘
              │                              │
              │ (raw AST)                    │ (processed JSON)
              ▼                              ▼
┌──────────────────────────┐   ┌─────────────────────────────┐
│   python_plugin.ml       │   │        parse.ml             │
│   (Python AST Parser)    │   │   (Processed JSON Parser)   │
│                          │   │                             │
│  • python_ast.ml         │   │  • parse_analysis_input     │
│  • python_parse.ml       │   │  • parse_func_signature     │
│  • python_extract.ml     │   │  • parse_match_call         │
└──────────────────────────┘   └─────────────────────────────┘
              │                              │
              └──────────────┬───────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                        ast.ml                               │
│                  (Core Data Types)                          │
│                                                             │
│  • language, loc, exc_type                                  │
│  • func_signature, match_call                               │
│  • unhandled_call, analysis_input                           │
│  • signature_type (SigRaises | SigOption)                   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                   exhaustiveness.ml                         │
│               (Core Analysis Algorithm)                     │
│                                                             │
│  • check_raises_signature - Result type checking            │
│  • check_option_signature - Option type checking            │
│  • check_all_with_unhandled - Full analysis                 │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    diagnostics.ml                           │
│              (Error Formatting & Output)                    │
│                                                             │
│  • error_to_diagnostic - Convert to diagnostic              │
│  • diagnostics_to_json - JSON output                        │
│  • diagnostics_to_string - Text output                      │
└─────────────────────────────────────────────────────────────┘
```

### Module Descriptions

| Module | Purpose |
|--------|---------|
| `ast.ml` | Core type definitions for the entire system |
| `parse.ml` | JSON parsing for processed format |
| `plugin.ml` | Plugin system for language-specific AST parsing |
| `python_plugin.ml` | Python language plugin (AST → analysis_input) |
| `python_ast.ml` | Python AST type definitions in OCaml |
| `python_parse.ml` | Python AST JSON parser |
| `python_extract.ml` | Extracts signatures/matches from Python AST |
| `exhaustiveness.ml` | The actual exhaustiveness checking algorithm |
| `diagnostics.ml` | Error code mapping and message formatting |
| `config.ml` | Configuration management |
| `pyrethrum.ml` | Public API that re-exports all modules |
| `main.ml` | CLI interface using cmdliner |

### Plugin Architecture

Pyrethrum uses a plugin-based architecture for language support. Each language plugin:

1. **Registers itself** at startup via `Plugin.register_plugin`
2. **Detects its input** via `can_handle` function
3. **Parses raw AST** from the language's tooling
4. **Extracts** function signatures, match statements, and unhandled calls
5. **Returns** the standard `analysis_input` type for exhaustiveness checking

This design allows:
- Heavy lifting (AST parsing) done in OCaml with pattern matching
- Language-agnostic core analysis
- Easy addition of new languages as plugins

---

## Language Support

Pyrethrum adapts its messages based on the `language` field:

### Decorator Syntax by Language

| Language | Decorator Syntax |
|----------|------------------|
| Python | `@raises(ValueError, KeyError)` |
| TypeScript | `raises(ValueError, KeyError)` |
| JavaScript | `raises(ValueError, KeyError)` |
| Go | `raises(ValueError, KeyError)` |
| Java | `@Raises(ValueError.class)` |
| PHP | `#[Raises(ValueError)]` |

### Match Syntax by Language

| Language | Match Syntax |
|----------|--------------|
| Python | `match result:` or `match(func, args)({...})` |
| TypeScript | `match(fn)({...})` |
| JavaScript | `match(fn)({...})` |
| Go | `Match(fn)` |
| Java | `Match.on(result)` |
| PHP | `match_result($fn)` |

---

## Output Formats

### Text Format (Default)

```
file:line:column: severity [CODE]: message
```

Example:
```
service.py:30:4: error [EXH001]: Non-exhaustive match on `get_user`: missing DatabaseError
service.py:45:8: warning [EXH002]: Match on `validate` has handlers for undeclared exceptions: RuntimeError
```

### JSON Format

```json
{
  "diagnostics": [
    {
      "file": "service.py",
      "line": 30,
      "column": 4,
      "endLine": 45,
      "endColumn": 0,
      "severity": "error",
      "code": "EXH001",
      "message": "Non-exhaustive match on `get_user`: missing DatabaseError",
      "suggestions": [
        {
          "action": "add_handler",
          "exception": "DatabaseError"
        }
      ]
    }
  ]
}
```

### Suggestion Actions

| Action | Description |
|--------|-------------|
| `add_handler` | Add a handler for the specified exception |
| `remove_handler` | Remove an unexpected handler |
| `add_match` | Wrap the function call in a match statement |

---

## Integration with Pyrethrin

Pyrethrum is designed to be called by Pyrethrin (the Python runtime library):

1. **Pyrethrin** parses Python source code using `ast.parse()`
2. **Pyrethrin** converts the AST to JSON using `dump_raw_ast_json()`
3. **Pyrethrin** invokes Pyrethrum with `--stdin -f json`
4. **Pyrethrum** detects the raw AST format and routes to `python_plugin`
5. **Pyrethrum** parses AST in OCaml, extracts signatures/matches
6. **Pyrethrum** runs exhaustiveness analysis and returns diagnostics
7. **Pyrethrin** raises `ExhaustivenessError` if errors found

This architecture ensures:
- **Python does minimal work** - just AST serialization
- **OCaml does heavy lifting** - pattern matching on AST nodes
- **Clean separation** - language-specific logic in plugins
- **Extensibility** - new languages can add their own plugins
