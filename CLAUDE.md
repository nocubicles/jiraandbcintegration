# bcjiraintegration

Jira → Business Central time-entry sync (PTE, publisher integrated.ee, app id f5cc8010-9fee-4668-beaa-f8ec318f3e1b).

## Layout
- `app/` main extension (ID range 50100-50149), `test/` test app (50150-50199).

## DEV sandbox
- Tenant `7e6efb3b-5060-4666-aee5-ffe6f3cb3644` (Integrated Technologies), environment `sandbox` (BC 28.4).
- Loop: build → publish app → publish test → `al_run_tests 50150` / `50151`.
- Republishing the main app uninstalls the dev-published test app — republish the test app after it (tests then show as "skipped" until you do).
- The `al_publish` MCP tool may report failure without details; use `al publishapp <file> --environmentname sandbox --environmenttype Sandbox --tenant <tenant>` to see the server message. A rebuild is needed to get a new package id before re-publishing.
- Compile the test app with the CLI: `al compile /project:test /packagecachepath:test\.alpackages` (copy the freshly built main .app into `test/.alpackages` first).

## Production
- Same tenant, environment `Production`, company "Integrated Technologies OÜ" (id `7695d01d-d042-f111-a820-7ced8d71cbf2`). The app is installed as a PTE via Extension Management upload, never dev-published.
- Deploy: `bash deploy-prod.sh` (automation API `extensionUpload`, schema sync mode Add, polls `extensionDeploymentStatus`). Takes ~6 minutes. Confirm with the user before running it.
