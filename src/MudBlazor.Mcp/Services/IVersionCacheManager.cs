namespace MudBlazor.Mcp.Services;

public interface IVersionCacheManager
{
    bool IsVersionCached(string version);
    void RegisterVersion(string version);
    void TouchVersion(string version);
    DateTimeOffset? GetLastUsed(string version);
    string? EvictIfNeeded();
}
