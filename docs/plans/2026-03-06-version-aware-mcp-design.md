# Version-Aware MudBlazor MCP Server

## Problem

The MudMCP server always indexes the latest `dev` branch of MudBlazor. Different projects use different MudBlazor versions (e.g., 8.x vs 9.x), so the served documentation may not match the project's actual API.

## Design

### Version Resolution

The server requires a `--version` CLI argument specifying the MudBlazor version to serve (e.g., `--version 9.0.0`). If missing, the server fails with a clear error message.

Per-project `.mcp.json` configuration:

```json
{
  "mcpServers": {
    "mudblazor": {
      "command": "dotnet",
      "args": [
        "run", "--project", "C:\\Projects\\MudMCP\\src\\MudBlazor.Mcp\\MudBlazor.Mcp.csproj",
        "--", "--stdio", "--version", "9.0.0"
      ]
    }
  }
}
```

Tool descriptions include the configured version so the AI knows which version it's serving. A note instructs the AI to verify the version against the project's `.csproj` `PackageReference` if something seems off.

### Multi-Clone LRU Cache

Each version gets its own clone and serialized index under `data/`:

```
data/
  versions.json
  v8.15.0/
    mudblazor-repo/
    index.json
  v9.0.0/
    mudblazor-repo/
    index.json
```

**Startup flow:**

1. Parse `--version` from CLI args
2. Check `versions.json` — is this version already cloned and indexed?
   - **Yes** → load `index.json`, update `lastUsed` timestamp. Ready instantly.
   - **No** → enforce max 3 cached versions. If at capacity, delete the version with the oldest `lastUsed`. Clone MudBlazor repo, checkout tag `v{version}`, run Roslyn indexing, serialize to `index.json`.

**`versions.json` format:**

```json
{
  "maxVersions": 3,
  "versions": [
    { "version": "9.0.0", "tag": "v9.0.0", "lastUsed": "2026-03-06T14:00:00Z" },
    { "version": "8.15.0", "tag": "v8.15.0", "lastUsed": "2026-03-05T10:00:00Z" }
  ]
}
```

Tags are immutable so no `git pull` is needed after initial clone.

### Changes to Existing Code

**`Program.cs`** — Parse `--version` from CLI args. Fail with clear error if missing. Pass version string to services during DI registration.

**`GitRepositoryService`** — Change clone target from `data/mudblazor-repo` to `data/v{version}/mudblazor-repo`. Checkout git tag instead of branch. Remove pull logic (tags are immutable).

**`ComponentIndexer`** — On startup, check for `data/v{version}/index.json`. If exists, deserialize and load (fast path). If not, run existing Roslyn parsing pipeline, then serialize result to `index.json`.

**New: `VersionCacheManager`** — Manages `versions.json`: tracks cloned versions and `lastUsed` timestamps, updates `lastUsed` on each startup, enforces max 3 versions with LRU eviction (deletes folder of oldest version).

**`MudBlazorOptions` / `appsettings.json`** — Remove `Branch` config (replaced by version). Keep `Url`. Add `MaxCachedVersions: 3`.

**Tool descriptions** — Append the configured version to tool descriptions so the AI sees which version it's serving docs for.

### What Stays the Same

- Parsing services (`XmlDocParser`, `RazorDocParser`, `ExampleExtractor`, `CategoryMapper`) — unchanged, they work on whatever checkout they're pointed at
- Tool logic — same tools, same behavior, just version-aware index underneath
- Stdio and HTTP transport modes

## Repository

Fork: https://github.com/Sarowx/MudMCP
Upstream: https://github.com/mcbodge/MudMCP
