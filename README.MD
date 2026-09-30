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

The hours of every Jira worklog are split over five buckets, so one worklog can be partly in a review, partly
approved and partly unbilled (table 50105 *Time Entry Allocation* records which review holds which hours):

| Bucket | Meaning |
|--------|---------|
| Open | Unbilled and free: not in a review, not approved, not written off |
| In Review | Reserved by a draft customer review or waiting for the customer's answer |
| Billable | Approved (by the customer in a review, or by you) and not invoiced yet |
| Billed | Invoiced |
| Not Billable | Written off |

*Unbilled* = Open + In Review + Billable. The **Billing Status** of a worklog is derived from its buckets and says
what it needs next (In Review, else Open, else Billable, else Billed, else Not Billable).

**Jira Billing Overview** (page 50102) shows a Customer → Project → Task → Time Entry tree with the buckets per level.
The customer is the project's *Bill-to Customer No.* — set it on each project card once; projects without one are
grouped under *(No customer)*. Filter by date (e.g. `cm` or `lm`), customer, project and view (default: *Unbilled*),
select any rows and use *Mark Selected As*, within the current filters:

| Action | Moves |
|--------|-------|
| Billable | Open hours → Billable (approve without a customer review) |
| Not Billable | Open hours → Not Billable (write off) |
| Billed | Billable hours → Billed, after invoicing. Open hours are never billed. |
| Open | Billed → Billable; otherwise your own Billable / Not Billable decisions → Open |

Hours in review are never touched by these actions, and hours a customer approved are taken back only by reopening
the review.

**Jira Time Entry Billing** (page 50103) is a flat, filterable list of the worklogs with their buckets and the same
mark actions. Views: *Unbilled*, *In Review*, *To Review*, *Ready to Bill*.

The older **Jira Time Entries** page (50100) keeps its two actions; they now go through the same hour moves
(*Mark as Billed* approves and bills the Open hours).

### Customer review

Before billing, the customer can be asked which hours may be invoiced:

1. In the **Jira Billing Overview** select customer, project or task rows and use **Send for Customer Review**.
   The Open hours under the selection (within the current filters) are reserved in a **draft** Customer Time
   Review per project, one line per task; a project that already has a draft gets the hours added to it. Hours
   in a draft cannot go into another review. Nothing is sent yet and the customer's link does not work yet.
2. On the draft set **Hours to Bill** per task (0 up to the hours in review; it starts at all of them), or for
   every task at once with **Set Hours to Bill %** (e.g. 50). Each line also holds a snapshot of the task's
   whole history: *Logged*, *Billed* (billed or approved), *Not Billable* (written off) and *Not Billed* (the rest).
3. **Send to Customer** sends the draft: per task the hours left out of Hours to Bill go back to **Open** right
   away (the oldest hours stay in review), tasks with 0 hours to bill are dropped, and the review is frozen.
   It is e-mailed (standard Email module, scenario *Jira Customer Time Review*) to the project's **Bill-to
   Contact** e-mail, falling back to the bill-to customer's e-mail; otherwise share the **Review Link**
   (`<Customer Review Base URL>/review/<token>`, base URL in **Jira Integration Setup**) yourself.
   **Resend E-Mail** sends it again. On the overview, **Customer Review** (or choosing the *In Review Hours*
   value) opens the review holding the hours under the current line.
4. The customer opens the link (the small web app in `review-web/`), enters the approved hours per task
   (0 up to the Hours to Bill) with an optional comment, and submits.
5. On submit the approved hours become **Billable**, oldest first, and every hour the customer did not approve
   goes back to **Open**. From there you write them off (*Not Billable*) or put them in a next review.
6. After invoicing, mark the approved hours **Billed** on the overview.

**Customer Time Reviews** (page 50104) lists the reviews. A draft or a sent review can be **cancelled** (its hours
in review return to *Open*), and a draft can be deleted. An answered review can be **reopened** so the customer
can adjust it: the approved hours go back into review (billed hours stay billed); this is refused when the hours
have meanwhile been written off or put in another review.

Upgrading to 1.2 moves existing data into the buckets once: hours a customer did not approve in an earlier review
become Open again, write-offs made by hand stay Not Billable.

`review-web/` is a dependency-free Node app that serves the customer page and talks to BC through the
`integrated/jira/v1.0` API pages (`customerReviews`, `customerReviewLines`) with a service-to-service
Entra app. See its README for configuration and deployment.
