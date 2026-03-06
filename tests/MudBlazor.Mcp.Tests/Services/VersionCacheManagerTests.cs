using MudBlazor.Mcp.Services;

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
