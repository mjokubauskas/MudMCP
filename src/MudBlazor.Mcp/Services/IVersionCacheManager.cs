// Copyright (c) 2026 Mud MCP Contributors
// Licensed under the GNU General Public License v2.0. See LICENSE file in the project root for full license information.

namespace MudBlazor.Mcp.Services;

public interface IVersionCacheManager
{
    bool IsVersionCached(string version);
    void RegisterVersion(string version);
    void TouchVersion(string version);
    DateTimeOffset? GetLastUsed(string version);
    string? EvictIfNeeded();
}
