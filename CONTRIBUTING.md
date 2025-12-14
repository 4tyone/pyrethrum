# Contributing to Pyrethrum

Thank you for your interest in contributing to Pyrethrum!

## Development Setup

### Prerequisites

- OCaml 5.2+ (avoid 5.4 on ARM64 due to assembler bug)
- opam 2.0+
- dune 3.0+

### Setup

```bash
# Clone the repository
git clone https://github.com/your-org/pyrethrum.git
cd pyrethrum

# Create OCaml switch
opam switch create pyrethrum 5.2.1
eval $(opam env)

# Install dependencies
opam install dune yojson ppx_deriving cmdliner fmt alcotest

# Build
dune build

# Run tests
dune runtest
```

## Project Structure

```
pyrethrum/
├── bin/
│   └── main.ml           # CLI entry point
├── lib/
│   ├── ast.ml            # Core types and data structures
│   ├── parse.ml          # JSON parsing
│   ├── exhaustiveness.ml # Core analysis algorithm
│   └── diagnostics.ml    # Error message formatting
├── test/
│   └── test_pyrethrum.ml # Unit tests
├── dune-project
├── dune
└── pyrethrum.opam
```

## Making Changes

### 1. Create a Branch

```bash
git checkout -b feature/your-feature-name
```

### 2. Make Your Changes

- Follow existing code style
- Add tests for new functionality
- Update documentation if needed

### 3. Test Your Changes

```bash
# Build and run tests
dune runtest

# Build only
dune build

# Clean build
dune clean && dune build
```

### 4. Submit a Pull Request

- Write a clear PR description
- Reference any related issues
- Ensure all tests pass

## Code Guidelines

### Style

- Follow OCaml standard formatting
- Use meaningful variable names
- Keep functions focused and small
- Add type annotations for clarity

### Module Organization

- `ast.ml` - Data types only, no logic
- `parse.ml` - JSON parsing, no business logic
- `exhaustiveness.ml` - Core analysis algorithm
- `diagnostics.ml` - Error formatting and output

### Testing

- Write tests for all new functionality
- Use Alcotest for test organization
- Test edge cases
- Include both positive and negative tests

### Adding a New Language

1. Add language variant to `language` type in `ast.ml`
2. Add decorator/match names in `language_decorator_name` and `language_match_name`
3. Update `parse_language` in `parse.ml`
4. Add tests for the new language

## Building Binaries

```bash
# Debug build
dune build

# Release build
dune build --release

# Binary location
# _build/default/bin/main.exe
```

## Areas for Contribution

- New language support
- Performance optimizations
- Additional error codes
- Better error messages
- Documentation improvements

## Testing the Full Pipeline

To test end-to-end with Pyrethrin:

```bash
# Build pyrethrum
dune build

# Copy to pyrethrin
cp _build/default/bin/main.exe ../Pyrethrin/pyrethrin/bin/pyrethrum-darwin-arm64

# Test with pyrethrin
cd ../Pyrethrin
python -m pyrethrin check test_file.py
```

## Questions?

Open an issue for any questions or discussions.
