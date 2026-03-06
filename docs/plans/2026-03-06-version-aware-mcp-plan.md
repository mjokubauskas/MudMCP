# Version-Aware MudBlazor MCP — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make MudMCP serve documentation for a specific MudBlazor version, with LRU-cached multi-version clones (max 3).

**Architecture:** CLI `--version` arg determines the MudBlazor version. Each version gets its own git clone (checked out at the matching tag) and a serialized index.json cache. A `VersionCacheManager` tracks versions in `versions.json` and evicts the least-recently-used when a 4th version is added.

**Tech Stack:** C# .NET 10, LibGit2Sharp, System.Text.Json, xUnit + Moq

---

### Task 1: Add `--version` CLI Parsing to Program.cs

**Files:**
- Modify: `src/MudBlazor.Mcp/Program.cs:10-12`

**Step 1: Add version parsing before the stdio check**

At the top of `Program.cs`, after the existing `--stdio` check (line 11), parse `--version`:

```csharp
// Check for stdio transport mode
var useStdio = args.Contains("--stdio");

// Parse required --version argument
var versionIndex = Array.IndexOf(args, "--version");
if (versionIndex < 0 || versionIndex + 1 >= args.Length)
{
    Console.Error.WriteLine("Error: --version argument is required. Usage: --version 9.0.0");
    Console.Error.WriteLine("Check the MudBlazor PackageReference version in your project's .csproj file.");
    return 1;
}
var mudBlazorVersion = args[versionIndex + 1];
```

**Step 2: Pass version into DI registration**

Change the `RegisterCoreServices` call in both stdio and HTTP branches to pass the version:

```csharp
RegisterCoreServices(builder.Services, builder.Configuration, mudBlazorVersion);
```

Update the method signature:

```csharp
static void RegisterCoreServices(IServiceCollection services, IConfiguration configuration, string version)
{
    services.AddSingleton(new VersionContext(version));
    // ... rest unchanged
}
```

**Step 3: Create the VersionContext record**

Add to `Configuration/VersionContext.cs`:

```csharp
namespace MudBlazor.Mcp.Configuration;

public sealed record VersionContext(string Version)
{
    public string Tag => $"v{Version}";
    public string DataPath => $"./data/v{Version}";
    public string RepoPath => Path.Combine(DataPath, "mudblazor-repo");
    public string IndexPath => Path.Combine(DataPath, "index.json");
}
```

**Step 4: Update Program.cs return type**

Change `Program.cs` top-level statements to return `int` (add `return 0;` at the end of both branches).

**Step 5: Build to verify**

Run: `dotnet build src/MudBlazor.Mcp/MudBlazor.Mcp.csproj`
Expected: Build succeeds

**Step 6: Commit**

```bash
git add src/MudBlazor.Mcp/Program.cs src/MudBlazor.Mcp/Configuration/VersionContext.cs
git commit -m "Add --version CLI argument parsing and VersionContext"
```

---

### Task 2: Create VersionCacheManager

**Files:**
- Create: `src/MudBlazor.Mcp/Services/VersionCacheManager.cs`
- Create: `src/MudBlazor.Mcp/Services/IVersionCacheManager.cs`
- Create: `tests/MudBlazor.Mcp.Tests/Services/VersionCacheManagerTests.cs`

**Step 1: Write the tests**

```csharp
using MudBlazor.Mcp.Services;
using MudBlazor.Mcp.Configuration;

namespace MudBlazor.Mcp.Tests.Services;

public class VersionCacheManagerTests : IDisposable
{
    private readonly string _testDataPath;
    private readonly VersionCacheManager _manager;

    public VersionCacheManagerTests()
    {
        _testDataPath = Path.Combine(Path.GetTempPath(), $"mudmcp-test-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_testDataPath);
        _manager = new VersionCacheManager(_testDataPath, maxVersions: 3);
    }

    [Fact]
    public void IsVersionCached_ReturnsFalse_WhenNoVersionsExist()
    {
        Assert.False(_manager.IsVersionCached("9.0.0"));
    }

    [Fact]
    public void RegisterVersion_AddsVersion()
    {
        _manager.RegisterVersion("9.0.0");
        Assert.True(_manager.IsVersionCached("9.0.0"));
    }

    [Fact]
    public void TouchVersion_UpdatesLastUsed()
    {
        _manager.RegisterVersion("9.0.0");
        var before = _manager.GetLastUsed("9.0.0");
        Thread.Sleep(50);
        _manager.TouchVersion("9.0.0");
        var after = _manager.GetLastUsed("9.0.0");
        Assert.True(after > before);
    }

    [Fact]
    public void EvictIfNeeded_RemovesOldestWhenAtCapacity()
    {
        _manager.RegisterVersion("7.0.0");
        Thread.Sleep(50);
        _manager.RegisterVersion("8.0.0");
        Thread.Sleep(50);
        _manager.RegisterVersion("9.0.0");

        // Create fake directories so eviction can delete them
        Directory.CreateDirectory(Path.Combine(_testDataPath, "v7.0.0"));
        Directory.CreateDirectory(Path.Combine(_testDataPath, "v8.0.0"));
        Directory.CreateDirectory(Path.Combine(_testDataPath, "v9.0.0"));

        var evicted = _manager.EvictIfNeeded();
        Assert.Equal("7.0.0", evicted);
        Assert.False(_manager.IsVersionCached("7.0.0"));
        Assert.False(Directory.Exists(Path.Combine(_testDataPath, "v7.0.0")));
    }

    [Fact]
    public void EvictIfNeeded_ReturnsNull_WhenUnderCapacity()
    {
        _manager.RegisterVersion("9.0.0");
        Assert.Null(_manager.EvictIfNeeded());
    }

    [Fact]
    public void PersistsAcrossInstances()
    {
        _manager.RegisterVersion("9.0.0");

        var manager2 = new VersionCacheManager(_testDataPath, maxVersions: 3);
        Assert.True(manager2.IsVersionCached("9.0.0"));
    }

    public void Dispose()
    {
        if (Directory.Exists(_testDataPath))
        {
            Directory.Delete(_testDataPath, true);
        }
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `dotnet test tests/MudBlazor.Mcp.Tests --filter "FullyQualifiedName~VersionCacheManagerTests" -v n`
Expected: FAIL — `VersionCacheManager` does not exist

**Step 3: Create the interface**

```csharp
// src/MudBlazor.Mcp/Services/IVersionCacheManager.cs
namespace MudBlazor.Mcp.Services;

public interface IVersionCacheManager
{
    bool IsVersionCached(string version);
    void RegisterVersion(string version);
    void TouchVersion(string version);
    DateTimeOffset? GetLastUsed(string version);
    string? EvictIfNeeded();
}
```

**Step 4: Implement VersionCacheManager**

```csharp
// src/MudBlazor.Mcp/Services/VersionCacheManager.cs
using System.Text.Json;

namespace MudBlazor.Mcp.Services;

public sealed class VersionCacheManager : IVersionCacheManager
{
    private readonly string _dataPath;
    private readonly int _maxVersions;
    private readonly string _manifestPath;
    private VersionManifest _manifest;

    public VersionCacheManager(string dataPath, int maxVersions = 3)
    {
        _dataPath = dataPath;
        _maxVersions = maxVersions;
        _manifestPath = Path.Combine(dataPath, "versions.json");
        _manifest = LoadManifest();
    }

    public bool IsVersionCached(string version)
        => _manifest.Versions.Any(v => v.Version == version);

    public void RegisterVersion(string version)
    {
        if (IsVersionCached(version)) return;
        _manifest.Versions.Add(new VersionEntry(version, $"v{version}", DateTimeOffset.UtcNow));
        Save();
    }

    public void TouchVersion(string version)
    {
        var entry = _manifest.Versions.FirstOrDefault(v => v.Version == version);
        if (entry is null) return;
        entry.LastUsed = DateTimeOffset.UtcNow;
        Save();
    }

    public DateTimeOffset? GetLastUsed(string version)
        => _manifest.Versions.FirstOrDefault(v => v.Version == version)?.LastUsed;

    public string? EvictIfNeeded()
    {
        if (_manifest.Versions.Count < _maxVersions) return null;

        var oldest = _manifest.Versions.OrderBy(v => v.LastUsed).First();
        _manifest.Versions.Remove(oldest);
        Save();

        var versionDir = Path.Combine(_dataPath, $"v{oldest.Version}");
        if (Directory.Exists(versionDir))
        {
            // Remove read-only attributes (git files)
            foreach (var file in new DirectoryInfo(versionDir).GetFiles("*", SearchOption.AllDirectories))
                file.Attributes = FileAttributes.Normal;
            Directory.Delete(versionDir, true);
        }

        return oldest.Version;
    }

    private VersionManifest LoadManifest()
    {
        if (!File.Exists(_manifestPath))
            return new VersionManifest();
        var json = File.ReadAllText(_manifestPath);
        return JsonSerializer.Deserialize<VersionManifest>(json) ?? new VersionManifest();
    }

    private void Save()
    {
        Directory.CreateDirectory(_dataPath);
        var json = JsonSerializer.Serialize(_manifest, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(_manifestPath, json);
    }
}

public sealed class VersionManifest
{
    public List<VersionEntry> Versions { get; set; } = [];
}

public sealed class VersionEntry
{
    public string Version { get; set; }
    public string Tag { get; set; }
    public DateTimeOffset LastUsed { get; set; }

    public VersionEntry() { Version = ""; Tag = ""; }
    public VersionEntry(string version, string tag, DateTimeOffset lastUsed)
    {
        Version = version;
        Tag = tag;
        LastUsed = lastUsed;
    }
}
```

**Step 5: Run tests to verify they pass**

Run: `dotnet test tests/MudBlazor.Mcp.Tests --filter "FullyQualifiedName~VersionCacheManagerTests" -v n`
Expected: All 6 tests PASS

**Step 6: Commit**

```bash
git add src/MudBlazor.Mcp/Services/IVersionCacheManager.cs src/MudBlazor.Mcp/Services/VersionCacheManager.cs tests/MudBlazor.Mcp.Tests/Services/VersionCacheManagerTests.cs
git commit -m "Add VersionCacheManager with LRU eviction and persistence"
```

---

### Task 3: Modify GitRepositoryService for Version-Aware Cloning

**Files:**
- Modify: `src/MudBlazor.Mcp/Services/GitRepositoryService.cs`
- Modify: `src/MudBlazor.Mcp/Configuration/MudBlazorOptions.cs`

**Step 1: Update RepositoryOptions**

In `Configuration/MudBlazorOptions.cs`, modify `RepositoryOptions`:
- Remove the `Branch` property
- Remove the `LocalPath` property (now derived from `VersionContext`)
- Add `MaxCachedVersions` property

```csharp
public sealed class RepositoryOptions
{
    public string Url { get; set; } = "https://github.com/MudBlazor/MudBlazor.git";
    public int MaxCachedVersions { get; set; } = 3;
}
```

**Step 2: Update GitRepositoryService constructor**

Inject `VersionContext` and `IVersionCacheManager`. Use `VersionContext.RepoPath` instead of `_options.Repository.LocalPath`:

```csharp
public sealed class GitRepositoryService : IGitRepositoryService, IDisposable, IAsyncDisposable
{
    private readonly ILogger<GitRepositoryService> _logger;
    private readonly MudBlazorOptions _options;
    private readonly VersionContext _versionContext;
    private readonly IVersionCacheManager _cacheManager;
    private readonly SemaphoreSlim _syncLock = new(1, 1);
    private Repository? _repository;
    private bool _disposed;

    public GitRepositoryService(
        ILogger<GitRepositoryService> logger,
        IOptions<MudBlazorOptions> options,
        VersionContext versionContext,
        IVersionCacheManager cacheManager)
    {
        _logger = logger;
        _options = options.Value;
        _versionContext = versionContext;
        _cacheManager = cacheManager;
    }

    public string RepositoryPath => Path.GetFullPath(_versionContext.RepoPath);
    // ... rest follows
```

**Step 3: Simplify EnsureRepositoryAsync**

Replace the clone+pull logic. Since we clone at a tag, there's no pull needed:

```csharp
public async Task<bool> EnsureRepositoryAsync(CancellationToken cancellationToken = default)
{
    ObjectDisposedException.ThrowIf(_disposed, this);

    await _syncLock.WaitAsync(cancellationToken).ConfigureAwait(false);
    try
    {
        if (IsAvailable)
        {
            _logger.LogInformation("Repository for v{Version} already available at {Path}",
                _versionContext.Version, RepositoryPath);
            _cacheManager.TouchVersion(_versionContext.Version);
            return false;
        }

        // Evict oldest version if at capacity
        var evicted = _cacheManager.EvictIfNeeded();
        if (evicted is not null)
        {
            _logger.LogInformation("Evicted cached version v{Version} (LRU)", evicted);
        }

        _logger.LogInformation("Cloning MudBlazor repository at tag {Tag} to {Path}",
            _versionContext.Tag, RepositoryPath);

        var parentDir = Path.GetDirectoryName(RepositoryPath);
        if (!string.IsNullOrEmpty(parentDir))
        {
            Directory.CreateDirectory(parentDir);
        }

        await Task.Run(() =>
        {
            var cloneOptions = new CloneOptions
            {
                RecurseSubmodules = false
            };

            Repository.Clone(_options.Repository.Url, RepositoryPath, cloneOptions);

            // Checkout the specific tag
            using var repo = new Repository(RepositoryPath);
            var tag = repo.Tags[_versionContext.Tag]
                ?? throw new InvalidOperationException(
                    $"Tag '{_versionContext.Tag}' not found. Available tags: {string.Join(", ", repo.Tags.Select(t => t.FriendlyName).Where(n => n.StartsWith("v")).OrderDescending().Take(10))}");
            Commands.Checkout(repo, tag.Target as Commit ?? ((TagAnnotation)tag.Target).Target as Commit);
        }, cancellationToken).ConfigureAwait(false);

        _cacheManager.RegisterVersion(_versionContext.Version);

        _logger.LogInformation("Successfully cloned MudBlazor v{Version}. Commit: {Commit}",
            _versionContext.Version, CurrentCommitHash);

        return true;
    }
    catch (Exception ex) when (ex is not OperationCanceledException)
    {
        _logger.LogError(ex, "Failed to ensure MudBlazor repository for v{Version}", _versionContext.Version);
        throw;
    }
    finally
    {
        _syncLock.Release();
    }
}
```

**Step 4: Build to verify**

Run: `dotnet build src/MudBlazor.Mcp/MudBlazor.Mcp.csproj`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add src/MudBlazor.Mcp/Services/GitRepositoryService.cs src/MudBlazor.Mcp/Configuration/MudBlazorOptions.cs
git commit -m "Make GitRepositoryService version-aware with tag checkout"
```

---

### Task 4: Add Index Serialization to ComponentIndexer

**Files:**
- Modify: `src/MudBlazor.Mcp/Services/ComponentIndexer.cs`

**Step 1: Add serialization/deserialization support**

In `ComponentIndexer`, inject `VersionContext`. Modify `BuildIndexAsync` to check for cached `index.json` first:

```csharp
// Add field
private readonly VersionContext _versionContext;

// Add to constructor
public ComponentIndexer(
    IGitRepositoryService gitService,
    IDocumentationCache cache,
    XmlDocParser xmlParser,
    RazorDocParser razorParser,
    ExampleExtractor exampleExtractor,
    CategoryMapper categoryMapper,
    IOptions<MudBlazorOptions> options,
    ILogger<ComponentIndexer> logger,
    VersionContext versionContext)
{
    // ... existing assignments ...
    _versionContext = versionContext;
}
```

**Step 2: Modify BuildIndexAsync to use cache**

```csharp
public async Task BuildIndexAsync(CancellationToken cancellationToken = default)
{
    await _indexLock.WaitAsync(cancellationToken).ConfigureAwait(false);
    try
    {
        // Try loading from serialized cache first
        if (await TryLoadCachedIndexAsync(cancellationToken).ConfigureAwait(false))
        {
            _logger.LogInformation("Loaded cached index for v{Version} with {Count} components",
                _versionContext.Version, _components.Count);
            _isIndexed = true;
            _lastIndexed = DateTimeOffset.UtcNow;
            return;
        }

        _logger.LogInformation("Starting index build for v{Version}...", _versionContext.Version);
        var sw = System.Diagnostics.Stopwatch.StartNew();

        await _gitService.EnsureRepositoryAsync(cancellationToken).ConfigureAwait(false);

        if (!_gitService.IsAvailable)
        {
            throw new InvalidOperationException("Repository is not available for indexing");
        }

        var repoPath = _gitService.RepositoryPath!;

        await _categoryMapper.InitializeAsync(repoPath, cancellationToken).ConfigureAwait(false);
        await IndexComponentsAsync(repoPath, cancellationToken).ConfigureAwait(false);
        await IndexDocumentationAsync(repoPath, cancellationToken).ConfigureAwait(false);
        await IndexExamplesAsync(repoPath, cancellationToken).ConfigureAwait(false);

        _isIndexed = true;
        _lastIndexed = DateTimeOffset.UtcNow;

        // Serialize index to disk for future fast loads
        await SaveCachedIndexAsync(cancellationToken).ConfigureAwait(false);

        sw.Stop();
        _logger.LogInformation("Index build completed in {ElapsedMs}ms. Indexed {Count} components",
            sw.ElapsedMilliseconds, _components.Count);
    }
    finally
    {
        _indexLock.Release();
    }
}
```

**Step 3: Add TryLoadCachedIndexAsync and SaveCachedIndexAsync**

```csharp
private async Task<bool> TryLoadCachedIndexAsync(CancellationToken cancellationToken)
{
    var indexPath = _versionContext.IndexPath;
    if (!File.Exists(indexPath)) return false;

    try
    {
        var json = await File.ReadAllTextAsync(indexPath, cancellationToken).ConfigureAwait(false);
        var cached = JsonSerializer.Deserialize<CachedIndex>(json);
        if (cached is null) return false;

        _components.Clear();
        foreach (var component in cached.Components)
            _components[component.Name] = component;

        _apiReferences.Clear();
        foreach (var apiRef in cached.ApiReferences)
            _apiReferences[apiRef.TypeName] = apiRef;

        return true;
    }
    catch (Exception ex)
    {
        _logger.LogWarning(ex, "Failed to load cached index from {Path}, will rebuild", indexPath);
        return false;
    }
}

private async Task SaveCachedIndexAsync(CancellationToken cancellationToken)
{
    try
    {
        var cached = new CachedIndex(
            _components.Values.ToList(),
            _apiReferences.Values.ToList());

        var dir = Path.GetDirectoryName(_versionContext.IndexPath);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

        var json = JsonSerializer.Serialize(cached, new JsonSerializerOptions { WriteIndented = true });
        await File.WriteAllTextAsync(_versionContext.IndexPath, json, cancellationToken).ConfigureAwait(false);

        _logger.LogInformation("Saved index cache to {Path}", _versionContext.IndexPath);
    }
    catch (Exception ex)
    {
        _logger.LogWarning(ex, "Failed to save index cache — server will work but next startup will re-index");
    }
}

private sealed record CachedIndex(
    List<ComponentInfo> Components,
    List<ApiReference> ApiReferences);
```

**Step 4: Add required using**

Add `using System.Text.Json;` to the top of `ComponentIndexer.cs`.

**Step 5: Build to verify**

Run: `dotnet build src/MudBlazor.Mcp/MudBlazor.Mcp.csproj`
Expected: Build succeeds

**Step 6: Commit**

```bash
git add src/MudBlazor.Mcp/Services/ComponentIndexer.cs
git commit -m "Add index serialization/deserialization for fast startup"
```

---

### Task 5: Update appsettings.json and DI Registration

**Files:**
- Modify: `src/MudBlazor.Mcp/appsettings.json`
- Modify: `src/MudBlazor.Mcp/Program.cs`

**Step 1: Update appsettings.json**

Remove `Branch` and `LocalPath` from Repository config, add `MaxCachedVersions`:

```json
{
  "MudBlazor": {
    "Repository": {
      "Url": "https://github.com/MudBlazor/MudBlazor.git",
      "MaxCachedVersions": 3
    },
    "Cache": {
      "RefreshIntervalMinutes": 60,
      "ComponentCacheDurationMinutes": 30,
      "ExampleCacheDurationMinutes": 120
    },
    "Parsing": {
      "IncludeInternalComponents": false,
      "IncludeDeprecatedComponents": true,
      "MaxExamplesPerComponent": 20
    }
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "MudBlazor.Mcp": "Debug",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "AllowedHosts": "*"
}
```

**Step 2: Update RegisterCoreServices in Program.cs**

```csharp
static void RegisterCoreServices(IServiceCollection services, IConfiguration configuration, string version)
{
    var versionContext = new VersionContext(version);
    services.AddSingleton(versionContext);

    services.Configure<MudBlazorOptions>(configuration.GetSection("MudBlazor"));
    services.Configure<RepositoryOptions>(configuration.GetSection("MudBlazor:Repository"));
    services.Configure<CacheOptions>(configuration.GetSection("MudBlazor:Cache"));
    services.Configure<ParsingOptions>(configuration.GetSection("MudBlazor:Parsing"));

    // Read MaxCachedVersions from config
    var repoOptions = configuration.GetSection("MudBlazor:Repository").Get<RepositoryOptions>() ?? new RepositoryOptions();
    services.AddSingleton<IVersionCacheManager>(
        new VersionCacheManager("./data", repoOptions.MaxCachedVersions));

    services.AddMemoryCache();

    services.AddSingleton<IGitRepositoryService, GitRepositoryService>();
    services.AddSingleton<IDocumentationCache, DocumentationCache>();
    services.AddSingleton<IComponentIndexer, ComponentIndexer>();

    services.AddSingleton<XmlDocParser>();
    services.AddSingleton<RazorDocParser>();
    services.AddSingleton<ExampleExtractor>();
    services.AddSingleton<CategoryMapper>();
}
```

**Step 3: Update MCP server info to include version**

In both stdio and HTTP branches, update the server info:

```csharp
options.ServerInfo = new() { Name = $"MudBlazor Documentation Server (v{mudBlazorVersion})", Version = "1.0.0" };
```

**Step 4: Build to verify**

Run: `dotnet build src/MudBlazor.Mcp/MudBlazor.Mcp.csproj`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add src/MudBlazor.Mcp/appsettings.json src/MudBlazor.Mcp/Program.cs
git commit -m "Update DI registration and config for version-aware server"
```

---

### Task 6: Add Version Info to Tool Descriptions

**Files:**
- Modify: `src/MudBlazor.Mcp/Tools/ComponentListTools.cs`
- Modify: `src/MudBlazor.Mcp/Tools/ComponentDetailTools.cs`
- Modify: `src/MudBlazor.Mcp/Tools/ComponentSearchTools.cs`
- Modify: `src/MudBlazor.Mcp/Tools/ComponentExampleTools.cs`
- Modify: `src/MudBlazor.Mcp/Tools/ApiReferenceTools.cs`

**Step 1: Inject VersionContext into each tool's output**

Since `[Description]` on `[McpServerTool]` is a compile-time constant, we can't put the version there. Instead, prepend a version header to each tool's output string. Inject `VersionContext` as a parameter in each tool method.

For example, in `ComponentListTools.ListComponentsAsync`:

```csharp
public static async Task<string> ListComponentsAsync(
    IComponentIndexer indexer,
    ILogger<ComponentListTools> logger,
    VersionContext versionContext,  // Add this
    // ... rest of params
```

And at the start of the output StringBuilder:

```csharp
sb.AppendLine($"# MudBlazor Components v{versionContext.Version} ({components.Count} total)");
```

Apply the same pattern to `ListCategoriesAsync`, `GetComponentDetailAsync`, `SearchComponentsAsync`, `GetComponentExamplesAsync`, and API reference tools — inject `VersionContext` and include the version in the output header.

**Step 2: Update the `[Description]` attributes**

Update each tool's `[Description]` to mention version awareness. For example:

```csharp
[Description("Lists all available MudBlazor components for the configured version. Optionally filter by category. If a component seems missing, verify the --version matches your project's MudBlazor PackageReference in the .csproj file.")]
```

**Step 3: Build to verify**

Run: `dotnet build src/MudBlazor.Mcp/MudBlazor.Mcp.csproj`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add src/MudBlazor.Mcp/Tools/
git commit -m "Add version info to tool outputs and descriptions"
```

---

### Task 7: Clean Up Old Data and Update .mcp.json

**Files:**
- Modify: `<project>/.mcp.json` (each project using MudMCP)

**Step 1: Delete the old single-clone data folder**

The existing `src/MudBlazor.Mcp/data/mudblazor-repo` is the old single-version clone. Delete it so the new version-aware system starts fresh:

```bash
rm -rf src/MudBlazor.Mcp/data/mudblazor-repo
```

**Step 2: Update .mcp.json in the quinn.Global project**

```json
{
  "mcpServers": {
    "mudblazor": {
      "command": "dotnet",
      "args": [
        "run",
        "--project",
        "C:\\Projects\\MudMCP\\src\\MudBlazor.Mcp\\MudBlazor.Mcp.csproj",
        "--",
        "--stdio",
        "--version",
        "9.0.0"
      ]
    }
  }
}
```

**Step 3: Run full test suite**

Run: `dotnet test tests/MudBlazor.Mcp.Tests -v n`
Expected: All tests pass

**Step 4: Smoke test — run the server**

Run: `dotnet run --project src/MudBlazor.Mcp/MudBlazor.Mcp.csproj -- --stdio --version 9.0.0`
Expected: Server starts, clones MudBlazor at tag v9.0.0, builds index, serializes to `data/v9.0.0/index.json`

**Step 5: Smoke test — second run should load from cache**

Kill and re-run the same command. Check stderr logs for "Loaded cached index" message instead of "Starting index build".

**Step 6: Commit the .mcp.json update and push**

```bash
git add .mcp.json
git commit -m "Update .mcp.json with --version parameter"
git push origin main
```
