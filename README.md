# Calith

A native macOS AI chat client built with SwiftUI.

## Features

### Multi-Provider Support

Calith works with five AI backends:

| Provider | Notes |
|---|---|
| **Apple Intelligence** | On-device via Foundation Models (default) |
| **OpenAI** | GPT-4o and other models via the Responses API |
| **Anthropic** | Claude models via the Messages API |
| **Google Gemini** | Gemini models via the Generative Language API |
| **Ollama** | Local models (llama3.1, etc.) |

Each provider supports streaming responses, adaptive thinking/reasoning, and configurable context windows.

### Tool Use

The assistant can use tools to interact with your system, each with a configurable confirmation policy:

- **ReadFile / WriteFile / ListDirectory** -- File system access
- **RunCommand** -- Shell command execution (asks by default)
- **RunAppleScript** -- AppleScript execution (asks by default)
- **WebFetch** -- Fetch content from URLs
- **WebSearch** -- Web search via Tavily

Tool calls appear inline with human-readable descriptions and approve/deny controls.

### Conversations and Memory

- Create, search, and switch between multiple conversations
- Automatic title generation using the active model
- Persistent memory system that extracts and recalls facts about you across conversations
- Location awareness (optional) for context-relevant responses

### Interface

- Native macOS look and feel with standard controls and SF Symbols
- Rich Markdown rendering with text selection
- Streaming text with character fade-in animation
- Collapsible thinking/reasoning display
- Animated input field glow during streaming
- Multi-modal input for models that support it
- Auto-updates via Sparkle

## Install

Requires macOS 26.0 (Tahoe) or later.

Download the latest DMG from [Releases](../../releases/latest), open it, and
drag Calith into your Applications folder. The app checks for updates
automatically via Sparkle.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for build-from-source instructions,
development guidelines, and the release process.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
