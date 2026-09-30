# Hour allocation contract (v1.2.0.0)

Replaces the per-worklog billing status as the source of truth with hour buckets per worklog, so one Jira
worklog can be partly in review, partly approved and partly unbilled.

## Business flow (from the consultant)

1. Hours are logged in Jira and synced to BC as unbilled (Open).
2. The consultant picks tasks and creates a **Draft** customer review. The draft reserves the Open hours of the
   selected worklogs (In Review), so the same hours cannot go into two drafts.
3. The consultant lowers **Hours to Bill** per task on the draft (directly or with Set Hours to Bill %).
4. **Send**: the hours cut from the review (in review − Hours to Bill) return to **Open** immediately; the review
   becomes Sent and is e-mailed (or its link shared). A sent review is frozen: no Hours to Bill changes.
5. The customer answers. Approved hours become **Billable** (approved, not invoiced); every hour not approved
   returns to **Open**.
6. From the overview the consultant writes off Open hours (**Not Billable**) or keeps them for a next review, and
   marks approved hours **Billed** after invoicing. Mark Billed bills only Billable hours, never Open ones.
7. Hours approved in a review can only be taken back by **Reopen** of that review, not by Mark Open/Not Billable.

Allocation inside a task is always oldest first: order Posting Date, then Jira ID (then Jira Issue Id). Older
hours are kept in review / approved first; the newest hours go back to Open.

## Buckets

Per worklog (table 50100 "BCJ Project Time Entry"), with L = "Time Spent in Hours":

| Bucket | Field | Meaning |
|---|---|---|
| Open | 22 "Open Hours" | unbilled and free: L − all other buckets |
| In Review | 23 "In Review Hours" | reserved by a Draft or Sent review |
| Billable | 20 "Billable Hours" (reused) | approved (by a review or manually), not invoiced |
| Billed | 25 "Billed Hours" | invoiced |
| Not Billable | 24 "Not Billable Hours" | written off |
| (derived) | 26 "Unbilled Hours" | Open + In Review + Billable |

Open + In Review + Billable + Billed + Not Billable = L always (Open may go negative only when Jira shrinks a
worklog below its billed hours; that is flagged, never corrected by un-billing).

All cache fields are Editable = false, stored, and written only by codeunit 50109.

"Billing Status" (field 18) is derived, for display and simple filters, by precedence:
In Review > 0 → Sent for Review; else Open > 0 → Open; else Billable > 0 → Billable; else Billed > 0 → Billed;
else Not Billable. (A worklog with L = 0 and nothing allocated is Open.) Its OnValidate keeps the legacy flags:
"Is Billable" = Billable|Billed, "Is Billed" = Billed.

On insert: Open = Unbilled = L, all other buckets 0, status Open. "Billable Hours" no longer defaults to L.

## New table 50105 "BCJ Time Entry Allocation"

PK ("Jira ID" Text[50], "Jira Issue Id" Text[50], "Review No." Integer). Review No. 0 = the manual row
(decisions made on the overview, migrated history).
Fields: "Project No." Code[20], "Project Task No." Code[20], "Posting Date" Date (copied from the entry),
"Reserved Hours", "In Review Hours", "Billable Hours", "Billed Hours", "Not Billable Hours" (Decimal).
Key ReviewWalk ("Review No.", "Project Task No.", "Posting Date", "Jira ID").
The entry's buckets are the sums of its rows' buckets; Open = L − those sums.
Deleting a time entry deletes its allocation rows (worklog removal in the Jira sync runs the delete trigger).

## Enum / table changes

- Enum 50102 "BCJ Review Status": add value(3; Draft).
- Table 50103 "BCJ Customer Review": new field 10 "Sent On" DateTime. A Draft or Cancelled review may be
  deleted; deleting a Draft releases its hours to Open first.
- Table 50104 "BCJ Customer Review Line": "Hours to Bill" may be changed only while the review is Draft;
  "Approved Hours" only while Sent. "Logged Hours" = the hours in review on that task (caption Hours in Review).

## Codeunit 50109 "BCJ Hour Allocation Mgt." (new)

- `procedure RecalcEntry(var TimeEntry: Record "BCJ Project Time Entry")`
  Sets the cache buckets, Unbilled, Billing Status and legacy flags on the var record from its rows. No Modify.
  |Open| < 0.005 is stored as 0.
- `procedure ReserveOpenHours(var TimeEntry: Record "BCJ Project Time Entry"; ReviewNo: Integer): Decimal`
  Moves all Open hours of the entry into its row for ReviewNo (In Review and Reserved increase), modifies the
  entry, returns the hours moved (0 when nothing is Open).
- `procedure ReleaseExcess(ReviewNo: Integer; ProjectTaskNo: Code[20]; KeepHours: Decimal): Decimal`
  Keeps In Review hours of that review+task up to KeepHours oldest first; the rest returns to Open. Returns the
  hours kept. If KeepHours >= Round(total in review, 0.01) everything is kept (no rounding dust released).
- `procedure ApproveReviewHours(ReviewNo: Integer; ProjectTaskNo: Code[20]; ApprovedHours: Decimal): Decimal`
  Oldest first moves In Review → Billable up to ApprovedHours; every remaining In Review hour of that
  review+task returns to Open. Returns the hours approved (capped by what was in review). Same rounding rule.
- `procedure ReleaseReview(ReviewNo: Integer)`
  All In Review hours of the review return to Open. Billable/Billed untouched.
- `procedure ReReserveReview(ReviewNo: Integer; ProjectTaskNo: Code[20]; TargetHours: Decimal): Decimal`
  For Reopen: moves the review's Billable (not Billed) hours of that task back to In Review, then tops up oldest
  first from each row's entry's Open hours (never beyond that row's Reserved Hours) until In Review + Billed of
  the task in this review reaches TargetHours. Returns the In Review + Billed reached.
- `procedure TrimToLoggedHours(var TimeEntry: Record "BCJ Project Time Entry")`
  Called when a worklog's logged hours change. Growth goes to Open. When allocations exceed L, cut in this
  order until they fit: manual Not Billable → In Review on Draft reviews → In Review on Sent reviews → manual
  Billable → review Billable (newest review first). Never cuts Billed. Recalcs the var record; no Modify.
- `procedure MigrateLegacyEntries()`
  One-time migration from the per-worklog status model, idempotent (entries that already have allocation rows,
  or whose cache was already built, are skipped). With B = old "Billable Hours" clamped to [0, L]:
  - Open → no rows; Open = L.
  - Sent for Review in a review that is still Sent → row for that review: Reserved = L, In Review = the entry's
    oldest-first share of the review line's Hours to Bill; the rest Open.
  - Billable from a review → review row: Reserved = L, Billable = B; L − B → Open.
  - Not Billable from a review (the customer approved nothing on it) → review row with Reserved = L, buckets 0;
    everything Open.
  - Billable without a review → manual row Billable = B; L − B → Open.
  - Not Billable without a review (a deliberate write-off) → manual row Not Billable = L.
  - Billed → Billed = B (review row when it has a review, else manual row); L − B → Open.
  Then every entry gets RecalcEntry and Modify(false). Called from the upgrade codeunit (upgrade tag
  'BCJ-HOURALLOCATION-20261001') and from install when that tag is missing.

## Codeunit 50103 "BCJ Billing Mgt."

`procedure SetBillingStatus(var TimeEntry: Record "BCJ Project Time Entry"; NewStatus: Enum "BCJ Billing Status"): Integer`
keeps its signature; per entry within the filters it performs one hour move on the manual row and returns the
number of entries whose buckets changed. It never touches In Review hours nor review-approved hours.

| NewStatus | Move |
|---|---|
| Billable | Open → manual Billable |
| Not Billable | Open → manual Not Billable |
| Billed | all Billable (manual and review rows) → Billed. Open hours are not billed. |
| Open | manual Billable and manual Not Billable → Open; Billed → Billable (the page asks for confirmation first) |
| Sent for Review | error |

`procedure CountEntriesInReview(var TimeEntry): Integer` counts entries within the filters with In Review ≠ 0.
`SyncStatusFromLegacyFlags` is obsolete (no-op) and no longer called from the overview.

## Codeunit 50107 "BCJ Customer Review Mgt."

- `CreateReviews(var TimeEntry; var TempReview): Integer` (same signature): reserves the Open hours of the entries
  within the filters and marks, one **Draft** review per project (hours are added to an existing Draft of that
  project instead of creating a second one), one line per task; line Logged Hours = the hours reserved on that
  task in this review (rounded 0.01), Hours to Bill = Logged Hours. Setup check before any write. Error when no
  Open hours are selected. Entries with Open = 0 are skipped. Returns the number of reviews created or extended.
- `procedure SendReview(var Review: Record "BCJ Customer Review"): Boolean` (new): review must be Draft. Per line:
  Logged Hours = current In Review hours of that task in this review, Hours to Bill clamped to it,
  ReleaseExcess(Hours to Bill); lines with Hours to Bill 0 are deleted. Refreshes the task snapshot, sets Status
  Sent and Sent On, then tries to e-mail; returns whether an e-mail was sent (no recipient → still Sent).
- `SendReviews(var TempReview)`: Drafts are sent with SendReview; already Sent reviews get the e-mail again.
- `SubmitReview`: unchanged (review must be Sent; 0 ≤ Approved ≤ Hours to Bill).
- `ApplyAnswer`: per line ApproveReviewHours(Approved Hours); Applied Hours = the returned hours.
  Hours not approved return to Open.
- `CancelReview`: Draft or Sent → Cancelled; ReleaseReview.
- `ReopenReview`: Answered → Sent; per line ReReserveReview(Hours to Bill); if any line reaches less than its
  Hours to Bill the reopen errors and nothing changes.
- `GetOpenReviews(var TimeEntry; var TempReview): Integer`: the Draft and Sent reviews holding In Review hours of
  the entries within the filters.
- `SetHoursToBillPct`: Draft only.
- Task snapshot on a line (over all worklogs of the task): Billed = Billed + Billable, Not Billable = Not
  Billable, Not Billed = Open + In Review, Logged = sum of L.

## Codeunit 50104 "BCJ Billing Overview Mgt."

BuildOverview reads the cached buckets: Open, Sent for Review (= In Review), Billable, Not Billable, Billed,
Unbilled, Total = L, on every level. Signatures of BuildOverview, ApplyLineFilter, MarkEntriesForLines,
SetStatusForLine unchanged. The status view on page 50102 filters on bucket fields (Unbilled → "Unbilled Hours"
<> 0, Open → "Open Hours" <> 0, …).

## Web API

API page 50107 excludes Draft reviews (a draft link is "not valid"). No other contract change.
