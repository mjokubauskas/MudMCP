# Mud MCP

An enterprise-grade Model Context Protocol (MCP) server that provides AI assistants with comprehensive access to MudBlazor component documentation, code examples, and API reference.

[![.NET 10](https://img.shields.io/badge/.NET-10.0-purple)](https://dotnet.microsoft.com/)
[![MCP Protocol](https://img.shields.io/badge/MCP-Protocol-blue)](https://modelcontextprotocol.io/)
[![License: GPL-2.0](https://img.shields.io/badge/License-GPL%202.0-green.svg)](LICENSE)

> **Disclaimer:** This project is not affiliated with, endorsed by, or officially supported by the MudBlazor team. It is an independent implementation that extracts and serves documentation from the official MudBlazor repository.

---

## 📖 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Quick Start](#quick-start)
- [Documentation](#documentation)
- [Available MCP Tools](#available-mcp-tools)
- [Project Structure](#project-structure)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

Mud MCP bridges the gap between AI assistants and MudBlazor component documentation. It clones the official MudBlazor repository, parses source files using Roslyn, and exposes an indexed API via the Model Context Protocol—enabling AI agents like GitHub Copilot, Claude, and other MCP-compatible clients to provide accurate, context-aware assistance for Blazor development.

### Key Value Propositions

- **Real-time Documentation**: Always serves the latest documentation from MudBlazor's dev branch
- **AI-Optimized Output**: Formats responses in Markdown for optimal LLM consumption
- **Production-Ready**: Built with Aspire 13.1, health checks, and observability
- **Flexible Deployment**: Supports both HTTP and stdio transports

---

## Features

| Feature | Description |
|---------|-------------|
| **Component Discovery** | List all ~85 MudBlazor components with category filtering |
| **Detailed Documentation** | Access parameters, events, methods, and inheritance info |
| **Code Examples** | Extract real examples from the MudBlazor documentation |
| **Semantic Search** | Search components by name, description, or parameters |
| **API Reference** | Full API reference for components and enum types |
| **Related Components** | Discover related components through inheritance and categories |
| **Health Monitoring** | Built-in health checks with detailed status reporting |
| **Expert Agent** | Pre-built agent file for optimal MCP tool usage with GitHub Copilot |

---

## MudBlazor Expert Agent

To maximize the value of the MCP server, this project includes a specialized GitHub Copilot agent file:

**Location:** `.github/agents/mudblazor-expert.agent.md`

The agent file teaches GitHub Copilot how to effectively use the MudBlazor MCP tools by providing:

- **Decision Logic**: Automatically selects the right MCP tool for each query
- **Best Practices**: Enforces "query before answering" to prevent hallucination
- **Blazor Guidelines**: Includes component architecture and rendering optimization patterns
- **Tool Chaining**: Combines multiple tools for comprehensive answers

**Example workflow:**
```
User: "How do I create a form with validation?"

Agent:
1. search_components("form input validation") → Find relevant components
2. get_component_detail("MudForm") → Get parameters and events
3. get_component_examples("MudTextField", filter="validation") → Get code examples
4. Provide complete, accurate answer with working code
```

> **Credits:** This agent file is derived from work in the [github/awesome-copilot](https://github.com/github/awesome-copilot) repository.

---

## Quick Start

### Prerequisites

- [.NET 10 SDK](https://dotnet.microsoft.com/download)
- [Git](https://git-scm.com/)

### 1. Clone and Build

```bash
dotnet build
```

### 2. Run the Server

```bash
dotnet run
```

The server will:
1. Clone the MudBlazor repository (~500MB)
2. Build an in-memory index of all components
3. Start the MCP server on `http://localhost:5180`

### 3. Verify

```bash
curl http://localhost:5180/health
```

Expected response:
```json
{
  "status": "Healthy",
  "totalDuration": 15.2,
  "checks": [{
    "name": "indexer",
    "status": "Healthy",
    "description": "Index contains 85 components in 12 categories."
  }]
}
```

### 4. Connect Your AI Assistant

**VS Code / Cursor (HTTP mode, mcp.json):**
```json
{
  "servers": {
    "mudblazor": {
      "type": "http",
      "url": "http://localhost:5180/mcp"
    }
  }
}
```

---

## Local MCP (stdio — no frontend required)

Run the MCP server locally without starting a web server or the Aspire dashboard. The server communicates directly through stdin/stdout, which is the native mode for Cursor, Claude Desktop, and most MCP clients.

### Option A — dotnet run (development)

Copy [`mcp.local.json`](./mcp.local.json) into your `.cursor/mcp.json` or `claude_desktop_config.json`. The path inside already points to this repository:

```json
{
  "mcpServers": {
    "mudblazor": {
      "command": "dotnet",
      "args": [
        "run",
        "--project",
        "C:\\Users\\current-user\\source\\repos\\MudMCP\\src\\MudBlazor.Mcp\\MudBlazor.Mcp.csproj",
        "--",
        "--stdio"
      ],
      "env": {}
    }
  }
}
```

> The first run takes longer because it clones the MudBlazor repository (~500 MB) and builds the index.

### Option B — Self-contained executable (recommended for daily use)

Publish a single-file executable that starts instantly without the .NET SDK:

```powershell
dotnet publish src/MudBlazor.Mcp/MudBlazor.Mcp.csproj `
  -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -o publish/win-x64
```

Then use [`mcp.executable.json`](./mcp.executable.json) as your MCP configuration:

```json
{
  "mcpServers": {
    "mudblazor": {
      "command": "C:\\Users\\current-user\\source\\repos\\MudMCP\\publish\\win-x64\\MudBlazor.Mcp.exe",
      "args": ["--stdio"],
      "env": {}
    }
  }
}
```

### Option C — Docker (HTTP mode, persistent cache)

Run the server in a container with built-in health checks and a named volume that persists the cloned MudBlazor repository across restarts.

**Prerequisites:** [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or Docker Engine + Compose plugin)

```bash
# Build the image and start the container
docker compose up --build -d

# Follow startup logs (first run clones ~500 MB — takes a few minutes)
docker compose logs -f

# Check health
curl http://localhost:5180/health
```

The MCP endpoint is available at `http://localhost:5180/mcp` — no changes needed to an existing `mcp.json` that already points to `:5180`.

**Volume:** The MudBlazor repository is stored in a named Docker volume (`mudblazor-data`) mounted at `/app/data/mudblazor-repo`. Subsequent `docker compose up` calls reuse the cached clone; only `git fetch` updates are performed.

```bash
# Stop without removing the volume (cache is preserved)
docker compose down

# Stop AND delete the cached clone (forces a full re-clone next start)
docker compose down -v
```

**Connect your AI assistant** — same config as HTTP mode:
```json
{
  "servers": {
    "mudblazor": {
      "type": "http",
      "url": "http://localhost:5180/mcp"
    }
  }
}
```

---

### Transport comparison

| Mode | Command | Kestrel | Use case |
|------|---------|---------|----------|
| `--stdio` | `dotnet run -- --stdio` or `.exe --stdio` | No | Cursor, Claude Desktop, local clients |
| HTTP (default) | `dotnet run` | Yes (`:5180`) | VS Code HTTP, MCP Inspector, remote |
| Docker | `docker compose up` | Yes (`:5180→8080`) | Containerised / persistent cache |

---

## Documentation

For comprehensive documentation, see the [docs](./docs/) folder:

| Document | Description |
|----------|-------------|
| [Overview](./docs/01-overview.md) | Architecture, design principles, and system overview |
| [Getting Started](./docs/02-getting-started.md) | Installation, prerequisites, and first run |
| [Architecture](./docs/03-architecture.md) | Technical architecture and component design |
| [Best Practices](./docs/04-best-practices.md) | Implemented patterns and practices |
| [Tools Reference](./docs/05-tools-reference.md) | Complete reference for all 12 MCP tools |
| [Configuration](./docs/06-configuration.md) | Configuration options and environment setup |
| [Testing](./docs/07-testing.md) | Unit testing strategy and examples |
| [MCP Inspector](./docs/08-mcp-inspector.md) | Testing with MCP Inspector tool |
| [IDE Integration](./docs/09-ide-integration.md) | VS Code, Visual Studio, and Claude Desktop setup |
| [Troubleshooting](./docs/10-troubleshooting.md) | Common issues and solutions |
| [Changelog](./docs/CHANGELOG.md) | Version history and release notes |

---

## Available MCP Tools

| Tool | Description |
|------|-------------|
| `list_components` | Lists all MudBlazor components with optional category filter |
| `list_categories` | Lists all component categories with descriptions |
| `get_component_detail` | Gets comprehensive details about a specific component |
| `get_component_parameters` | Gets all parameters for a component |
| `get_component_examples` | Gets code examples for a component |
| `get_example_by_name` | Gets a specific example by name |
| `list_component_examples` | Lists all example names for a component |
| `search_components` | Searches components by query |
| `get_components_by_category` | Gets all components in a specific category |
| `get_related_components` | Gets components related to a specific component |
| `get_api_reference` | Gets full API reference for a type |
| `get_enum_values` | Gets all values for a MudBlazor enum |

**Example Interaction:**

Ask your AI assistant:
- *"List all MudBlazor button components"*
- *"Show me how to use MudTextField with validation"*
- *"What parameters does MudDataGrid support?"*
- *"What are the available Color enum values?"*

---

## Project Structure

```
MudBlazor.Mcp/
├── .github/
│   └── agents/
│       └── mudblazor-expert.agent.md  # GitHub Copilot agent file
├── src/
│   ├── MudBlazor.Mcp/              # Main MCP server
│   │   ├── Configuration/          # Strongly-typed options
│   │   ├── Models/                 # Domain models (immutable records)
│   │   ├── Services/               # Core services
│   │   │   └── Parsing/            # Roslyn-based parsers
│   │   └── Tools/                  # MCP tool implementations
│   ├── MudBlazor.Mcp.AppHost/      # Aspire orchestration
│   └── MudBlazor.Mcp.ServiceDefaults/  # Shared service configuration
├── tests/
│   └── MudBlazor.Mcp.Tests/        # Unit tests
├── docs/                           # Documentation
└── README.md
```

---

## Contributing

Contributions are welcome! Please see the [Contributing Guide](./docs/01-overview.md#contributing) for details.

### Quick Contribution Steps

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

This project is licensed under the **GNU General Public License v2.0 (GPL-2.0)** in compliance with MudBlazor's licensing.

- Source code is provided under GPL-2.0
- Original copyright notices are retained
- Modifications are documented

See the [LICENSE](LICENSE) file for full details.

---

## Acknowledgments

- [MudBlazor](https://mudblazor.com/) — The excellent Blazor component library
- [Model Context Protocol](https://modelcontextprotocol.io/) — The protocol specification
- [.NET Aspire](https://learn.microsoft.com/dotnet/aspire/) — Cloud-native orchestration
- [Roslyn](https://github.com/dotnet/roslyn) — The .NET Compiler Platform
- [github/awesome-copilot](https://github.com/github/awesome-copilot) — Inspiration for the expert agent file

---

<p align="center">
  Built with ❤️ for the Blazor community
</p>
