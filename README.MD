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
| Sent for Review | Sent to the customer for approval, waiting for an answer |
| Billed | Billed to the customer |

**Jira Billing Overview** (page 50102) shows a Customer → Project → Task → Time Entry tree with total, unbilled, open, billable, not billable and billed hours per level. The customer is the project's *Bill-to Customer No.* — set it on each project card once; projects without one are grouped under *(No customer)*. Filter by date (e.g. `cm` or `lm`), customer, project and status (default: *Unbilled* = Open + Billable), select any rows and use *Mark Selected As* to set the status of every time entry under them, within the current filters.

**Jira Time Entry Billing** (page 50103) is a flat, filterable list of the entries with an editable Billing Status and the same mark actions. Views: *Unbilled*, *To Review*, *Ready to Bill*.

Typical month-end flow: open the overview with date filter `lm` → mark internal work *Not Billable* → mark the rest *Billable* → bill the billable hours per customer in the billing software → mark them *Billed*.

The older **Jira Time Entries** page (50100) is unchanged. Its *Is Billable* / *Is Billed* flags are kept in sync with the Billing Status. When the overview opens, entries marked there are picked up: a ticked *Is Billed* always makes the entry Billed; *Is Billable* only promotes entries that are still Open.

### Customer review

Before billing, the customer can be asked which hours may be invoiced:

1. In the **Jira Billing Overview** select customer, project or task rows and use **Send for Customer Review**.
   One **Customer Time Review** is created per project from the *Open* entries under the selection (within
   the current filters), with one line per task and the logged hours. The entries become *Sent for Review*
   and are skipped by *Mark Selected As* until the review is answered or cancelled.
2. The review is e-mailed (standard Email module, scenario *Jira Customer Time Review*) to the project's
   **Bill-to Contact** e-mail, falling back to the bill-to customer's e-mail. The mail lists the tasks and
   links to `<Customer Review Base URL>/review/<token>` (base URL in **Jira Integration Setup**). A project
   without any e-mail still gets its review; send it later from the review card or copy the link.
   **Copy Review Link** on the Jira Billing Overview shows the links of the reviews still waiting for an
   answer under the current line, to send to the customer by hand.
3. The customer opens the link (the small web app in `review-web/`), enters the approved hours per task
   (0 up to the logged hours) with an optional comment, and submits.
4. On submit the answer is applied automatically: the approved hours are allocated to the task's entries
   oldest first and stored in **Billable Hours**. Entries that receive hours become *Billable*, the rest
   *Not Billable*. A partly approved entry keeps its logged hours but only the approved part counts as
   billable in the overview; the remainder shows under *Not Billable*.

**Customer Time Reviews** (page 50104) lists the reviews with logged, approved and applied hours. A review
can be **cancelled** while it waits (entries return to *Open*) or **reopened** after an answer so the
customer can adjust it (entries already *Billed* are left alone).

`review-web/` is a dependency-free Node app that serves the customer page and talks to BC through the
`integrated/jira/v1.0` API pages (`customerReviews`, `customerReviewLines`) with a service-to-service
Entra app. See its README for configuration and deployment.
