// Copyright (c) 2026 Mud MCP Contributors
// Licensed under the GNU General Public License v2.0. See LICENSE file in the project root for full license information.

namespace MudBlazor.Mcp.Services;

public interface IVersionCacheManager
{
    bool IsVersionCached(string version);
    void RegisterVersion(string version);
    void TouchVersion(string version);
    DateTimeOffset? GetLastUsed(string version);

    /// <summary>
    /// Evicts the least-recently-used cached version to make room for a new one.
    /// Must be called <b>before</b> registering a new version.
    /// Returns the evicted version string, or <c>null</c> if no eviction was needed.
    /// </summary>
    string? EvictToMakeRoomForNewVersion();
}
