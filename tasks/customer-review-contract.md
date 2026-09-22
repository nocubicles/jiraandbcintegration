# Customer Time Review — design contract (bcjiraintegration)

Decisions: one review per Project (Job); auto-apply on customer submit with consultant Reopen; review numbering Integer AutoIncrement; project without contact email -> review created, mail skipped; multi-row selection collected via Marks; SetBillingStatus skips "Sent for Review"; entry keeps logged hours, new "Billable Hours" carries allocation.

Assumptions: Job."Bill-to Contact No." -> Contact."E-Mail", fallback Customer."E-Mail" of Job."Bill-to Customer No.". Web app is trusted (S2S). Multiple open reviews per project allowed. Runtime 12.1 OK. Version bump minor. Cod50101 (job journal transfer) untouched.

## 1. Objects
- table 50103 "BCJ Customer Review"
- table 50104 "BCJ Customer Review Line"
- enum 50102 "BCJ Review Status"
- enumextension 50100 "BCJ Email Scenario" extends "Email Scenario" (value 50100 "BCJ Customer Time Review")
- codeunit 50107 "BCJ Customer Review Mgt."
- codeunit 50108 "BCJ Review Mail"
- page 50104 "BCJ Customer Reviews" (List), page 50105 "BCJ Customer Review" (Card), page 50106 "BCJ Customer Review Subform"
- page 50107 "BCJ Customer Review API", page 50108 "BCJ Cust. Review Line API"

## 2. Data model
Enum 50100 "BCJ Billing Status": value(4; "Sent for Review") Caption 'Sent for Review'.

Table 50100 "BCJ Project Time Entry" additions:
- field 20 "Billable Hours" Decimal (DecimalPlaces 0:2, MinValue 0, Editable false)
- field 21 "Review No." Integer (TableRelation "BCJ Customer Review"."Review No.", ValidateTableRelation = false)
- key ReviewAlloc: "Review No.", "Project Task No.", "Posting Date", "Jira ID"
- OnInsert: if "Billable Hours" = 0 then "Billable Hours" := "Time Spent in Hours"
- "Time Spent in Hours" OnValidate: if status in [Open, "Sent for Review"] then "Billable Hours" := "Time Spent in Hours" else clamp "Billable Hours" to <= "Time Spent in Hours"

Table 50103 "BCJ Customer Review":
- 1 "Review No." Integer AutoIncrement; 2 "Project No." Code[20] (Job); 3 "Customer No." Code[20] snapshot of Job."Bill-to Customer No."; 4 Status enum "BCJ Review Status"; 5 "Access Token" Text[50] = 32 uppercase hex chars (GUID without braces/dashes), unique; 6 "Sent To E-Mail" Text[80]; 7 "E-Mail Sent On" DateTime; 8 "Answered On" DateTime; 9 "Cancelled On" DateTime
- 20 "Logged Hours" FlowField Sum(line "Logged Hours"); 21 "Approved Hours" FlowField Sum; 22 "Applied Hours" FlowField Sum
- keys: PK "Review No."; Token "Access Token"; ProjectStatus "Project No.", Status
- OnDelete: if Status <> Cancelled then Error(CannotDeleteReviewErr) (code 'Dialog'); otherwise delete lines

Table 50104 "BCJ Customer Review Line":
- 1 "Review No." Integer; 2 "Project Task No." Code[20]; 3 "Task Description" Text[100]; 4 "Logged Hours" Decimal; 5 "Approved Hours" Decimal MinValue 0 (OnValidate: < 0 or > Logged Hours -> Error(ApprovedHoursOutOfRangeErr) 'Dialog'); 6 "Customer Comment" Text[250]; 7 "Applied Hours" Decimal; 8 "Entry Count" Integer
- PK "Review No.", "Project Task No."
- OnModify: header TestField(Status, Sent) (code 'TestField'). Internal writes use Modify(false) to bypass.

Enum 50102 "BCJ Review Status": 0 Sent (Caption 'Sent for Review'), 1 Answered, 2 Cancelled.

Table 50101 "BCJ Jira Integration Setup": field 8 "Review Base URL" Text[250].
Table 50102 "BCJ Billing Overview Buffer": field 26 "Sent for Review Hours" Decimal; field 27 "Allocated Hours" Decimal (time-entry lines only, carries Billable Hours).

## 3.1 Codeunit 50107 "BCJ Customer Review Mgt."
procedure CreateReviews(var TimeEntry: Record "BCJ Project Time Entry"; var TempReview: Record "BCJ Customer Review" temporary): Integer
- Iterates TimeEntry as given (honours filters AND marks; must not Reset/Copy/CopyFilters it). Only Open entries are taken; others ignored.
- One review per Project No.; one line per Project Task No.; Logged Hours = sum of Time Spent in Hours of the entries taken; Task Description from Job Task; Entry Count = entries taken.
- Each entry taken: Validate("Billing Status", "Sent for Review"), "Review No." := new review, Modify(true).
- Calls ReviewMail.CheckSetup() FIRST, before any write.
- Errors: NothingToSendErr ('Dialog') when no Open entry in range, nothing created. Blank base URL -> TestField ('TestField'), nothing created.
- Returns number of reviews; TempReview holds a copy of each header.

procedure SendReviews(var TempReview: Record "BCJ Customer Review" temporary): Integer
- Sends the email for every review in TempReview (re-reads real record). Returns emails sent. No recipient -> skipped, no error. Never errors on send failure.

procedure SubmitReview(var Review: Record "BCJ Customer Review")
- Review.TestField(Status, Sent) ('TestField'). Re-validates every line Approved Hours <= Logged Hours (ApprovedHoursOutOfRangeErr, 'Dialog'). Status := Answered; "Answered On" := CurrentDateTime; then ApplyAnswer.

procedure ApplyAnswer(var Review: Record "BCJ Customer Review")
- TestField(Status, Answered). Per line, over entries with "Review No." = review, "Project Task No." = line task, Billing Status = Sent for Review, in key ReviewAlloc order ("Review No.", "Project Task No.", "Posting Date", "Jira ID"):
  Remaining := line."Approved Hours"; per entry: Give := min(Remaining, entry."Time Spent in Hours"); entry."Billable Hours" := Give; Remaining -= Give; entry.Validate("Billing Status", Give > 0 ? Billable : "Not Billable"); entry.Modify(true).
- line."Applied Hours" := Approved - Remaining; line.Modify(false). Leftover is dropped, not an error.

procedure CancelReview(var Review: Record "BCJ Customer Review")
- TestField(Status, Sent). Entries with "Review No." = review AND status Sent for Review -> Open, "Billable Hours" := "Time Spent in Hours", "Review No." := 0. Status := Cancelled; "Cancelled On" := CurrentDateTime.

procedure ReopenReview(var Review: Record "BCJ Customer Review")
- TestField(Status, Answered). Entries with "Review No." = review AND status in [Billable, "Not Billable"] -> Sent for Review, "Billable Hours" := logged. Billed entries untouched. Lines: "Applied Hours" := 0 (Modify(false)); Approved Hours and comments kept. Status := Sent; "Answered On" := 0DT. Mail stamps kept.

procedure FindByToken(AccessToken: Text; var Review: Record "BCJ Customer Review"): Boolean
- false when blank or unknown.

Labels: NothingToSendErr = 'The selected lines contain no open time entries to send for customer review.'; ApprovedHoursOutOfRangeErr = 'The approved hours must be between 0 and %1.'; CannotDeleteReviewErr (table 50103) = 'Only a cancelled customer review can be deleted. Cancel the review first.'

## 3.2 Codeunit 50108 "BCJ Review Mail" (test seam)
procedure CheckSetup()  — setup TestField("Review Base URL") ('TestField').
procedure GetReviewLink(Review: Record "BCJ Customer Review"): Text  — '<base without trailing slash>/review/<Access Token>'. Calls CheckSetup first.
procedure GetRecipientEmail(Review: Record "BCJ Customer Review"): Text[80]  — Job."Bill-to Contact No." -> Contact."E-Mail"; if blank, Customer."E-Mail" of Job."Bill-to Customer No."; '' when neither. Never errors, never writes.
procedure BuildReviewEmail(Review: Record "BCJ Customer Review"; Recipient: Text; var EmailMessage: Codeunit "Email Message")  — builds, does NOT send, no DB write. Subject contains project no.; HTML body has one row per line (Project Task No., Task Description, Logged Hours), a total row, and an <a href> to GetReviewLink. Tests call this and inspect GetSubject/GetBody/GetRecipients(To).
procedure SendReviewEmail(var Review: Record "BCJ Customer Review"): Boolean  — recipient '' -> false without writing. Else Build + Email.Send(msg, "Email Scenario"::"BCJ Customer Time Review"); on success stamp "Sent To E-Mail" and "E-Mail Sent On" (Modify(false)) and true; else false, no stamp, no error. Only procedure touching codeunit Email.

## 3.3 Codeunit 50103 "BCJ Billing Mgt." changes
- SetBillingStatus (signature unchanged): additionally excludes entries with status Sent for Review (same FilterGroup(10) block). They are not changed and not counted.
- SyncStatusFromLegacyFlags: both statements exclude Sent for Review.
- New: procedure CountEntriesInReview(var TimeEntry: Record "BCJ Project Time Entry"): Integer  — entries within TimeEntry filters with status Sent for Review.

## 3.4 Codeunit 50104 "BCJ Billing Overview Mgt." changes
- New: procedure MarkEntriesForLines(var SelectedLine: Record "BCJ Billing Overview Buffer" temporary; var TimeEntryFilter: Record "BCJ Project Time Entry"; var TimeEntry: Record "BCJ Project Time Entry"): Integer  — marks on TimeEntry every entry belonging to any selected line (ApplyLineFilter semantics) within the filters of TimeEntryFilter; de-duplicated; on return TimeEntry is Reset + MarkedOnly(true). Returns distinct count.
- Bucket maths per section 5. BuildOverview signature unchanged.

## 5. Overview hours semantics (L = Time Spent in Hours, B = Billable Hours)
| Status | Total | Open | Sent for Review | Billable | Not Billable | Billed |
| Open | +L | +L | | | | |
| Sent for Review | +L | | +L | | | |
| Billable | +L | | | +B | +(L-B) | |
| Not Billable | +L | | | | +L | |
| Billed | +L | | | | +(L-B) | +B |
Unbilled Hours = Open + Sent for Review + Billable. Invariant: Open + Sent for Review + Billable + Not Billable + Billed = Total, at every tree level.

## 6. API pages
Both: PageType = API; APIPublisher = 'integrated'; APIGroup = 'jira'; APIVersion = 'v1.0'; ODataKeyFields = SystemId; DelayedInsert = true; InsertAllowed = false; DeleteAllowed = false.
- 50107 EntityName 'customerReview' / EntitySetName 'customerReviews', ModifyAllowed = false. Fields: systemId, reviewNo, accessToken, projectNo, projectDescription (Job.Description), customerName (Customer.Name), status, loggedHours, approvedHours, createdOn (SystemCreatedAt), answeredOn. Bound action [ServiceEnabled] procedure submit(var ActionContext: WebServiceActionContext) -> CustomerReviewMgt.SubmitReview.
- 50108 EntityName 'customerReviewLine' / 'customerReviewLines', ModifyAllowed = true. Fields: systemId, reviewNo, taskNo ("Project Task No."), taskDescription, loggedHours, appliedHours (read-only); approvedHours, customerComment (writable).

## 8. Upgrade
Cod50105: procedure GetBillableHoursUpgradeTag(): Code[250] = 'BCJ-BILLABLEHOURS-20260922'. UpgradeBillableHours: entries with "Billable Hours" = 0 and "Time Spent in Hours" <> 0 -> "Billable Hours" := "Time Spent in Hours", Modify(false). Register tag; Cod50106 Install sets the tag.

## 9. Tests
File: test/src/Cod50154.BCJCustomerReviewTests.al (50150-50153 used). Only Library Assert and Any available.
Test library additions in test/src/Cod50152.BCJTestLibrary.al: EnsureSetup(BaseUrl: Text[250]); CreateContact(ContactNo: Code[20]; Email: Text[80]); SetJobBillToContact(JobNo: Code[20]; ContactNo: Code[20]); SetCustomerEmail(CustomerNo: Code[20]; Email: Text[80]); CreateTimeEntry additionally sets "Billable Hours" := Hours (it uses Insert(false), which skips OnInsert).
Error codes: TestField -> 'TestField'; Error(Label) -> 'Dialog'. Never assert on message text or FieldCaption. Negative Approved Hours may be caught by MinValue first: assert on state (value unchanged) only.

Required cases:
Create
1. One project's Open entries -> 1 review Sent, one line per task, Logged Hours = sum per task, Entry Count correct, entries Sent for Review with Review No. set and Billable Hours = logged.
2. Selection spanning two projects -> 2 reviews, entries split correctly.
3. Selection with Billable/Billed/Not Billable entries -> only Open taken, others untouched.
4. No Open entries -> 'Dialog', no review, entries unchanged.
5. Blank Review Base URL -> 'TestField', no review, entries still Open.
6. Access token: 32 chars, non-blank, differs between two reviews created in one call.
7. MarkEntriesForLines over a Customer row and one of its Task rows -> each entry counted once, exactly one review per project.
8. Filters honoured: an Open entry outside the date filter is not included.
Mail (no sending)
9. GetRecipientEmail -> contact email when Bill-to Contact No. resolves to a contact with email.
10. Falls back to Customer."E-Mail" when contact has none / no contact set.
11. '' when neither; SendReviews returns 0, E-Mail Sent On blank, review still exists with status Sent.
12. GetReviewLink = <base>/review/<token>, with and without trailing slash on base.
13. BuildReviewEmail -> To list contains exactly the given address; body contains each Project Task No., the token, and a logged-hours figure. Language-invariant substrings only.
Submit / apply
14. Approved = Logged on every line -> all entries Billable with Billable Hours = logged; review Answered; Answered On set; Applied Hours = Approved Hours.
15. Approved = 0 -> all Not Billable with Billable Hours = 0.
16. Partial: entries 1h (older) + 3h, approved 2.5 -> older Billable 1.0, newer Billable 1.5.
17. Partial zeroing one entry: 2h (older) + 1h, approved 2 -> older Billable 2.0, newer Not Billable 0.
18. Tie-break: same posting date -> allocated in Jira ID order.
19. Submit twice -> 'TestField', statuses unchanged by second call.
20. Submit after cancel -> 'TestField'.
21. Approved > Logged on validate -> rejected, line value unchanged.
22. Line.Validate + Modify(true) after review Answered -> 'TestField'.
23. Entries deleted after sending -> apply allocates what remains, Applied Hours < Approved Hours, no error.
24. Entry hours reduced by re-sync after sending (Validate "Time Spent in Hours") -> allocation capped at new hours.
Cancel / reopen
25. Cancel Sent review -> entries Open, Review No. 0, Billable Hours = logged, review Cancelled with Cancelled On.
26. Cancel where some entries were meanwhile Billed -> Billed entries untouched.
27. Cancel after answered -> 'TestField'.
28. Reopen Answered review -> entries Sent for Review with Billable Hours = logged, Applied Hours 0, status Sent, approved hours preserved; second submit re-applies correctly.
29. Reopen a Sent review -> 'TestField'.
Sync / status interaction
30. SetBillingStatus over range containing Sent for Review entries -> not changed, not counted; CountEntriesInReview returns them.
31. SyncStatusFromLegacyFlags with Is Billed = true on a Sent for Review entry -> status unchanged.
32. Time entry Insert(true) -> Billable Hours = Time Spent in Hours.
33. Validate("Time Spent in Hours") on an Open entry -> Billable Hours follows.
Overview maths
34. Billable entry logged 3 / billable 1.5 -> Total 3, Billable 1.5, Not Billable 1.5, Unbilled 1.5.
35. Billed entry logged 3 / billable 1 -> Total 3, Billed 1, Not Billable 2, Unbilled 0.
36. Sent for Review entry -> Total = logged, Sent for Review Hours = logged, Unbilled includes it.
37. Invariant Open + Sent + Billable + Not Billable + Billed = Total on every tree level of a mixed scenario.

Not tested: page layout, API pages, Email.Send, permission set contents.

## 10. Permission set additions
tabledata/table "BCJ Customer Review" and "BCJ Customer Review Line" (RIMD / X); codeunits "BCJ Customer Review Mgt.", "BCJ Review Mail"; pages "BCJ Customer Reviews", "BCJ Customer Review", "BCJ Customer Review Subform", "BCJ Customer Review API", "BCJ Cust. Review Line API".
