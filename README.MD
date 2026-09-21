This project implements Jira and Business Central integration using Azure Storage Queues.

This will enable the following:

- Sync all projects, issues and issue time entries from Jira to Business Central
- Using the Jira's webhooks it will keep projects, issues and time entries automatically in sync between Jira and Business Central

More information about the project [https://www.integrated.ee/posts/business-central-jira-integration/](https://www.integrated.ee/posts/business-central-jira-integration/)
## Repository layout

- `app/` — the Business Central extension (`bcjiraintegration`)
- `test/` — automated tests (`bcjiraintegration Tests`), depends on Microsoft Library Assert
- `bcandjira/` — legacy Azure Functions app (Azure Storage Queue sync, superseded by the direct Jira API sync in `BCJ Jira SDK`)

## Billing review

Time logged in Jira is reviewed and marked for billing in Business Central.

Every Jira time entry has a **Billing Status**:

| Status | Meaning |
|--------|---------|
| Open | Synced from Jira, not reviewed yet |
| Billable | Reviewed, to be billed to the customer |
| Not Billable | Reviewed, will not be billed (internal work, warranty, ...) |
| Billed | Billed to the customer |

**Jira Billing Overview** (page 50102) shows a Customer → Project → Task → Time Entry tree with total, unbilled, open, billable, not billable and billed hours per level. The customer is the project's *Bill-to Customer No.* — set it on each project card once; projects without one are grouped under *(No customer)*. Filter by date (e.g. `cm` or `lm`), customer, project and status (default: *Unbilled* = Open + Billable), select any rows and use *Mark Selected As* to set the status of every time entry under them, within the current filters.

**Jira Time Entry Billing** (page 50103) is a flat, filterable list of the entries with an editable Billing Status and the same mark actions. Views: *Unbilled*, *To Review*, *Ready to Bill*.

Typical month-end flow: open the overview with date filter `lm` → mark internal work *Not Billable* → mark the rest *Billable* → bill the billable hours per customer in the billing software → mark them *Billed*.

The older **Jira Time Entries** page (50100) is unchanged. Its *Is Billable* / *Is Billed* flags are kept in sync with the Billing Status. When the overview opens, entries marked there are picked up: a ticked *Is Billed* always makes the entry Billed; *Is Billable* only promotes entries that are still Open.
