// Copyright (c) 2026 Mud MCP Contributors
// Licensed under the GNU General Public License v2.0. See LICENSE file in the project root for full license information.

namespace MudBlazor.Mcp.Configuration;

public sealed record VersionContext(string Version)
{
    public string Tag => $"v{Version}";
    public string DataPath => $"./data/v{Version}";
    public string RepoPath => Path.Combine(DataPath, "mudblazor-repo");
    public string IndexPath => Path.Combine(DataPath, "index.json");
}
