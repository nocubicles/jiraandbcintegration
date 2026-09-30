codeunit 50150 "BCJ Billing Status Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        BCJTestLibrary: Codeunit "BCJ Test Library";
        Assert: Codeunit "Library Assert";
        BillingMgt: Codeunit "BCJ Billing Mgt.";

    // ---------------------------------------------------------------------------------
    // "Billing Status" OnValidate -> legacy flags
    // ---------------------------------------------------------------------------------

    [Test]
    procedure ValidateOpenClearsBothLegacyFlags()
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] The old time-entry page, reports and integrations still read "Is Billable" /
        // "Is Billed". Open means nobody has decided yet, so neither flag may claim the entry is
        // billable or billed - otherwise undecided hours leak into billing runs.
        // [GIVEN] An entry with both legacy flags set
        TimeEntry.Init();
        TimeEntry."Is Billable" := true;
        TimeEntry."Is Billed" := true;
        // [WHEN] Billing Status is validated to Open
        TimeEntry.Validate("Billing Status", "BCJ Billing Status"::Open);
        // [THEN] Both flags are cleared
        Assert.IsFalse(TimeEntry."Is Billable", 'Open status must clear Is Billable');
        Assert.IsFalse(TimeEntry."Is Billed", 'Open status must clear Is Billed');
    end;

    [Test]
    procedure ValidateBillableSetsIsBillableOnly()
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] Billable = to be invoiced but not yet invoiced. Legacy consumers must see it
        // as billable and NOT billed, or it would be skipped by the next invoicing run.
        // [GIVEN] An entry wrongly flagged as billed but not billable
        TimeEntry.Init();
        TimeEntry."Is Billable" := false;
        TimeEntry."Is Billed" := true;
        // [WHEN] Billing Status is validated to Billable
        TimeEntry.Validate("Billing Status", "BCJ Billing Status"::Billable);
        // [THEN] Is Billable is set, Is Billed is cleared
        Assert.IsTrue(TimeEntry."Is Billable", 'Billable status must set Is Billable');
        Assert.IsFalse(TimeEntry."Is Billed", 'Billable status must clear Is Billed');
    end;

    [Test]
    procedure ValidateNotBillableClearsBothLegacyFlags()
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] Not Billable is an explicit decision that the customer is never charged
        // for these hours; legacy consumers must see neither billable nor billed.
        // [GIVEN] An entry with both legacy flags set
        TimeEntry.Init();
        TimeEntry."Is Billable" := true;
        TimeEntry."Is Billed" := true;
        // [WHEN] Billing Status is validated to Not Billable
        TimeEntry.Validate("Billing Status", "BCJ Billing Status"::"Not Billable");
        // [THEN] Both flags are cleared
        Assert.IsFalse(TimeEntry."Is Billable", 'Not Billable status must clear Is Billable');
        Assert.IsFalse(TimeEntry."Is Billed", 'Not Billable status must clear Is Billed');
    end;

    [Test]
    procedure ValidateBilledSetsBothLegacyFlags()
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] Billed hours were billable hours that have been invoiced, so legacy consumers
        // must see both flags - Is Billed alone would make billable-hours totals drop after invoicing.
        // [GIVEN] An entry with no flags set
        TimeEntry.Init();
        TimeEntry."Is Billable" := false;
        TimeEntry."Is Billed" := false;
        // [WHEN] Billing Status is validated to Billed
        TimeEntry.Validate("Billing Status", "BCJ Billing Status"::Billed);
        // [THEN] Both flags are set
        Assert.IsTrue(TimeEntry."Is Billable", 'Billed status must set Is Billable');
        Assert.IsTrue(TimeEntry."Is Billed", 'Billed status must set Is Billed');
    end;

    // ---------------------------------------------------------------------------------
    // GetStatusFromFlags
    // ---------------------------------------------------------------------------------

    [Test]
    procedure GetStatusFromFlagsFollowsTruthTable()
    begin
        // [SCENARIO] Translating the legacy booleans into the new status: once invoiced (Is Billed)
        // the entry is Billed whatever Is Billable says - an invoiced hour must never be re-billed.
        // Only billable-not-billed is Billable; no flags means undecided (Open), never Not Billable,
        // because the old page had no way to express an explicit "not billable" decision.
        // [WHEN] / [THEN] Each flag combination maps as agreed
        Assert.AreEqual("BCJ Billing Status"::Open, BillingMgt.GetStatusFromFlags(false, false), 'No flags must map to Open');
        Assert.AreEqual("BCJ Billing Status"::Billable, BillingMgt.GetStatusFromFlags(true, false), 'Is Billable only must map to Billable');
        Assert.AreEqual("BCJ Billing Status"::Billed, BillingMgt.GetStatusFromFlags(false, true), 'Is Billed without Is Billable must still map to Billed');
        Assert.AreEqual("BCJ Billing Status"::Billed, BillingMgt.GetStatusFromFlags(true, true), 'Both flags must map to Billed');
    end;

    // ---------------------------------------------------------------------------------
    // SetBillingStatus
    // ---------------------------------------------------------------------------------

    [Test]
    procedure SetBillingStatusChangesOnlyEntriesWithinFilters()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Stem: Code[13];
        JobNo: Code[20];
        Changed: Integer;
    begin
        // [SCENARIO] The user marks a date range as billable. Entries outside that range belong to
        // another billing period; touching them would bill hours the customer was not quoted for.
        // [GIVEN] Three open entries on consecutive dates for one project
        Stem := BCJTestLibrary.NewStem();
        JobNo := CreateJobWithTask(Stem);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-1', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 1, "BCJ Billing Status"::Open);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-2', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate() + 1, 2, "BCJ Billing Status"::Open);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-3', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate() + 2, 3, "BCJ Billing Status"::Open);
        // [WHEN] SetBillingStatus(Billable) on the first two dates only
        TimeEntry.Reset();
        TimeEntry.SetRange("Project No.", JobNo);
        TimeEntry.SetRange("Posting Date", BCJTestLibrary.BaseDate(), BCJTestLibrary.BaseDate() + 1);
        Changed := BillingMgt.SetBillingStatus(TimeEntry, "BCJ Billing Status"::Billable);
        // [THEN] Two entries changed, the third is still Open
        Assert.AreEqual(2, Changed, 'SetBillingStatus must return the number of filtered entries it changed');
        Assert.AreEqual("BCJ Billing Status"::Billable, GetStatus(Stem + '-1'), 'Entry inside the date filter must become Billable');
        Assert.AreEqual("BCJ Billing Status"::Billable, GetStatus(Stem + '-2'), 'Entry inside the date filter must become Billable');
        Assert.AreEqual("BCJ Billing Status"::Open, GetStatus(Stem + '-3'), 'Entry outside the date filter must stay Open');
    end;

    [Test]
    procedure SetBillingStatusOnEmptySetReturnsZero()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Stem: Code[13];
        Changed: Integer;
    begin
        // [SCENARIO] Pressing "Mark as Billable" on a filter that matches nothing is a normal user
        // situation (e.g. an empty period); it must be a no-op, not an error.
        // [GIVEN] A filter on a project number that has no entries
        Stem := BCJTestLibrary.NewStem();
        TimeEntry.SetRange("Project No.", Stem + 'NONE');
        // [WHEN] SetBillingStatus is called
        Changed := BillingMgt.SetBillingStatus(TimeEntry, "BCJ Billing Status"::Billed);
        // [THEN] Zero entries changed
        Assert.AreEqual(0, Changed, 'An empty filter result must return 0 changed entries');
    end;


    [Test]
    procedure SetBillingStatusBillableMovesOnlyOpenHoursAndCountsChangedEntries()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Stem: Code[13];
        JobNo: Code[20];
        Changed: Integer;
    begin
        // [SCENARIO] Mark Billable is an hour move, Open -> manual Billable (contract table in
        // "Codeunit 50103"). An entry already Billable has no Open hours to move, and an entry the
        // consultant wrote off stays written off - Mark Billable does not silently reverse a
        // write-off; that is what Mark Open is for. The returned count is shown as "N entries
        // updated", so only entries whose buckets actually changed may be counted.
        // [GIVEN] An Open entry, a Billable entry and a Not Billable entry
        Stem := BCJTestLibrary.NewStem();
        JobNo := CreateJobWithTask(Stem);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-1', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 1, "BCJ Billing Status"::Open);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-2', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 2, "BCJ Billing Status"::Billable);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-3', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 3, "BCJ Billing Status"::"Not Billable");
        // [WHEN] SetBillingStatus(Billable) on the whole project
        TimeEntry.Reset();
        TimeEntry.SetRange("Project No.", JobNo);
        Changed := BillingMgt.SetBillingStatus(TimeEntry, "BCJ Billing Status"::Billable);
        // [THEN] Only the Open entry changed; the write-off stands
        Assert.AreEqual(1, Changed, 'Only the entry that had Open hours to move may be counted as changed');
        BCJTestLibrary.AssertBuckets(Stem + '-1', 0, 0, 1, 0, 0, 'The Open hour must move to Billable');
        BCJTestLibrary.AssertBuckets(Stem + '-2', 0, 0, 2, 0, 0, 'An already Billable entry must stay exactly as it was');
        BCJTestLibrary.AssertBuckets(Stem + '-3', 0, 0, 0, 3, 0, 'Mark Billable must not reverse a write-off - it moves Open hours only');
        TimeEntry.Reset();
        TimeEntry.SetRange("Project No.", JobNo);
        BCJTestLibrary.AssertInvariant(TimeEntry, 'After Mark Billable');
    end;

    [Test]
    procedure SetBillingStatusPersistsStatusAndLegacyFlags()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Stored: Record "BCJ Project Time Entry";
        Stem: Code[13];
        JobNo: Code[20];
    begin
        // [SCENARIO] The old time-entry page and existing reports read Is Billable / Is Billed, so
        // the derived Billing Status and the legacy flags must be stored with every move:
        // Billable -> Is Billable only, Billed -> both. Mark Not Billable afterwards writes off
        // Open hours only, so an invoiced entry is not touched by it - an invoice exists.
        // [GIVEN] One open entry with no flags
        Stem := BCJTestLibrary.NewStem();
        JobNo := CreateJobWithTask(Stem);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-1', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 1, "BCJ Billing Status"::Open);
        TimeEntry.Reset();
        TimeEntry.SetRange("Project No.", JobNo);
        // [WHEN] Marked Billable
        BillingMgt.SetBillingStatus(TimeEntry, "BCJ Billing Status"::Billable);
        // [THEN] Stored Billable with Is Billable only
        Stored.Get(Stem + '-1', 'I-' + Stem + '-1');
        Assert.AreEqual("BCJ Billing Status"::Billable, Stored."Billing Status", 'Billable status must be persisted');
        Assert.IsTrue(Stored."Is Billable", 'Persisted Billable entry must have Is Billable set');
        Assert.IsFalse(Stored."Is Billed", 'Persisted Billable entry must not have Is Billed set');
        // [WHEN] Marked Billed
        BillingMgt.SetBillingStatus(TimeEntry, "BCJ Billing Status"::Billed);
        // [THEN] Stored Billed with both flags set
        Stored.Get(Stem + '-1', 'I-' + Stem + '-1');
        Assert.AreEqual("BCJ Billing Status"::Billed, Stored."Billing Status", 'Billed status must be persisted');
        Assert.IsTrue(Stored."Is Billable", 'Persisted Billed entry must have Is Billable set');
        Assert.IsTrue(Stored."Is Billed", 'Persisted Billed entry must have Is Billed set');
        BCJTestLibrary.AssertBuckets(Stem + '-1', 0, 0, 0, 0, 1, 'The billed hour must sit in Billed');
        // [WHEN] Then marked Not Billable
        Assert.AreEqual(0, BillingMgt.SetBillingStatus(TimeEntry, "BCJ Billing Status"::"Not Billable"), 'An invoiced entry has no Open hours to write off, so nothing may be counted as changed');
        // [THEN] Still Billed
        Stored.Get(Stem + '-1', 'I-' + Stem + '-1');
        Assert.AreEqual("BCJ Billing Status"::Billed, Stored."Billing Status", 'Mark Not Billable must never write off invoiced hours');
        BCJTestLibrary.AssertBuckets(Stem + '-1', 0, 0, 0, 0, 1, 'Mark Not Billable must leave invoiced hours in Billed');
    end;

    [Test]
    procedure MarkBilledBillsOnlyBillableHours()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
        InReviewReview: Record "BCJ Customer Review";
        Stem: Code[13];
        JobNo: Code[20];
        Changed: Integer;
    begin
        // [SCENARIO] Business flow step 6: "Mark Billed bills only Billable hours, never Open
        // ones". Marking a whole project Billed after the invoice run must invoice what was
        // approved (by a review or by hand) and nothing else - undecided hours and hours still
        // with the customer were not on the invoice, and billing them would make them vanish
        // from every later review and invoice.
        // [GIVEN] E1 4 h of which a review approved 2 (2 Open), E2 3 h manual Billable,
        // E3 1 h Open, E4 2 h in a sent review
        Stem := BCJTestLibrary.NewStem();
        JobNo := CreateJobWithTask(Stem);
        BCJTestLibrary.EnsureSetup('https://review.example.com');
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-1', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 4, "BCJ Billing Status"::Open);
        BCJTestLibrary.ReviewSingleEntry(Stem + '-1', 4, 2, Review);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-2', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 3, "BCJ Billing Status"::Billable);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-3', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 1, "BCJ Billing Status"::Open);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-4', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 2, "BCJ Billing Status"::Open);
        TimeEntry.Reset();
        TimeEntry.SetRange("Jira ID", Stem + '-4');
        BCJTestLibrary.CreateDraftReview(TimeEntry, InReviewReview);
        BCJTestLibrary.SendDraftReview(InReviewReview);
        BCJTestLibrary.AssertBuckets(Stem + '-1', 2, 0, 2, 0, 0, 'Fixture: E1 must be 2 approved + 2 Open');
        // [WHEN] The whole project is marked Billed
        TimeEntry.Reset();
        TimeEntry.SetRange("Project No.", JobNo);
        Changed := BillingMgt.SetBillingStatus(TimeEntry, "BCJ Billing Status"::Billed);
        // [THEN] Only Billable hours were billed
        Assert.AreEqual(2, Changed, 'Only the two entries holding Billable hours may be counted as changed');
        BCJTestLibrary.AssertBuckets(Stem + '-1', 2, 0, 0, 0, 2, 'The review-approved hours must be billed and the Open remainder must stay Open');
        BCJTestLibrary.AssertBuckets(Stem + '-2', 0, 0, 0, 0, 3, 'Manually approved hours must be billed');
        BCJTestLibrary.AssertBuckets(Stem + '-3', 1, 0, 0, 0, 0, 'Open hours must never be billed by Mark Billed');
        BCJTestLibrary.AssertBuckets(Stem + '-4', 0, 2, 0, 0, 0, 'Hours still with the customer must never be billed by Mark Billed');
        BCJTestLibrary.AssertStatus(Stem + '-1', "BCJ Billing Status"::Open, 'An entry with Open hours left shows Open, whatever else it holds');
        BCJTestLibrary.AssertInvariant(TimeEntry, 'After Mark Billed');
    end;

    [Test]
    procedure MarkNotBillableWritesOffOnlyOpenHours()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
        DraftReview: Record "BCJ Customer Review";
        Stem: Code[13];
        JobNo: Code[20];
        Changed: Integer;
    begin
        // [SCENARIO] Writing off is a decision about undecided hours only. Hours reserved in a
        // review belong to that review until it is sent, answered or cancelled, and hours the
        // customer approved can only be taken back by reopening that review (business flow
        // step 7) - so neither may be written off from the overview.
        // [GIVEN] E1 4 h with 2 approved by a review and 2 Open, E2 3 h in a draft review,
        // E3 1 h Open, E4 2 h manual Billable
        Stem := BCJTestLibrary.NewStem();
        JobNo := CreateJobWithTask(Stem);
        BCJTestLibrary.EnsureSetup('https://review.example.com');
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-1', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 4, "BCJ Billing Status"::Open);
        BCJTestLibrary.ReviewSingleEntry(Stem + '-1', 4, 2, Review);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-2', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 3, "BCJ Billing Status"::Open);
        TimeEntry.Reset();
        TimeEntry.SetRange("Jira ID", Stem + '-2');
        BCJTestLibrary.CreateDraftReview(TimeEntry, DraftReview);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-3', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 1, "BCJ Billing Status"::Open);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-4', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 2, "BCJ Billing Status"::Billable);
        // [WHEN] The whole project is marked Not Billable
        TimeEntry.Reset();
        TimeEntry.SetRange("Project No.", JobNo);
        Changed := BillingMgt.SetBillingStatus(TimeEntry, "BCJ Billing Status"::"Not Billable");
        // [THEN] Only Open hours were written off
        Assert.AreEqual(2, Changed, 'Only the two entries holding Open hours may be counted as changed');
        BCJTestLibrary.AssertBuckets(Stem + '-1', 0, 0, 2, 2, 0, 'Only the Open remainder may be written off; the review-approved hours stay Billable');
        BCJTestLibrary.AssertBuckets(Stem + '-2', 0, 3, 0, 0, 0, 'Hours reserved in a draft review must not be written off');
        BCJTestLibrary.AssertBuckets(Stem + '-3', 0, 0, 0, 1, 0, 'Open hours must be written off');
        BCJTestLibrary.AssertBuckets(Stem + '-4', 0, 0, 2, 0, 0, 'Manually approved hours have no Open hours to write off and must stay Billable');
        BCJTestLibrary.AssertInvariant(TimeEntry, 'After Mark Not Billable');
    end;

    [Test]
    procedure MarkOpenReturnsManualDecisionsButNotReviewApprovedHours()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
        DraftReview: Record "BCJ Customer Review";
        Stem: Code[13];
        JobNo: Code[20];
        Changed: Integer;
    begin
        // [SCENARIO] Mark Open undoes the consultant's own overview decisions (manual Billable,
        // manual Not Billable). It must not undo the customer's approval: those hours can only
        // be taken back by reopening their review (business flow step 7), and it must not pull
        // hours out of a review that is being prepared.
        // [GIVEN] E1 3 h manual Billable, E2 2 h manual Not Billable, E3 4 h of which a review
        // approved 2 (2 Open), E4 2 h in a draft review
        Stem := BCJTestLibrary.NewStem();
        JobNo := CreateJobWithTask(Stem);
        BCJTestLibrary.EnsureSetup('https://review.example.com');
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-1', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 3, "BCJ Billing Status"::Billable);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-2', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 2, "BCJ Billing Status"::"Not Billable");
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-3', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 4, "BCJ Billing Status"::Open);
        BCJTestLibrary.ReviewSingleEntry(Stem + '-3', 4, 2, Review);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-4', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 2, "BCJ Billing Status"::Open);
        TimeEntry.Reset();
        TimeEntry.SetRange("Jira ID", Stem + '-4');
        BCJTestLibrary.CreateDraftReview(TimeEntry, DraftReview);
        // [WHEN] The whole project is marked Open
        TimeEntry.Reset();
        TimeEntry.SetRange("Project No.", JobNo);
        Changed := BillingMgt.SetBillingStatus(TimeEntry, "BCJ Billing Status"::Open);
        // [THEN] Only the manual decisions were undone
        Assert.AreEqual(2, Changed, 'Only the entries with manual Billable or manual Not Billable hours may be counted as changed');
        BCJTestLibrary.AssertBuckets(Stem + '-1', 3, 0, 0, 0, 0, 'Manual Billable hours must return to Open');
        BCJTestLibrary.AssertBuckets(Stem + '-2', 2, 0, 0, 0, 0, 'Manual Not Billable hours must return to Open');
        BCJTestLibrary.AssertBuckets(Stem + '-3', 2, 0, 2, 0, 0, 'Hours approved by the customer must stay Billable - only Reopen of the review takes them back');
        BCJTestLibrary.AssertBuckets(Stem + '-4', 0, 2, 0, 0, 0, 'Hours reserved in a draft review must stay in review');
        BCJTestLibrary.AssertStatus(Stem + '-1', "BCJ Billing Status"::Open, 'An entry returned to Open must show Open');
        BCJTestLibrary.AssertInvariant(TimeEntry, 'After Mark Open');
    end;

    [Test]
    procedure MarkOpenOnBilledEntryReturnsItToBillable()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Stored: Record "BCJ Project Time Entry";
        Stem: Code[13];
        JobNo: Code[20];
    begin
        // [SCENARIO] Contract table, NewStatus Open: "Billed -> Billable". Undoing an invoice (the
        // page asks for confirmation first) takes the hours back one step - approved but not
        // invoiced - not all the way back to undecided: the approval itself was never wrong.
        // Mark Open is one move per entry, so a second Mark Open is what returns them to Open.
        // [GIVEN] An entry billed by hand (manual Billable, then Billed)
        Stem := BCJTestLibrary.NewStem();
        JobNo := CreateJobWithTask(Stem);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-1', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 3, "BCJ Billing Status"::Billed);
        // [WHEN] Marked Open
        Assert.AreEqual(1, BCJTestLibrary.MarkEntryById(Stem + '-1', "BCJ Billing Status"::Open), 'Un-billing an entry must count it as changed');
        // [THEN] The hours are Billable again, with the legacy flags following
        BCJTestLibrary.AssertBuckets(Stem + '-1', 0, 0, 3, 0, 0, 'Mark Open on a Billed entry must move Billed back to Billable');
        Stored.Get(Stem + '-1', 'I-' + Stem + '-1');
        Assert.AreEqual("BCJ Billing Status"::Billable, Stored."Billing Status", 'An un-billed entry must show Billable');
        Assert.IsTrue(Stored."Is Billable", 'An un-billed entry must keep Is Billable');
        Assert.IsFalse(Stored."Is Billed", 'An un-billed entry must clear Is Billed');
        // [WHEN] Marked Open again
        BCJTestLibrary.MarkEntryById(Stem + '-1', "BCJ Billing Status"::Open);
        // [THEN] Now the manual Billable hours return to Open
        BCJTestLibrary.AssertBuckets(Stem + '-1', 3, 0, 0, 0, 0, 'A second Mark Open must return the manual Billable hours to Open');
    end;

    [Test]
    procedure SetBillingStatusSentForReviewIsRefused()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Stem: Code[13];
        JobNo: Code[20];
    begin
        // [SCENARIO] Hours only go into review through a customer review (CreateReviews), which
        // is what records which review holds them. A bare status change to Sent for Review would
        // park hours in no review at all, where nothing can ever release them.
        // [GIVEN] An Open entry
        Stem := BCJTestLibrary.NewStem();
        JobNo := CreateJobWithTask(Stem);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-1', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 2, "BCJ Billing Status"::Open);
        TimeEntry.Reset();
        TimeEntry.SetRange("Project No.", JobNo);
        // [WHEN] SetBillingStatus(Sent for Review)
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror BillingMgt.SetBillingStatus(TimeEntry, "BCJ Billing Status"::"Sent for Review");
        // [THEN] Refused and nothing moved
        BCJTestLibrary.AssertBuckets(Stem + '-1', 2, 0, 0, 0, 0, 'A refused Sent for Review must leave the entry fully Open');
    end;

    // ---------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------

    local procedure CreateJobWithTask(Stem: Code[13]): Code[20]
    var
        JobNo: Code[20];
        CustomerNo: Code[20];
    begin
        JobNo := Stem + 'P';
        CustomerNo := Stem + 'C';
        BCJTestLibrary.CreateCustomer(CustomerNo, 'Customer ' + Stem);
        BCJTestLibrary.CreateJob(JobNo, CustomerNo, 'Project ' + Stem);
        BCJTestLibrary.CreateJobTask(JobNo, 'T1', 'Task ' + Stem, '');
        exit(JobNo);
    end;

    local procedure GetStatus(JiraId: Text[50]): Enum "BCJ Billing Status"
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        TimeEntry.Get(JiraId, CopyStr('I-' + JiraId, 1, 50));
        exit(TimeEntry."Billing Status");
    end;
}
