// Copyright (c) 2026 Mud MCP Contributors
// Licensed under the GNU General Public License v2.0. See LICENSE file in the project root for full license information.

using System.Text.Json;

namespace MudBlazor.Mcp.Services;

public sealed class VersionCacheManager : IVersionCacheManager
{
    private readonly string _dataPath;
    private readonly int _maxVersions;
    private readonly string _manifestPath;
    private readonly TimeProvider _timeProvider;
    private VersionManifest _manifest;

    public VersionCacheManager(string dataPath, int maxVersions = 3, TimeProvider? timeProvider = null)
    {
        if (maxVersions < 1)
            throw new ArgumentOutOfRangeException(nameof(maxVersions), maxVersions, "Must be at least 1.");

        _dataPath = dataPath;
        _maxVersions = maxVersions;
        _timeProvider = timeProvider ?? TimeProvider.System;
        _manifestPath = Path.Combine(dataPath, "versions.json");
        _manifest = LoadManifest();
    }

    public bool IsVersionCached(string version)
        => _manifest.Versions.Any(v => v.Version == version);

    public void RegisterVersion(string version)
    {
        if (IsVersionCached(version)) return;
        _manifest.Versions.Add(new VersionEntry(version, $"v{version}", _timeProvider.GetUtcNow()));
        Save();
    }

    public void TouchVersion(string version)
    {
        var entry = _manifest.Versions.FirstOrDefault(v => v.Version == version);
        if (entry is null) return;
        entry.LastUsed = _timeProvider.GetUtcNow();
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
