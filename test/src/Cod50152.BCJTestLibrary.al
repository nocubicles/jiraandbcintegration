codeunit 50152 "BCJ Test Library"
{
    // Shared fixture helpers for the bcjiraintegration test suite.
    // Every fixture uses keys derived from a fresh GUID stem, so tests never collide with
    // real synced Jira data in the sandbox or with each other. Nothing is cached between
    // calls - each test builds its own fixtures and the test runner rolls them back.
    //
    // Hour allocation model (tasks/hour-allocation-contract.md): a worklog's hours live in
    // buckets (Open / In Review / Billable / Billed / Not Billable) backed by rows in
    // "BCJ Time Entry Allocation". Fixtures therefore never assign "Billing Status" or a bucket
    // directly - they create an Open worklog exactly as an insert would leave it, and then move
    // hours with the real procedures (SetBillingStatus, CreateReviews, SendReview, SubmitReview).
    // The only exception is CreateLegacyTimeEntry, which deliberately builds pre-migration data.

    var
        Assert: Codeunit "Library Assert";
        BillingMgt: Codeunit "BCJ Billing Mgt.";
        CustomerReviewMgt: Codeunit "BCJ Customer Review Mgt.";
        HourAllocationMgt: Codeunit "BCJ Hour Allocation Mgt.";
        SentForReviewFixtureErr: Label 'Fixture misuse: an entry is put in review with CreateDraftReview, not with CreateTimeEntry.', Locked = true;

    procedure NewStem(): Code[13]
    begin
        // 'T' + 12 hex chars from a fresh GUID: 13 chars, leaves 7 chars of Code[20] for suffixes.
        exit(CopyStr('T' + CopyStr(DelChr(Format(CreateGuid()), '=', '{}-'), 1, 12), 1, 13));
    end;

    procedure BaseDate(): Date
    begin
        exit(DMY2Date(15, 1, 2030));
    end;

    procedure CreateCustomer(CustomerNo: Code[20]; CustomerName: Text[100])
    var
        Customer: Record Customer;
    begin
        if Customer.Get(CustomerNo) then begin
            Customer.Name := CustomerName;
            Customer.Modify(false);
            exit;
        end;
        Customer.Init();
        Customer."No." := CustomerNo;
        Customer.Name := CustomerName;
        Customer.Insert(false);
    end;

    procedure CreateJob(JobNo: Code[20]; BillToCustomerNo: Code[20]; JobDescription: Text[100])
    var
        Job: Record Job;
    begin
        if not Job.Get(JobNo) then begin
            Job.Init();
            Job."No." := JobNo;
            Job.Insert(false);
        end;
        Job.Description := JobDescription;
        // Direct assignment on purpose: validating Bill-to Customer No. pulls in customer
        // posting/contact setup that is irrelevant to the code under test.
        Job."Bill-to Customer No." := BillToCustomerNo;
        Job.Modify(false);
    end;

    procedure CreateJobTask(JobNo: Code[20]; JobTaskNo: Code[20]; TaskDescription: Text[100]; JiraStatus: Code[250])
    var
        JobTask: Record "Job Task";
    begin
        if not JobTask.Get(JobNo, JobTaskNo) then begin
            JobTask.Init();
            JobTask."Job No." := JobNo;
            JobTask."Job Task No." := JobTaskNo;
            JobTask.Insert(false);
        end;
        JobTask.Description := TaskDescription;
        JobTask."BCJ Jira Status" := JiraStatus;
        JobTask.Modify(false);
    end;

    procedure SetJobTaskJiraId(JobNo: Code[20]; JobTaskNo: Code[20]; JiraTaskId: Text[50])
    var
        JobTask: Record "Job Task";
    begin
        // CreateJobTask does not set the Jira issue id - the worklog sync looks the task up by it,
        // so tests that exercise worklogs have to link the two explicitly.
        JobTask.Get(JobNo, JobTaskNo);
        JobTask."BCJ Jira Task Id" := JiraTaskId;
        JobTask.Modify(false);
    end;

    procedure EnsureJobsSetup()
    var
        JobsSetup: Record "Jobs Setup";
    begin
        // The worklog sync reads the Projects setup singleton. A sandbox or a fresh CRONUS may or
        // may not have it, so create it when missing and leave an existing one untouched - its
        // default unit of measure is real configuration a test has no business changing.
        if JobsSetup.Get() then
            exit;
        JobsSetup.Init();
        JobsSetup.Insert(false);
    end;

    // ---------------------------------------------------------------------------------
    // Time entries
    // ---------------------------------------------------------------------------------

    procedure IssueId(JiraId: Text[50]): Text[50]
    begin
        exit(CopyStr('I-' + JiraId, 1, 50));
    end;

    procedure CreateOpenTimeEntry(var TimeEntry: Record "BCJ Project Time Entry"; JiraId: Text[50]; JobNo: Code[20]; JobTaskNo: Code[20]; ResourceNo: Code[20]; PostingDate: Date; Hours: Decimal)
    begin
        // A freshly synced worklog as the contract defines it after insert: every logged hour is
        // Open and Unbilled, every other bucket is 0, status Open, and no allocation rows exist.
        // Insert(false) keeps the fixture independent of the insert trigger, so the cache is set
        // here to exactly what that trigger must produce.
        TimeEntry.Init();
        TimeEntry."Jira ID" := JiraId;
        TimeEntry."Jira Issue Id" := IssueId(JiraId);
        TimeEntry."Project No." := JobNo;
        TimeEntry."Project Task No." := JobTaskNo;
        TimeEntry."BC Resource No." := ResourceNo;
        TimeEntry."Posting Date" := PostingDate;
        TimeEntry."Time Spent in Hours" := Hours;
        TimeEntry."Time Spend Seconds" := Round(Hours * 3600, 1);
        TimeEntry.Comment := CopyStr('Worklog ' + JiraId, 1, MaxStrLen(TimeEntry.Comment));
        TimeEntry."Open Hours" := Hours;
        TimeEntry."Unbilled Hours" := Hours;
        TimeEntry."In Review Hours" := 0;
        TimeEntry."Billable Hours" := 0;
        TimeEntry."Billed Hours" := 0;
        TimeEntry."Not Billable Hours" := 0;
        TimeEntry."Billing Status" := "BCJ Billing Status"::Open;
        TimeEntry."Is Billable" := false;
        TimeEntry."Is Billed" := false;
        TimeEntry.Insert(false);
    end;

    procedure CreateTimeEntry(var TimeEntry: Record "BCJ Project Time Entry"; JiraId: Text[50]; JobNo: Code[20]; JobTaskNo: Code[20]; ResourceNo: Code[20]; PostingDate: Date; Hours: Decimal; Status: Enum "BCJ Billing Status")
    begin
        // An Open worklog, then moved into the requested state with the overview's own actions:
        // Billable = manual Billable, Not Billable = manual write-off, Billed = manual Billable
        // then invoiced. Every hour of the entry ends up in that one bucket.
        CreateOpenTimeEntry(TimeEntry, JiraId, JobNo, JobTaskNo, ResourceNo, PostingDate, Hours);
        case Status of
            "BCJ Billing Status"::Open:
                ;
            "BCJ Billing Status"::Billable:
                MarkEntry(TimeEntry, "BCJ Billing Status"::Billable);
            "BCJ Billing Status"::"Not Billable":
                MarkEntry(TimeEntry, "BCJ Billing Status"::"Not Billable");
            "BCJ Billing Status"::Billed:
                begin
                    MarkEntry(TimeEntry, "BCJ Billing Status"::Billable);
                    MarkEntry(TimeEntry, "BCJ Billing Status"::Billed);
                end;
            "BCJ Billing Status"::"Sent for Review":
                Error(SentForReviewFixtureErr);
        end;
        TimeEntry.Get(TimeEntry."Jira ID", TimeEntry."Jira Issue Id");
    end;

    procedure MarkEntry(var TimeEntry: Record "BCJ Project Time Entry"; NewStatus: Enum "BCJ Billing Status") Changed: Integer
    var
        SingleEntry: Record "BCJ Project Time Entry";
    begin
        // One overview action on exactly this worklog.
        SingleEntry.SetRange("Jira ID", TimeEntry."Jira ID");
        SingleEntry.SetRange("Jira Issue Id", TimeEntry."Jira Issue Id");
        Changed := BillingMgt.SetBillingStatus(SingleEntry, NewStatus);
        TimeEntry.Get(TimeEntry."Jira ID", TimeEntry."Jira Issue Id");
    end;

    procedure MarkEntryById(JiraId: Text[50]; NewStatus: Enum "BCJ Billing Status"): Integer
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        GetEntry(JiraId, TimeEntry);
        exit(MarkEntry(TimeEntry, NewStatus));
    end;

    procedure ChangeLoggedHours(JiraId: Text[50]; NewHours: Decimal)
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // Stands in for the Jira sync rewriting a worklog's duration: the logged hours change and
        // the allocation is fitted to them with the contract's own procedure.
        GetEntry(JiraId, TimeEntry);
        TimeEntry."Time Spent in Hours" := NewHours;
        TimeEntry."Time Spend Seconds" := Round(NewHours * 3600, 1);
        HourAllocationMgt.TrimToLoggedHours(TimeEntry);
        TimeEntry.Modify(false);
    end;

    procedure CreateLegacyTimeEntry(var TimeEntry: Record "BCJ Project Time Entry"; JiraId: Text[50]; JobNo: Code[20]; JobTaskNo: Code[20]; PostingDate: Date; Hours: Decimal; Status: Enum "BCJ Billing Status"; BillableHours: Decimal; ReviewNo: Integer)
    begin
        // Pre-1.2 data, deliberately built by direct assignment: the per-worklog status model
        // with "Billable Hours" as the agreed allocation and "Review No." as the review link,
        // no allocation rows and no bucket cache. Only the migration tests use this.
        TimeEntry.Init();
        TimeEntry."Jira ID" := JiraId;
        TimeEntry."Jira Issue Id" := IssueId(JiraId);
        TimeEntry."Project No." := JobNo;
        TimeEntry."Project Task No." := JobTaskNo;
        TimeEntry."Posting Date" := PostingDate;
        TimeEntry."Time Spent in Hours" := Hours;
        TimeEntry."Time Spend Seconds" := Round(Hours * 3600, 1);
        TimeEntry.Comment := CopyStr('Legacy worklog ' + JiraId, 1, MaxStrLen(TimeEntry.Comment));
        TimeEntry."Billing Status" := Status;
        TimeEntry."Billable Hours" := BillableHours;
        TimeEntry."Review No." := ReviewNo;
        TimeEntry."Is Billable" := Status in ["BCJ Billing Status"::Billable, "BCJ Billing Status"::Billed];
        TimeEntry."Is Billed" := Status = "BCJ Billing Status"::Billed;
        TimeEntry."Open Hours" := 0;
        TimeEntry."In Review Hours" := 0;
        TimeEntry."Not Billable Hours" := 0;
        TimeEntry."Billed Hours" := 0;
        TimeEntry."Unbilled Hours" := 0;
        TimeEntry.Insert(false);
    end;

    procedure CreateLegacyReview(ProjectNo: Code[20]; CustomerNo: Code[20]; Status: Enum "BCJ Review Status"): Integer
    var
        Review: Record "BCJ Customer Review";
    begin
        // A review header as 1.1 left it, inserted without triggers (AutoIncrement assigns the no.).
        Review.Init();
        Review."Project No." := ProjectNo;
        Review."Customer No." := CustomerNo;
        Review.Status := Status;
        Review."Access Token" := CopyStr(DelChr(Format(CreateGuid()), '=', '{}-'), 1, MaxStrLen(Review."Access Token"));
        Review.Insert(false);
        exit(Review."Review No.");
    end;

    procedure CreateLegacyReviewLine(ReviewNo: Integer; TaskNo: Code[20]; LoggedHours: Decimal; HoursToBill: Decimal)
    var
        ReviewLine: Record "BCJ Customer Review Line";
    begin
        ReviewLine.Init();
        ReviewLine."Review No." := ReviewNo;
        ReviewLine."Project Task No." := TaskNo;
        ReviewLine."Logged Hours" := LoggedHours;
        ReviewLine."Hours to Bill" := HoursToBill;
        ReviewLine.Insert(false);
    end;

    procedure GetEntry(JiraId: Text[50]; var TimeEntry: Record "BCJ Project Time Entry")
    begin
        TimeEntry.Get(JiraId, IssueId(JiraId));
    end;

    // ---------------------------------------------------------------------------------
    // Reviews - driven through the real review procedures
    // ---------------------------------------------------------------------------------

    procedure CreateDraftReview(var TimeEntryFilter: Record "BCJ Project Time Entry"; var Review: Record "BCJ Customer Review")
    var
        TempReview: Record "BCJ Customer Review" temporary;
    begin
        Assert.AreEqual(1, CustomerReviewMgt.CreateReviews(TimeEntryFilter, TempReview), 'Fixture: the selected Open hours must produce exactly one draft review');
        TempReview.FindFirst();
        Review.Get(TempReview."Review No.");
    end;

    procedure SendDraftReview(var Review: Record "BCJ Customer Review")
    begin
        Review.Get(Review."Review No.");
        CustomerReviewMgt.SendReview(Review);
        Review.Get(Review."Review No.");
    end;

    procedure SetHoursToBill(ReviewNo: Integer; TaskNo: Code[20]; Hours: Decimal)
    var
        ReviewLine: Record "BCJ Customer Review Line";
    begin
        ReviewLine.Get(ReviewNo, TaskNo);
        ReviewLine.Validate("Hours to Bill", Hours);
        ReviewLine.Modify(true);
    end;

    procedure SetApprovedHours(ReviewNo: Integer; TaskNo: Code[20]; Hours: Decimal)
    var
        ReviewLine: Record "BCJ Customer Review Line";
    begin
        ReviewLine.Get(ReviewNo, TaskNo);
        ReviewLine.Validate("Approved Hours", Hours);
        ReviewLine.Modify(true);
    end;

    procedure SubmitAnswer(var Review: Record "BCJ Customer Review")
    begin
        Review.Get(Review."Review No.");
        CustomerReviewMgt.SubmitReview(Review);
        Review.Get(Review."Review No.");
    end;

    procedure ReviewSingleEntry(JiraId: Text[50]; HoursToBill: Decimal; ApprovedHours: Decimal; var Review: Record "BCJ Customer Review")
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // The whole review cycle on one worklog: draft, ask for HoursToBill, send, the customer
        // approves ApprovedHours. Leaves the review Answered.
        GetEntry(JiraId, TimeEntry);
        TimeEntry.SetRange("Jira ID", TimeEntry."Jira ID");
        TimeEntry.SetRange("Jira Issue Id", TimeEntry."Jira Issue Id");
        CreateDraftReview(TimeEntry, Review);
        SetHoursToBill(Review."Review No.", TimeEntry."Project Task No.", HoursToBill);
        SendDraftReview(Review);
        SetApprovedHours(Review."Review No.", TimeEntry."Project Task No.", ApprovedHours);
        SubmitAnswer(Review);
    end;

    // ---------------------------------------------------------------------------------
    // Bucket assertions
    // ---------------------------------------------------------------------------------

    procedure AssertBuckets(JiraId: Text[50]; OpenHours: Decimal; InReviewHours: Decimal; BillableHours: Decimal; NotBillableHours: Decimal; BilledHours: Decimal; Msg: Text)
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        GetEntry(JiraId, TimeEntry);
        Assert.AreEqual(OpenHours, TimeEntry."Open Hours", Msg + ' (Open Hours)');
        Assert.AreEqual(InReviewHours, TimeEntry."In Review Hours", Msg + ' (In Review Hours)');
        Assert.AreEqual(BillableHours, TimeEntry."Billable Hours", Msg + ' (Billable Hours)');
        Assert.AreEqual(NotBillableHours, TimeEntry."Not Billable Hours", Msg + ' (Not Billable Hours)');
        Assert.AreEqual(BilledHours, TimeEntry."Billed Hours", Msg + ' (Billed Hours)');
        Assert.AreEqual(OpenHours + InReviewHours + BillableHours, TimeEntry."Unbilled Hours", Msg + ' (Unbilled Hours must be Open + In Review + Billable)');
    end;

    procedure AssertStatus(JiraId: Text[50]; ExpectedStatus: Enum "BCJ Billing Status"; Msg: Text)
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        GetEntry(JiraId, TimeEntry);
        Assert.AreEqual(ExpectedStatus, TimeEntry."Billing Status", Msg + ' (derived Billing Status)');
    end;

    procedure AssertRow(JiraId: Text[50]; ReviewNo: Integer; InReviewHours: Decimal; BillableHours: Decimal; NotBillableHours: Decimal; BilledHours: Decimal; Msg: Text)
    var
        Allocation: Record "BCJ Time Entry Allocation";
    begin
        Assert.IsTrue(Allocation.Get(JiraId, IssueId(JiraId), ReviewNo), Msg + ' (the allocation row must exist)');
        Assert.AreEqual(InReviewHours, Allocation."In Review Hours", Msg + ' (row In Review Hours)');
        Assert.AreEqual(BillableHours, Allocation."Billable Hours", Msg + ' (row Billable Hours)');
        Assert.AreEqual(NotBillableHours, Allocation."Not Billable Hours", Msg + ' (row Not Billable Hours)');
        Assert.AreEqual(BilledHours, Allocation."Billed Hours", Msg + ' (row Billed Hours)');
    end;

    procedure AssertRowHoldsNoHours(JiraId: Text[50]; ReviewNo: Integer; Msg: Text)
    var
        Allocation: Record "BCJ Time Entry Allocation";
    begin
        // A row emptied by a cut may be kept or deleted - the contract does not say - so an
        // absent row counts as holding nothing.
        if not Allocation.Get(JiraId, IssueId(JiraId), ReviewNo) then
            exit;
        Assert.AreEqual(0, Allocation."In Review Hours", Msg + ' (row In Review Hours)');
        Assert.AreEqual(0, Allocation."Billable Hours", Msg + ' (row Billable Hours)');
        Assert.AreEqual(0, Allocation."Not Billable Hours", Msg + ' (row Not Billable Hours)');
        Assert.AreEqual(0, Allocation."Billed Hours", Msg + ' (row Billed Hours)');
    end;

    procedure CountRows(JiraId: Text[50]): Integer
    var
        Allocation: Record "BCJ Time Entry Allocation";
    begin
        Allocation.SetRange("Jira ID", JiraId);
        Allocation.SetRange("Jira Issue Id", IssueId(JiraId));
        exit(Allocation.Count());
    end;

    procedure AssertInvariant(var TimeEntryFilter: Record "BCJ Project Time Entry"; Context: Text)
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Allocation: Record "BCJ Time Entry Allocation";
        Msg: Text;
    begin
        // The invariant the whole model rests on, checked on every entry of the selection:
        // the five buckets add up to the logged hours, Unbilled is Open + In Review + Billable,
        // and the cached buckets are exactly the sums of the entry's allocation rows.
        TimeEntry.CopyFilters(TimeEntryFilter);
        if not TimeEntry.FindSet() then
            exit;
        repeat
            Msg := StrSubstNo('%1 - worklog %2', Context, TimeEntry."Jira ID");
            Assert.AreNearlyEqual(
              TimeEntry."Time Spent in Hours",
              TimeEntry."Open Hours" + TimeEntry."In Review Hours" + TimeEntry."Billable Hours" + TimeEntry."Billed Hours" + TimeEntry."Not Billable Hours",
              0.005,
              Msg + ': Open + In Review + Billable + Billed + Not Billable must equal the logged hours');
            Assert.AreEqual(
              TimeEntry."Open Hours" + TimeEntry."In Review Hours" + TimeEntry."Billable Hours",
              TimeEntry."Unbilled Hours",
              Msg + ': Unbilled Hours must be Open + In Review + Billable');
            Allocation.Reset();
            Allocation.SetRange("Jira ID", TimeEntry."Jira ID");
            Allocation.SetRange("Jira Issue Id", TimeEntry."Jira Issue Id");
            Allocation.CalcSums("In Review Hours", "Billable Hours", "Billed Hours", "Not Billable Hours");
            Assert.AreEqual(Allocation."In Review Hours", TimeEntry."In Review Hours", Msg + ': cached In Review Hours must be the sum of the allocation rows');
            Assert.AreEqual(Allocation."Billable Hours", TimeEntry."Billable Hours", Msg + ': cached Billable Hours must be the sum of the allocation rows');
            Assert.AreEqual(Allocation."Billed Hours", TimeEntry."Billed Hours", Msg + ': cached Billed Hours must be the sum of the allocation rows');
            Assert.AreEqual(Allocation."Not Billable Hours", TimeEntry."Not Billable Hours", Msg + ': cached Not Billable Hours must be the sum of the allocation rows');
        until TimeEntry.Next() = 0;
    end;

    procedure SetLegacyFlags(var TimeEntry: Record "BCJ Project Time Entry"; IsBillable: Boolean; IsBilled: Boolean)
    begin
        TimeEntry.Get(TimeEntry."Jira ID", TimeEntry."Jira Issue Id");
        TimeEntry."Is Billable" := IsBillable;
        TimeEntry."Is Billed" := IsBilled;
        TimeEntry.Modify(false);
    end;

    // ---------------------------------------------------------------------------------
    // Setup and parties
    // ---------------------------------------------------------------------------------

    procedure EnsureSetup(BaseUrl: Text[250])
    var
        JiraIntegrationSetup: Record "BCJ Jira Integration Setup";
    begin
        // The setup singleton may or may not exist in a sandbox and must never be left with a
        // stale review base URL from another test, so this is insert-or-update, never cached.
        if not JiraIntegrationSetup.Get() then begin
            JiraIntegrationSetup.Init();
            JiraIntegrationSetup.PK := 0;
            JiraIntegrationSetup.Insert(false);
        end;
        JiraIntegrationSetup."Review Base URL" := BaseUrl;
        JiraIntegrationSetup.Modify(false);
    end;

    procedure CreateContact(ContactNo: Code[20]; Email: Text[80])
    var
        Contact: Record Contact;
    begin
        // Insert(false)/Modify(false) on purpose: a validated contact pulls in business relations,
        // salutation and marketing setup that the review mail code never looks at.
        if Contact.Get(ContactNo) then begin
            Contact."E-Mail" := Email;
            Contact.Modify(false);
            exit;
        end;
        Contact.Init();
        Contact."No." := ContactNo;
        Contact.Name := CopyStr('Contact ' + ContactNo, 1, MaxStrLen(Contact.Name));
        Contact."E-Mail" := Email;
        Contact.Insert(false);
    end;

    procedure SetJobBillToContact(JobNo: Code[20]; ContactNo: Code[20])
    var
        Job: Record Job;
    begin
        // Direct assignment on purpose: validating Bill-to Contact No. resolves contact business
        // relations and can overwrite the bill-to customer, which the fixture has already chosen.
        Job.Get(JobNo);
        Job."Bill-to Contact No." := ContactNo;
        Job.Modify(false);
    end;

    procedure SetCustomerEmail(CustomerNo: Code[20]; Email: Text[80])
    var
        Customer: Record Customer;
    begin
        Customer.Get(CustomerNo);
        Customer."E-Mail" := Email;
        Customer.Modify(false);
    end;
}
