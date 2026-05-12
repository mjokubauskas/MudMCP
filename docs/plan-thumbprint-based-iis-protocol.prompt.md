## Plan: Thumbprint-Based IIS Protocol

Implement the requested behavior in the IIS deployment layer, where certificate thumbprints are already modeled. Add an explicit automatic protocol mode so deployment uses HTTPS when a certificate thumbprint is supplied, keeps HTTPS when an existing HTTPS IIS binding already has a certificate, and otherwise falls back to HTTP. Keep Kestrel/app runtime behavior unchanged because the agreed scope is IIS deployment only.

**Steps**
1. Add an automatic protocol mode to `eng/scripts/Configure-IisWebsite.ps1`. Extend `BindingProtocol` to accept `auto`, make `auto` the default, and keep explicit `http`/`https` available for manual override scenarios.
2. Normalize `SslCertificateThumbprint` from the parameter or `IIS_SSL_CERTIFICATE_THUMBPRINT`, preserving the existing Azure DevOps literal handling for unresolved values like `$(iisDevSslCertificateThumbprint)`.
3. Extract or add a small protocol-resolution helper used by `Configure-IisWebsite.ps1`: in `auto`, select `https` when a normalized thumbprint exists; select `https` when an existing HTTPS binding on the requested port has a certificate; otherwise select `http`. For explicit `https`, continue to require either a thumbprint or an existing HTTPS cert. For explicit `http`, use HTTP.
4. Keep certificate validation strict when a thumbprint is supplied: remove whitespace, uppercase it, validate it exists in `Cert:\LocalMachine\My`, and fail if missing.
5. Run the rest of the binding creation/update/removal logic against the resolved effective protocol. Preserve the current safety pattern of creating/validating the desired binding before removing opposite-protocol bindings.
6. Make the resolved protocol available to later Azure Pipeline tasks. Have `Configure-IisWebsite.ps1` emit a clear log line and set an Azure DevOps variable such as `iisEffectiveBindingProtocol` to `http` or `https` after resolution.
7. Update `eng/templates/deploy-iis.yaml` so the health-check task uses `$(iisEffectiveBindingProtocol)` from the configure step instead of the original requested `bindingProtocol` parameter. Keep `healthScheme` only as a fallback/manual override if needed.
8. Update `eng/templates/deploy-iis-stage.yaml` and `eng/azure-pipelines.yaml` so `iisBindingProtocol` defaults to `auto`, accepted values are documented as `auto`, `http`, and `https`, and per-environment thumbprint variables remain the HTTPS opt-in path.
9. Add Pester coverage for the protocol-resolution helper. Cover: thumbprint parameter selects HTTPS; env thumbprint selects HTTPS; unresolved Azure DevOps literal counts as unset; no thumbprint/no existing cert selects HTTP; no thumbprint/existing HTTPS cert selects HTTPS; explicit HTTP stays HTTP; explicit HTTPS without thumbprint or existing cert fails clearly.
10. Update documentation in `eng/README.md`, `docs/02-getting-started.md`, `docs/06-configuration.md`, `docs/08-mcp-inspector.md`, `docs/09-ide-integration.md`, and `docs/10-troubleshooting.md` where HTTP/HTTPS behavior, health checks, localhost URLs, IIS deployment, or certificate thumbprints are discussed. State that local and Docker examples remain HTTP by default, while IIS deployment defaults to auto protocol selection.
11. Leave `src/MudBlazor.Mcp/Program.cs`, `appsettings.json`, `Dockerfile`, and `docker-compose.yml` unchanged unless implementation discovery finds a direct coupling to IIS protocol resolution. The user selected IIS deployment only, and Docker/local runtime already defaults to HTTP.

**Relevant files**
- `eng/scripts/Configure-IisWebsite.ps1` — central IIS binding logic; update protocol resolution, validation, logging, Azure DevOps variable emission, and help text.
- `eng/templates/deploy-iis.yaml` — deployment template that passes `BindingProtocol`, `sslCertificateThumbprint`, and runs health checks; align health scheme with the effective protocol.
- `eng/templates/deploy-iis-stage.yaml` — stage wrapper currently tying `healthScheme` to requested `bindingProtocol`; update for `auto` and effective-protocol behavior.
- `eng/azure-pipelines.yaml` — pipeline variables and per-environment thumbprint parameters; change default protocol to `auto` and update comments.
- `eng/README.md` — primary IIS deployment documentation; update manual commands, variable table, and HTTPS/certificate guidance.
- `docs/02-getting-started.md` — clarify local HTTP default and link IIS HTTPS behavior to thumbprint configuration.
- `docs/06-configuration.md` — update transport/configuration section so IIS protocol selection is described separately from `dotnet run --urls`.
- `docs/08-mcp-inspector.md` — keep HTTP examples for local use and mention HTTPS URLs only when IIS resolved to HTTPS.
- `docs/09-ide-integration.md` — clarify HTTP transport examples and HTTPS endpoint expectations for deployed IIS.
- `docs/10-troubleshooting.md` — add troubleshooting for unexpectedly HTTP/HTTPS deployments, missing thumbprints, and existing binding behavior.
- `eng/scripts/Common/*.Tests.ps1` or a new nearby Pester test file — follow existing Pester 5 style for deployment-script helper coverage.

**Verification**
1. Run `dotnet build` from the repo root.
2. Run `dotnet test --no-build` from the repo root.
3. Run Pester for deployment scripts, expanding the pipeline path if the new tests live outside `eng/scripts/Common`: `Invoke-Pester -Path .\eng\scripts` or update the Azure pipeline Pester path to include the new test location.
4. Manually validate on a Windows/IIS host or with mocked Pester helpers: no thumbprint and no existing HTTPS cert creates HTTP; provided thumbprint creates HTTPS and assigns the cert; existing HTTPS binding with cert remains HTTPS in auto mode.
5. Confirm deployment health checks use the resolved protocol: HTTP after fallback, HTTPS after thumbprint or existing cert.
6. Review docs for stale claims that IIS always uses HTTPS by default or that a thumbprint is always required.

**Decisions**
- Scope is IIS deployment only; no Kestrel runtime thumbprint loading will be added.
- Existing IIS HTTPS binding with a certificate should keep HTTPS in auto mode even when no new thumbprint is provided.
- Local development and Docker remain HTTP by default.
- Thumbprints can come from the explicit script parameter or `IIS_SSL_CERTIFICATE_THUMBPRINT`; Azure DevOps unresolved literal variables should continue to be treated as unset.
- `auto` is the recommended default; explicit `http` and `https` remain available for intentional overrides.

**Further Considerations**
1. Make sure the health-check scheme consume the resolved protocol, not the requested protocol.
2. Production docs should continue recommending HTTPS with a valid certificate while documenting the requested HTTP fallback for environments without a certificate.