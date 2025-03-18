# Customer.io iOS SDK - Developer Guide

## Commands
- Build: `swift build`
- Test all: `swift test`
- Test single: `swift test --filter TestClassName/testMethodName`
- Lint: `make lint`
- Format: `make format`
- Generate code: `make generate`

## Code Style
- Swift 5.3+ with protocol-oriented design
- Naming: CamelCase for types, camelCase for properties/methods
- Descriptive method names (e.g., `identify`, `registerDeviceToken`)
- Use dependency injection pattern
- Modular architecture (Common, DataPipeline, MessagingPush, etc.)
- Document public APIs with doc comments
- Error handling: use Result types for operations that can fail
- Avoid force unwrapping (!) except in tests
- Keep methods small and focused
- Use SwiftLint rules (strict mode)
- No binary/decimal/hex grouping, no semicolons

## Project Structure
- Sources/ - Main SDK code organized by module
- Tests/ - Test files matching module structure
- Apps/ - Sample applications demonstrating SDK usage