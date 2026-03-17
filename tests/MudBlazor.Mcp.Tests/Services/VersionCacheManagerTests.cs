using MudBlazor.Mcp.Services;

namespace MudBlazor.Mcp.Tests.Services;

/// <summary>
/// A controllable <see cref="TimeProvider"/> for deterministic testing without Thread.Sleep.
/// </summary>
internal sealed class FakeTimeProvider : TimeProvider
{
    private DateTimeOffset _utcNow;

    public FakeTimeProvider(DateTimeOffset startTime) => _utcNow = startTime;

    public override DateTimeOffset GetUtcNow() => _utcNow;

    public void Advance(TimeSpan delta) => _utcNow += delta;
}

public class VersionCacheManagerTests : IDisposable
{
    private readonly string _testDataPath;
    private readonly FakeTimeProvider _timeProvider;
    private readonly VersionCacheManager _manager;

    public VersionCacheManagerTests()
    {
        _testDataPath = Path.Combine(Path.GetTempPath(), $"mudmcp-test-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_testDataPath);
        _timeProvider = new FakeTimeProvider(new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero));
        _manager = new VersionCacheManager(_testDataPath, maxVersions: 3, _timeProvider);
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
        _timeProvider.Advance(TimeSpan.FromSeconds(1));
        _manager.TouchVersion("9.0.0");
        var after = _manager.GetLastUsed("9.0.0");
        Assert.True(after > before);
    }

    [Fact]
    public void EvictIfNeeded_RemovesOldestWhenAtCapacity()
    {
        _manager.RegisterVersion("7.0.0");
        _timeProvider.Advance(TimeSpan.FromSeconds(1));
        _manager.RegisterVersion("8.0.0");
        _timeProvider.Advance(TimeSpan.FromSeconds(1));
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
    public void Constructor_ThrowsForZeroMaxVersions()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new VersionCacheManager(_testDataPath, maxVersions: 0));
    }

    [Fact]
    public void Constructor_ThrowsForNegativeMaxVersions()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new VersionCacheManager(_testDataPath, maxVersions: -1));
    }

    [Fact]
    public void PersistsAcrossInstances()
    {
        _manager.RegisterVersion("9.0.0");

        var manager2 = new VersionCacheManager(_testDataPath, maxVersions: 3);
        Assert.True(manager2.IsVersionCached("9.0.0"));
    }

    [Fact]
    public void Constructor_SelfHeals_WhenManifestIsCorrupted()
    {
        // Write corrupt JSON to versions.json
        var manifestPath = Path.Combine(_testDataPath, "versions.json");
        File.WriteAllText(manifestPath, "{{not valid json!!");

        // Should not throw — self-heals by returning an empty manifest
        var manager = new VersionCacheManager(_testDataPath, maxVersions: 3);
        Assert.False(manager.IsVersionCached("9.0.0"));

        // Should be able to register a new version (which overwrites the bad file)
        manager.RegisterVersion("9.0.0");
        Assert.True(manager.IsVersionCached("9.0.0"));
    }

    public void Dispose()
    {
        if (Directory.Exists(_testDataPath))
        {
            Directory.Delete(_testDataPath, true);
        }
    }
}
