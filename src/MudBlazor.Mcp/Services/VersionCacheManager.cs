// Copyright (c) 2026 Mud MCP Contributors
// Licensed under the GNU General Public License v2.0. See LICENSE file in the project root for full license information.

using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;

namespace MudBlazor.Mcp.Services;

public sealed class VersionCacheManager : IVersionCacheManager
{
    private readonly string _dataPath;
    private readonly int _maxVersions;
    private readonly string _manifestPath;
    private readonly TimeProvider _timeProvider;
    private readonly ILogger<VersionCacheManager> _logger;
    private VersionManifest _manifest;

    public VersionCacheManager(string dataPath, int maxVersions = 3, TimeProvider? timeProvider = null, ILogger<VersionCacheManager>? logger = null)
    {
        if (maxVersions < 1)
            throw new ArgumentOutOfRangeException(nameof(maxVersions), maxVersions, "Must be at least 1.");

        _dataPath = dataPath;
        _maxVersions = maxVersions;
        _timeProvider = timeProvider ?? TimeProvider.System;
        _logger = logger ?? NullLogger<VersionCacheManager>.Instance;
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

    /// <summary>
    /// Evicts the least-recently-used cached version to make room for a new one.
    /// Must be called <b>before</b> registering a new version when the caller intends
    /// to add a version that is not yet tracked by the manifest.
    /// Returns the evicted version string, or <c>null</c> if no eviction was needed.
    /// </summary>
    public string? EvictToMakeRoomForNewVersion()
    {
        if (_manifest.Versions.Count < _maxVersions) return null;

        var oldest = _manifest.Versions.OrderBy(v => v.LastUsed).First();
        _manifest.Versions.Remove(oldest);
        Save();

        var versionDir = Path.Combine(_dataPath, $"v{oldest.Version}");
        try
        {
            if (Directory.Exists(versionDir))
            {
                foreach (var file in new DirectoryInfo(versionDir).GetFiles("*", SearchOption.AllDirectories))
                    file.Attributes = FileAttributes.Normal;
                Directory.Delete(versionDir, true);
            }
        }
        catch (IOException ex)
        {
            _logger.LogWarning(ex, "IO error deleting evicted version directory {Path}", versionDir);
        }
        catch (UnauthorizedAccessException ex)
        {
            _logger.LogWarning(ex, "Permission error deleting evicted version directory {Path}", versionDir);
        }

        return oldest.Version;
    }

    private VersionManifest LoadManifest()
    {
        if (!File.Exists(_manifestPath))
            return new VersionManifest();
        try
        {
            var json = File.ReadAllText(_manifestPath);
            return JsonSerializer.Deserialize<VersionManifest>(json) ?? new VersionManifest();
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "Corrupted versions manifest at {Path}, starting fresh", _manifestPath);
            return new VersionManifest();
        }
        catch (IOException ex)
        {
            _logger.LogWarning(ex, "IO error reading versions manifest at {Path}, starting fresh", _manifestPath);
            return new VersionManifest();
        }
    }

    private void Save()
    {
        try
        {
            Directory.CreateDirectory(_dataPath);
            var json = JsonSerializer.Serialize(_manifest, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(_manifestPath, json);
        }
        catch (IOException ex)
        {
            _logger.LogWarning(ex, "IO error saving versions manifest to {Path}", _manifestPath);
        }
        catch (UnauthorizedAccessException ex)
        {
            _logger.LogWarning(ex, "Permission error saving versions manifest to {Path}", _manifestPath);
        }
    }
}

internal sealed class VersionManifest
{
    public List<VersionEntry> Versions { get; set; } = [];
}

internal sealed class VersionEntry
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
