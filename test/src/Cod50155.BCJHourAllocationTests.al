codeunit 50155 "BCJ Hour Allocation Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    // Hour allocation model (tasks/hour-allocation-contract.md, v1.2.0.0): every worklog's
    // logged hours L live in five buckets - Open, In Review, Billable, Billed, Not Billable -
    // backed by rows in "BCJ Time Entry Allocation" (one per review, Review No. 0 = manual).
    // Open + In Review + Billable + Billed + Not Billable = L always; Open may go negative only
    // when Jira shrinks a worklog below its billed hours. These tests pin the allocation
    // codeunit 50109 and the one-time migration from the per-worklog status model.
    //
    // Fixtures use GUID-stem keys and are rebuilt in every test (never cached): the runner rolls
    // the database back but not codeunit variables.

    var
        BCJTestLibrary: Codeunit "BCJ Test Library";
        Assert: Codeunit "Library Assert";
        HourAllocationMgt: Codeunit "BCJ Hour Allocation Mgt.";
        CustomerReviewMgt: Codeunit "BCJ Customer Review Mgt.";
        BillingMgt: Codeunit "BCJ Billing Mgt.";
        Stem: Code[13];
        CustomerNo: Code[20];
        JobNo: Code[20];

    // ---------------------------------------------------------------------------------
    // RecalcEntry - cache and derived status from the rows
    // ---------------------------------------------------------------------------------

    [Test]
    procedure RecalcEntry_DerivesBillingStatusByPrecedence()
    begin
        // [SCENARIO] "Billing Status" is derived for display and simple filters by precedence:
        // In Review > 0 -> Sent for Review; else Open > 0 -> Open; else Billable > 0 -> Billable;
        // else Billed > 0 -> Billed; else Not Billable; a worklog with L = 0 and nothing allocated
        // is Open. The order answers "what still needs someone's attention first" - hours with
        // the customer, then undecided hours, then approved-but-not-invoiced.
        Initialize();
        // [GIVEN] / [WHEN] / [THEN] In Review 1 + Billable 1 of 3 (Open 1) -> Sent for Review
        AddOpenEntry('S1', 3);
        InsertRow('S1', FakeReviewNo(), 1, 0, 0, 0);
        InsertRow('S1', 0, 0, 1, 0, 0);
        RecalcAndAssert('S1', 1, 1, 1, 0, 0, "BCJ Billing Status"::"Sent for Review", 'In Review wins over everything');
        // Billable 1 of 2 (Open 1) -> Open
        AddOpenEntry('S2', 2);
        InsertRow('S2', 0, 0, 1, 0, 0);
        RecalcAndAssert('S2', 1, 0, 1, 0, 0, "BCJ Billing Status"::Open, 'Open wins over Billable');
        // Billable 1 + Billed 1 of 2 -> Billable
        AddOpenEntry('S3', 2);
        InsertRow('S3', 0, 0, 1, 1, 0);
        RecalcAndAssert('S3', 0, 0, 1, 1, 0, "BCJ Billing Status"::Billable, 'Billable wins over Billed');
        // Billed 1 + Not Billable 1 of 2 -> Billed
        AddOpenEntry('S4', 2);
        InsertRow('S4', 0, 0, 0, 1, 1);
        RecalcAndAssert('S4', 0, 0, 0, 1, 1, "BCJ Billing Status"::Billed, 'Billed wins over Not Billable');
        // Not Billable 2 of 2 -> Not Billable
        AddOpenEntry('S5', 2);
        InsertRow('S5', 0, 0, 0, 0, 2);
        RecalcAndAssert('S5', 0, 0, 0, 0, 2, "BCJ Billing Status"::"Not Billable", 'Only written-off hours means Not Billable');
        // L = 0, no rows -> Open
        AddOpenEntry('S6', 0);
        RecalcAndAssert('S6', 0, 0, 0, 0, 0, "BCJ Billing Status"::Open, 'An empty worklog with nothing allocated is Open');
    end;

    [Test]
    procedure RecalcEntry_KeepsLegacyFlagsInStep()
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] The old time-entry page and reports read Is Billable / Is Billed. The derived
        // status keeps them: Is Billable = Billable|Billed, Is Billed = Billed. A worklog shown as
        // Billable but flagged Is Billed would be skipped by the next invoicing run.
        Initialize();
        // [GIVEN] A worklog whose rows make it Billable, one Billed, one Not Billable
        AddOpenEntry('BL', 2);
        InsertRow('BL', 0, 0, 2, 0, 0);
        AddOpenEntry('BD', 2);
        InsertRow('BD', 0, 0, 0, 2, 0);
        AddOpenEntry('NB', 2);
        InsertRow('NB', 0, 0, 0, 0, 2);
        // [WHEN] / [THEN] RecalcEntry sets the flags accordingly
        GetEntry('BL', TimeEntry);
        TimeEntry."Is Billed" := true;
        HourAllocationMgt.RecalcEntry(TimeEntry);
        Assert.IsTrue(TimeEntry."Is Billable", 'A Billable worklog must have Is Billable set');
        Assert.IsFalse(TimeEntry."Is Billed", 'A Billable worklog must not have Is Billed set');
        GetEntry('BD', TimeEntry);
        HourAllocationMgt.RecalcEntry(TimeEntry);
        Assert.IsTrue(TimeEntry."Is Billable", 'A Billed worklog must have Is Billable set');
        Assert.IsTrue(TimeEntry."Is Billed", 'A Billed worklog must have Is Billed set');
        GetEntry('NB', TimeEntry);
        TimeEntry."Is Billable" := true;
        HourAllocationMgt.RecalcEntry(TimeEntry);
        Assert.IsFalse(TimeEntry."Is Billable", 'A Not Billable worklog must not have Is Billable set');
        Assert.IsFalse(TimeEntry."Is Billed", 'A Not Billable worklog must not have Is Billed set');
    end;

    [Test]
    procedure RecalcEntry_StoresOpenDustAsZeroAndDoesNotModify()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Stored: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] Contract: "|Open| < 0.005 is stored as 0". Seconds-based worklogs leave
        // fractions no one can see at two decimals; a worklog that is 0.996 h approved of 1 h
        // must read as fully approved, not as "Open" because of 0.004 h. RecalcEntry works on the
        // var record only - the caller decides when to write it.
        // [GIVEN] A 1 h worklog with 0.996 h manual Billable
        Initialize();
        AddOpenEntry('E1', 1);
        InsertRow('E1', 0, 0, 0.996, 0, 0);
        // [WHEN] RecalcEntry
        GetEntry('E1', TimeEntry);
        HourAllocationMgt.RecalcEntry(TimeEntry);
        // [THEN] Open is 0 and the worklog is Billable
        Assert.AreEqual(0.0, TimeEntry."Open Hours", 'Open dust below 0.005 h must be stored as 0');
        Assert.AreEqual("BCJ Billing Status"::Billable, TimeEntry."Billing Status", 'A worklog with only dust left Open must not show Open');
        // [THEN] Nothing was written
        GetEntry('E1', Stored);
        Assert.AreEqual(1.0, Stored."Open Hours", 'RecalcEntry must not modify the stored record');
    end;

    // ---------------------------------------------------------------------------------
    // ReserveOpenHours / ReleaseExcess / ApproveReviewHours / ReReserveReview
    // ---------------------------------------------------------------------------------

    [Test]
    procedure ReserveOpenHours_MovesAllOpenHoursOnce()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Allocation: Record "BCJ Time Entry Allocation";
        ReviewNo: Integer;
        Moved: Decimal;
    begin
        // [SCENARIO] Reserving is what makes a draft own its hours: all Open hours of the worklog
        // move into that review's row (In Review and Reserved), and a second reservation finds
        // nothing Open - which is exactly why the same hours cannot go into two drafts.
        // [GIVEN] A 3 h worklog marked Billable by hand, then grown by Jira to 5 h (2 Open), and a draft review header
        Initialize();
        AddOpenEntry('E1', 3);
        BCJTestLibrary.MarkEntryById(JiraId('E1'), "BCJ Billing Status"::Billable);
        BCJTestLibrary.ChangeLoggedHours(JiraId('E1'), 5);
        ReviewNo := BCJTestLibrary.CreateLegacyReview(JobNo, CustomerNo, "BCJ Review Status"::Draft);
        // [WHEN] Its Open hours are reserved
        GetEntry('E1', TimeEntry);
        Moved := HourAllocationMgt.ReserveOpenHours(TimeEntry, ReviewNo);
        // [THEN] The 2 Open hours moved, nothing else
        Assert.AreEqual(2.0, Moved, 'ReserveOpenHours must return the Open hours it moved');
        BCJTestLibrary.AssertBuckets(JiraId('E1'), 0, 2, 3, 0, 0, 'Only the Open hours may be reserved; the entry must be modified');
        Assert.IsTrue(Allocation.Get(JiraId('E1'), BCJTestLibrary.IssueId(JiraId('E1')), ReviewNo), 'The review must get its own allocation row');
        Assert.AreEqual(2.0, Allocation."Reserved Hours", 'Reserved Hours must record what the review took');
        Assert.AreEqual(2.0, Allocation."In Review Hours", 'The reserved hours must be In Review');
        // [WHEN] Reserved a second time
        GetEntry('E1', TimeEntry);
        Moved := HourAllocationMgt.ReserveOpenHours(TimeEntry, ReviewNo);
        // [THEN] Nothing more is reserved
        Assert.AreEqual(0.0, Moved, 'With nothing Open, ReserveOpenHours must return 0');
        BCJTestLibrary.AssertBuckets(JiraId('E1'), 0, 2, 3, 0, 0, 'A second reservation must not reserve anything twice');
    end;

    [Test]
    procedure ReleaseExcess_KeepsOldestFirstAndReturnsKeptHours()
    var
        Review: Record "BCJ Customer Review";
        Kept: Decimal;
    begin
        // [SCENARIO] ReleaseExcess is Send's cut: keep KeepHours of the task in review, oldest
        // first, release the rest to Open, return what was kept. Asking to keep more than is in
        // review keeps everything and returns the total - a request can never create hours.
        // [GIVEN] A draft over 6 h (older) and 4 h (newer)
        Initialize();
        AddOpenEntry('OLD', 6);
        AddOpenEntryOn('NEW', 4, BCJTestLibrary.BaseDate() + 1);
        CreateDraftOverOwnEntries(Review);
        // [WHEN] 20 hours are to be kept
        Kept := HourAllocationMgt.ReleaseExcess(Review."Review No.", 'T1', 20);
        // [THEN] Everything is kept
        Assert.AreEqual(10.0, Kept, 'Keeping more than is in review must keep and return everything');
        BCJTestLibrary.AssertBuckets(JiraId('OLD'), 0, 6, 0, 0, 0, 'Nothing may be released when keeping more than is in review');
        // [WHEN] 5 hours are to be kept
        Kept := HourAllocationMgt.ReleaseExcess(Review."Review No.", 'T1', 5);
        // [THEN] 5 kept on the older worklog, the rest Open
        Assert.AreEqual(5.0, Kept, 'ReleaseExcess must return the hours kept');
        BCJTestLibrary.AssertBuckets(JiraId('OLD'), 1, 5, 0, 0, 0, 'The older worklog must keep 5 hours');
        BCJTestLibrary.AssertBuckets(JiraId('NEW'), 4, 0, 0, 0, 0, 'The newer worklog must be released first');
        AssertOwnInvariant('After ReleaseExcess');
    end;

    [Test]
    procedure ApproveReviewHours_IsCappedByHoursInReview()
    var
        Review: Record "BCJ Customer Review";
        Approved: Decimal;
    begin
        // [SCENARIO] The approval moves In Review -> Billable oldest first and returns what it
        // approved, capped by what was in review: a customer approving more than is left (a
        // worklog shrank or was deleted) must never create Billable hours that were not logged.
        // [GIVEN] A sent review over a 3 h worklog
        Initialize();
        AddOpenEntry('E1', 3);
        CreateDraftOverOwnEntries(Review);
        BCJTestLibrary.SendDraftReview(Review);
        // [WHEN] 5 hours are approved
        Approved := HourAllocationMgt.ApproveReviewHours(Review."Review No.", 'T1', 5);
        // [THEN] 3 approved, all Billable
        Assert.AreEqual(3.0, Approved, 'ApproveReviewHours must return the hours actually approved, capped by what was in review');
        BCJTestLibrary.AssertBuckets(JiraId('E1'), 0, 0, 3, 0, 0, 'All hours in review must be Billable');
    end;

    [Test]
    procedure ApproveReviewHours_PartialReturnsRestToOpen()
    var
        Review: Record "BCJ Customer Review";
        Approved: Decimal;
    begin
        // [SCENARIO] "every remaining In Review hour of that review+task returns to Open" - the
        // part not approved is the consultant's to decide again, inside the same worklog.
        // [GIVEN] A sent review over a 3 h worklog
        Initialize();
        AddOpenEntry('E1', 3);
        CreateDraftOverOwnEntries(Review);
        BCJTestLibrary.SendDraftReview(Review);
        // [WHEN] 1.25 hours are approved
        Approved := HourAllocationMgt.ApproveReviewHours(Review."Review No.", 'T1', 1.25);
        // [THEN] 1.25 Billable, 1.75 Open
        Assert.AreEqual(1.25, Approved, 'ApproveReviewHours must return the approved hours');
        BCJTestLibrary.AssertBuckets(JiraId('E1'), 1.75, 0, 1.25, 0, 0, 'The unapproved part of the worklog must be Open');
        BCJTestLibrary.AssertRow(JiraId('E1'), Review."Review No.", 0, 1.25, 0, 0, 'The approval must sit on the review''s row');
    end;

    [Test]
    procedure ReReserveReview_ReturnsWhatItCouldReach()
    var
        Review: Record "BCJ Customer Review";
        OtherDraft: Record "BCJ Customer Review";
        TimeEntry: Record "BCJ Project Time Entry";
        Reached: Decimal;
    begin
        // [SCENARIO] Reopen needs to know whether the review can hold its Hours to Bill again.
        // ReReserveReview returns In Review + Billed reached for the task: it can only take back
        // its own approved hours and Open hours of its own worklogs - hours meanwhile reserved in
        // another review are not available, so the returned figure falls short.
        // [GIVEN] A 4 h worklog, asked 4, approved 1; its 3 Open hours then reserved in another draft
        Initialize();
        AddOpenEntry('E1', 4);
        BCJTestLibrary.ReviewSingleEntry(JiraId('E1'), 4, 1, Review);
        FilterOwnProjects(TimeEntry);
        BCJTestLibrary.CreateDraftReview(TimeEntry, OtherDraft);
        // [WHEN] The answered review tries to re-reserve 4
        Reached := HourAllocationMgt.ReReserveReview(Review."Review No.", 'T1', 4);
        // [THEN] Only its own approved hour is reachable
        Assert.AreEqual(1.0, Reached, 'ReReserveReview must return only the hours it could actually bring back into review');
        BCJTestLibrary.AssertRow(JiraId('E1'), OtherDraft."Review No.", 3, 0, 0, 0, 'Hours reserved in another review must never be taken by ReReserveReview');
    end;

    // ---------------------------------------------------------------------------------
    // TrimToLoggedHours - Jira changes a worklog's duration
    // ---------------------------------------------------------------------------------

    [Test]
    procedure TrimToLoggedHours_GrowthGoesToOpen()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Stored: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
    begin
        // [SCENARIO] A consultant adds time to a worklog in Jira. The extra hours are new and
        // undecided, so they go to Open - never into the review or the approval that the earlier
        // hours were part of. TrimToLoggedHours recalculates the var record only; the sync writes it.
        // [GIVEN] A 2 h worklog reserved in a draft review
        Initialize();
        AddOpenEntry('E1', 2);
        CreateDraftOverOwnEntries(Review);
        // [WHEN] Jira grows it to 3 h
        GetEntry('E1', TimeEntry);
        TimeEntry."Time Spent in Hours" := 3;
        HourAllocationMgt.TrimToLoggedHours(TimeEntry);
        // [THEN] The extra hour is Open on the var record, the reservation is unchanged
        Assert.AreEqual(1.0, TimeEntry."Open Hours", 'Growth must go to Open');
        Assert.AreEqual(2.0, TimeEntry."In Review Hours", 'Growth must not change the hours in review');
        Assert.AreEqual(3.0, TimeEntry."Unbilled Hours", 'Unbilled must follow the grown worklog');
        GetEntry('E1', Stored);
        Assert.AreEqual(0.0, Stored."Open Hours", 'TrimToLoggedHours must not modify the stored record');
    end;

    [Test]
    procedure TrimToLoggedHours_CutsInContractOrder()
    var
        SentReview: Record "BCJ Customer Review";
        DraftReview: Record "BCJ Customer Review";
        FirstApproval: Record "BCJ Customer Review";
        SecondApproval: Record "BCJ Customer Review";
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] When Jira shrinks a worklog below what is allocated, hours are taken back in
        // the order that hurts least: manual write-off first (nothing lost), then a draft review
        // (not yet shown to anyone), then a sent review (the customer sees fewer hours), then a
        // manual approval, then a customer approval - and never an invoiced hour.
        // [GIVEN] A 10 h worklog holding: Billed 2 (review 1), review-approved Billable 1
        // (review 2), manual Billable 1, 3 in a sent review, 2 in a draft review, manual Not Billable 1
        Initialize();
        AddOpenEntry('E1', 2);
        BCJTestLibrary.ReviewSingleEntry(JiraId('E1'), 2, 2, FirstApproval);
        BCJTestLibrary.MarkEntryById(JiraId('E1'), "BCJ Billing Status"::Billed);
        BCJTestLibrary.ChangeLoggedHours(JiraId('E1'), 3);
        BCJTestLibrary.ReviewSingleEntry(JiraId('E1'), 1, 1, SecondApproval);
        BCJTestLibrary.ChangeLoggedHours(JiraId('E1'), 4);
        BCJTestLibrary.MarkEntryById(JiraId('E1'), "BCJ Billing Status"::Billable);
        BCJTestLibrary.ChangeLoggedHours(JiraId('E1'), 7);
        FilterOwnProjects(TimeEntry);
        BCJTestLibrary.CreateDraftReview(TimeEntry, SentReview);
        BCJTestLibrary.SendDraftReview(SentReview);
        BCJTestLibrary.ChangeLoggedHours(JiraId('E1'), 9);
        FilterOwnProjects(TimeEntry);
        BCJTestLibrary.CreateDraftReview(TimeEntry, DraftReview);
        BCJTestLibrary.ChangeLoggedHours(JiraId('E1'), 10);
        BCJTestLibrary.MarkEntryById(JiraId('E1'), "BCJ Billing Status"::"Not Billable");
        BCJTestLibrary.AssertBuckets(JiraId('E1'), 0, 5, 2, 1, 2, 'Fixture: the 10 h worklog must hold every kind of allocation');
        // [WHEN] 10 -> 9: [THEN] the manual write-off goes first
        BCJTestLibrary.ChangeLoggedHours(JiraId('E1'), 9);
        BCJTestLibrary.AssertBuckets(JiraId('E1'), 0, 5, 2, 0, 2, 'Cutting 1 h must take the manual Not Billable hour first');
        // [WHEN] 9 -> 8: [THEN] then the draft review
        BCJTestLibrary.ChangeLoggedHours(JiraId('E1'), 8);
        BCJTestLibrary.AssertBuckets(JiraId('E1'), 0, 4, 2, 0, 2, 'The next cut must come out of review');
        BCJTestLibrary.AssertRow(JiraId('E1'), DraftReview."Review No.", 1, 0, 0, 0, 'The draft review must be cut before the sent review');
        BCJTestLibrary.AssertRow(JiraId('E1'), SentReview."Review No.", 3, 0, 0, 0, 'The sent review must be untouched while the draft still has hours');
        // [WHEN] 8 -> 5: [THEN] the rest of the draft, then the sent review
        BCJTestLibrary.ChangeLoggedHours(JiraId('E1'), 5);
        BCJTestLibrary.AssertRowHoldsNoHours(JiraId('E1'), DraftReview."Review No.", 'The draft review must be emptied first');
        BCJTestLibrary.AssertRow(JiraId('E1'), SentReview."Review No.", 1, 0, 0, 0, 'The sent review must be cut once the draft is empty');
        BCJTestLibrary.AssertBuckets(JiraId('E1'), 0, 1, 2, 0, 2, 'After the cut 1 h must remain in review');
        // [WHEN] 5 -> 3: [THEN] the sent review is emptied, then the manual approval goes
        BCJTestLibrary.ChangeLoggedHours(JiraId('E1'), 3);
        BCJTestLibrary.AssertRowHoldsNoHours(JiraId('E1'), 0, 'The manual approval must be cut before a customer approval');
        BCJTestLibrary.AssertRow(JiraId('E1'), SecondApproval."Review No.", 0, 1, 0, 0, 'The customer approval must survive while a manual approval can be cut');
        BCJTestLibrary.AssertBuckets(JiraId('E1'), 0, 0, 1, 0, 2, 'After the cut only the customer approval and the invoiced hours remain');
        // [WHEN] 3 -> 2: [THEN] finally the customer approval
        BCJTestLibrary.ChangeLoggedHours(JiraId('E1'), 2);
        BCJTestLibrary.AssertBuckets(JiraId('E1'), 0, 0, 0, 0, 2, 'The customer approval is the last thing cut before Billed');
        BCJTestLibrary.AssertRow(JiraId('E1'), FirstApproval."Review No.", 0, 0, 0, 2, 'Invoiced hours must never be cut');
        AssertOwnInvariant('After the cuts');
    end;

    [Test]
    procedure TrimToLoggedHours_CutsNewestReviewApprovalFirst()
    var
        OlderReview: Record "BCJ Customer Review";
        NewerReview: Record "BCJ Customer Review";
    begin
        // [SCENARIO] Among customer approvals the newest review is cut first: the older approval
        // has stood longer and is more likely already on an invoice proposal.
        // [GIVEN] A 2 h worklog approved 1 h in an older review and 1 h in a newer one
        Initialize();
        AddOpenEntry('E1', 1);
        BCJTestLibrary.ReviewSingleEntry(JiraId('E1'), 1, 1, OlderReview);
        BCJTestLibrary.ChangeLoggedHours(JiraId('E1'), 2);
        BCJTestLibrary.ReviewSingleEntry(JiraId('E1'), 1, 1, NewerReview);
        Assert.IsTrue(NewerReview."Review No." > OlderReview."Review No.", 'Fixture: the second review must be the newer one');
        // [WHEN] Jira shrinks it to 1 h
        BCJTestLibrary.ChangeLoggedHours(JiraId('E1'), 1);
        // [THEN] The newer review's approval is cut
        BCJTestLibrary.AssertRowHoldsNoHours(JiraId('E1'), NewerReview."Review No.", 'The newest review''s approval must be cut first');
        BCJTestLibrary.AssertRow(JiraId('E1'), OlderReview."Review No.", 0, 1, 0, 0, 'The older review''s approval must be kept');
    end;

    [Test]
    procedure TrimToLoggedHours_NeverCutsBilledAndFlagsNegativeOpen()
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] An invoiced hour is a fact on a sent invoice. When Jira shrinks a worklog
        // below its billed hours, BC must not quietly un-bill: Billed stays and Open goes negative
        // (contract: "that is flagged, never corrected by un-billing"), so the overview shows the
        // over-invoiced hours for a person to sort out with a credit note.
        // [GIVEN] A 3 h worklog, fully invoiced
        Initialize();
        AddEntry('E1', 3, "BCJ Billing Status"::Billed);
        // [WHEN] Jira shrinks it to 1 h
        BCJTestLibrary.ChangeLoggedHours(JiraId('E1'), 1);
        // [THEN] Billed stays 3 and Open is -2
        BCJTestLibrary.AssertBuckets(JiraId('E1'), -2, 0, 0, 0, 3, 'Billed hours must never be cut; Open must go negative instead');
        GetEntry('E1', TimeEntry);
        Assert.AreEqual("BCJ Billing Status"::Billed, TimeEntry."Billing Status", 'An over-invoiced worklog must still show Billed');
    end;

    // ---------------------------------------------------------------------------------
    // Rows follow the worklog
    // ---------------------------------------------------------------------------------

    [Test]
    procedure DeleteTimeEntry_DeletesItsAllocationRows()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
    begin
        // [SCENARIO] A worklog deleted in Jira is removed by the sync through the delete trigger.
        // Its allocation rows must go with it - an orphaned row would keep hours counted against a
        // review or a task that no worklog carries any more.
        // [GIVEN] A 4 h worklog with a review row (2 approved) and a manual row (2 written off)
        Initialize();
        AddOpenEntry('E1', 4);
        BCJTestLibrary.ReviewSingleEntry(JiraId('E1'), 4, 2, Review);
        BCJTestLibrary.MarkEntryById(JiraId('E1'), "BCJ Billing Status"::"Not Billable");
        Assert.AreEqual(2, BCJTestLibrary.CountRows(JiraId('E1')), 'Fixture: the worklog must have a review row and a manual row');
        // [WHEN] The worklog is deleted with its trigger
        GetEntry('E1', TimeEntry);
        TimeEntry.Delete(true);
        // [THEN] No row is left
        Assert.AreEqual(0, BCJTestLibrary.CountRows(JiraId('E1')), 'Deleting a worklog must delete all of its allocation rows');
    end;

    // ---------------------------------------------------------------------------------
    // The invariant across a whole working cycle
    // ---------------------------------------------------------------------------------

    [Test]
    procedure BucketInvariant_HoldsAfterEveryOperation()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        SecondReview: Record "BCJ Customer Review";
    begin
        // [SCENARIO] The model is only trustworthy if, after every operation any user can run,
        // each worklog's buckets add up to its logged hours, Unbilled = Open + In Review +
        // Billable, and the cached buckets equal the sums of its allocation rows. A drift in any
        // one of them silently mis-states what can still be invoiced.
        // [GIVEN] Three worklogs on one task
        Initialize();
        AddOpenEntry('E1', 6);
        AddOpenEntryOn('E2', 4, BCJTestLibrary.BaseDate() + 1);
        AddOpenEntryOn('E3', 1.5, BCJTestLibrary.BaseDate() + 2);
        AssertOwnInvariant('After insert');
        // [WHEN] / [THEN] Every step of the business flow keeps the invariant
        FilterOwnProjects(TimeEntry);
        TimeEntry.SetFilter("Jira ID", '%1|%2', JiraId('E1'), JiraId('E2'));
        CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        TempReview.FindFirst();
        Review.Get(TempReview."Review No.");
        AssertOwnInvariant('After CreateReviews');
        CustomerReviewMgt.SetHoursToBillPct(Review, 70);
        AssertOwnInvariant('After SetHoursToBillPct');
        BCJTestLibrary.SendDraftReview(Review);
        AssertOwnInvariant('After SendReview');
        BCJTestLibrary.SetApprovedHours(Review."Review No.", 'T1', 5.5);
        BCJTestLibrary.SubmitAnswer(Review);
        AssertOwnInvariant('After SubmitReview');
        FilterOwnProjects(TimeEntry);
        BillingMgt.SetBillingStatus(TimeEntry, "BCJ Billing Status"::Billed);
        AssertOwnInvariant('After Mark Billed');
        BCJTestLibrary.MarkEntryById(JiraId('E3'), "BCJ Billing Status"::"Not Billable");
        AssertOwnInvariant('After Mark Not Billable');
        BCJTestLibrary.MarkEntryById(JiraId('E3'), "BCJ Billing Status"::Open);
        AssertOwnInvariant('After Mark Open');
        FilterOwnProjects(TimeEntry);
        BCJTestLibrary.CreateDraftReview(TimeEntry, SecondReview);
        AssertOwnInvariant('After a second CreateReviews');
        BCJTestLibrary.ChangeLoggedHours(JiraId('E2'), 2);
        AssertOwnInvariant('After a Jira shrink');
        BCJTestLibrary.ChangeLoggedHours(JiraId('E1'), 8);
        AssertOwnInvariant('After a Jira growth');
        SecondReview.Get(SecondReview."Review No.");
        CustomerReviewMgt.CancelReview(SecondReview);
        AssertOwnInvariant('After CancelReview');
    end;

    // ---------------------------------------------------------------------------------
    // MigrateLegacyEntries - one-time move from the per-worklog status model
    // ---------------------------------------------------------------------------------

    [Test]
    procedure Migrate_OpenEntryGetsNoRowsAndAllHoursOpen()
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] An undecided legacy worklog is simply Open: no allocation rows, Open =
        // Unbilled = L. Creating a row for it would suggest a decision nobody made.
        // [GIVEN] A legacy Open worklog of 3 h
        Initialize();
        BCJTestLibrary.CreateLegacyTimeEntry(TimeEntry, JiraId('E1'), JobNo, 'T1', BCJTestLibrary.BaseDate(), 3, "BCJ Billing Status"::Open, 3, 0);
        // [WHEN] The migration runs
        HourAllocationMgt.MigrateLegacyEntries();
        // [THEN]
        Assert.AreEqual(0, BCJTestLibrary.CountRows(JiraId('E1')), 'A legacy Open worklog must get no allocation rows');
        BCJTestLibrary.AssertBuckets(JiraId('E1'), 3, 0, 0, 0, 0, 'A legacy Open worklog must be fully Open, its old default Billable Hours ignored');
        BCJTestLibrary.AssertStatus(JiraId('E1'), "BCJ Billing Status"::Open, 'A migrated Open worklog must show Open');
    end;

    [Test]
    procedure Migrate_SentForReviewInSentReviewKeepsOldestFirstShareInReview()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        ReviewNo: Integer;
    begin
        // [SCENARIO] A review that is out with the customer at upgrade time must survive it: its
        // worklogs get a row for that review with Reserved = L, and In Review = the worklog's
        // oldest-first share of the line's Hours to Bill - exactly what a Send under the new model
        // would have kept. The rest is Open, as Send would have released it.
        // [GIVEN] A Sent legacy review asking 7 h on T1, over OLD 6 h (D) and NEW 4 h (D+1)
        Initialize();
        ReviewNo := BCJTestLibrary.CreateLegacyReview(JobNo, CustomerNo, "BCJ Review Status"::Sent);
        BCJTestLibrary.CreateLegacyReviewLine(ReviewNo, 'T1', 10, 7);
        BCJTestLibrary.CreateLegacyTimeEntry(TimeEntry, JiraId('OLD'), JobNo, 'T1', BCJTestLibrary.BaseDate(), 6, "BCJ Billing Status"::"Sent for Review", 6, ReviewNo);
        BCJTestLibrary.CreateLegacyTimeEntry(TimeEntry, JiraId('NEW'), JobNo, 'T1', BCJTestLibrary.BaseDate() + 1, 4, "BCJ Billing Status"::"Sent for Review", 4, ReviewNo);
        // [WHEN] The migration runs
        HourAllocationMgt.MigrateLegacyEntries();
        // [THEN] OLD 6 in review, NEW 1 in review + 3 Open, both fully reserved
        BCJTestLibrary.AssertBuckets(JiraId('OLD'), 0, 6, 0, 0, 0, 'The older worklog must carry its full share of the 7 hours asked');
        BCJTestLibrary.AssertBuckets(JiraId('NEW'), 3, 1, 0, 0, 0, 'The newer worklog must carry only the remainder of the request; the rest is Open');
        AssertReserved('OLD', ReviewNo, 6, 'The review must have reserved the whole older worklog');
        AssertReserved('NEW', ReviewNo, 4, 'The review must have reserved the whole newer worklog');
        BCJTestLibrary.AssertStatus(JiraId('NEW'), "BCJ Billing Status"::"Sent for Review", 'A worklog with hours in review must show Sent for Review');
    end;

    [Test]
    procedure Migrate_BillableFromReviewKeepsApprovalOnReviewRow()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        ReviewNo: Integer;
    begin
        // [SCENARIO] Hours a customer approved in a legacy review stay approved, and on that
        // review's row, so Reopen of that review can still take them back. The unapproved rest of
        // the worklog (L - B) was treated as not billable before; now it is Open, for the
        // consultant to decide (business flow step 5).
        // [GIVEN] An answered legacy review; a 4 h worklog Billable with 2.5 h allocated
        Initialize();
        ReviewNo := BCJTestLibrary.CreateLegacyReview(JobNo, CustomerNo, "BCJ Review Status"::Answered);
        BCJTestLibrary.CreateLegacyTimeEntry(TimeEntry, JiraId('E1'), JobNo, 'T1', BCJTestLibrary.BaseDate(), 4, "BCJ Billing Status"::Billable, 2.5, ReviewNo);
        // [WHEN] The migration runs
        HourAllocationMgt.MigrateLegacyEntries();
        // [THEN]
        BCJTestLibrary.AssertRow(JiraId('E1'), ReviewNo, 0, 2.5, 0, 0, 'The approved hours must sit on the review''s row');
        AssertReserved('E1', ReviewNo, 4, 'The review row must have reserved the whole worklog');
        BCJTestLibrary.AssertBuckets(JiraId('E1'), 1.5, 0, 2.5, 0, 0, 'The unallocated rest of the worklog must be Open');
    end;

    [Test]
    procedure Migrate_NotBillableFromReviewBecomesOpen()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        ReviewNo: Integer;
    begin
        // [SCENARIO] Under the old model a worklog the customer approved nothing on was marked Not
        // Billable automatically. That was the customer's answer, not the consultant's write-off,
        // so it migrates to Open (with a reserved-only review row recording where it came from).
        // [GIVEN] An answered legacy review; a 2 h worklog Not Billable on it
        Initialize();
        ReviewNo := BCJTestLibrary.CreateLegacyReview(JobNo, CustomerNo, "BCJ Review Status"::Answered);
        BCJTestLibrary.CreateLegacyTimeEntry(TimeEntry, JiraId('E1'), JobNo, 'T1', BCJTestLibrary.BaseDate(), 2, "BCJ Billing Status"::"Not Billable", 0, ReviewNo);
        // [WHEN] The migration runs
        HourAllocationMgt.MigrateLegacyEntries();
        // [THEN]
        BCJTestLibrary.AssertRow(JiraId('E1'), ReviewNo, 0, 0, 0, 0, 'The review row must hold no bucket hours');
        AssertReserved('E1', ReviewNo, 2, 'The review row must record the whole worklog as reserved');
        BCJTestLibrary.AssertBuckets(JiraId('E1'), 2, 0, 0, 0, 0, 'A worklog the customer approved nothing on must be Open');
        BCJTestLibrary.AssertStatus(JiraId('E1'), "BCJ Billing Status"::Open, 'It must show Open');
    end;

    [Test]
    procedure Migrate_ManualBillableKeepsAllocationOnManualRow()
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] A worklog marked Billable by hand (no review) keeps its allocation as a
        // manual approval; the rest of the worklog is Open.
        // [GIVEN] A legacy 3 h worklog Billable with 2 h allocated, no review
        Initialize();
        BCJTestLibrary.CreateLegacyTimeEntry(TimeEntry, JiraId('E1'), JobNo, 'T1', BCJTestLibrary.BaseDate(), 3, "BCJ Billing Status"::Billable, 2, 0);
        // [WHEN] The migration runs
        HourAllocationMgt.MigrateLegacyEntries();
        // [THEN]
        BCJTestLibrary.AssertRow(JiraId('E1'), 0, 0, 2, 0, 0, 'The manual approval must sit on the manual row');
        BCJTestLibrary.AssertBuckets(JiraId('E1'), 1, 0, 2, 0, 0, 'The rest of the worklog must be Open');
    end;

    [Test]
    procedure Migrate_ManualNotBillableIsADeliberateWriteOff()
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] A worklog marked Not Billable by hand, without a review, was a deliberate
        // write-off by the consultant and stays one - for the whole worklog.
        // [GIVEN] A legacy 2 h worklog Not Billable, no review
        Initialize();
        BCJTestLibrary.CreateLegacyTimeEntry(TimeEntry, JiraId('E1'), JobNo, 'T1', BCJTestLibrary.BaseDate(), 2, "BCJ Billing Status"::"Not Billable", 2, 0);
        // [WHEN] The migration runs
        HourAllocationMgt.MigrateLegacyEntries();
        // [THEN]
        BCJTestLibrary.AssertRow(JiraId('E1'), 0, 0, 0, 2, 0, 'A manual write-off must be a manual Not Billable row for the whole worklog');
        BCJTestLibrary.AssertBuckets(JiraId('E1'), 0, 0, 0, 2, 0, 'A manual write-off must stay written off');
        BCJTestLibrary.AssertStatus(JiraId('E1'), "BCJ Billing Status"::"Not Billable", 'It must show Not Billable');
    end;

    [Test]
    procedure Migrate_BilledKeepsInvoicedHoursOnTheRightRow()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        ReviewNo: Integer;
    begin
        // [SCENARIO] Invoiced hours are a fact and must survive the upgrade exactly: Billed = B, on
        // the review's row when the worklog came through a review, else on the manual row. The
        // part of the worklog that was never invoiced (L - B) is Open.
        // [GIVEN] A 5 h worklog Billed with 3 h from an answered review, and a 2 h worklog Billed in full without review
        Initialize();
        ReviewNo := BCJTestLibrary.CreateLegacyReview(JobNo, CustomerNo, "BCJ Review Status"::Answered);
        BCJTestLibrary.CreateLegacyTimeEntry(TimeEntry, JiraId('REV'), JobNo, 'T1', BCJTestLibrary.BaseDate(), 5, "BCJ Billing Status"::Billed, 3, ReviewNo);
        BCJTestLibrary.CreateLegacyTimeEntry(TimeEntry, JiraId('MAN'), JobNo, 'T1', BCJTestLibrary.BaseDate(), 2, "BCJ Billing Status"::Billed, 2, 0);
        // [WHEN] The migration runs
        HourAllocationMgt.MigrateLegacyEntries();
        // [THEN]
        BCJTestLibrary.AssertRow(JiraId('REV'), ReviewNo, 0, 0, 0, 3, 'Invoiced hours from a review must sit on the review''s row');
        BCJTestLibrary.AssertBuckets(JiraId('REV'), 2, 0, 0, 0, 3, 'The never-invoiced rest of the worklog must be Open');
        BCJTestLibrary.AssertRow(JiraId('MAN'), 0, 0, 0, 0, 2, 'Invoiced hours without a review must sit on the manual row');
        BCJTestLibrary.AssertBuckets(JiraId('MAN'), 0, 0, 0, 0, 2, 'A fully invoiced worklog must be fully Billed');
        BCJTestLibrary.AssertStatus(JiraId('MAN'), "BCJ Billing Status"::Billed, 'A fully invoiced worklog must show Billed');
        GetEntry('MAN', TimeEntry);
        Assert.IsTrue(TimeEntry."Is Billed", 'A migrated Billed worklog must keep Is Billed');
    end;

    [Test]
    procedure Migrate_ClampsOldBillableHoursToLoggedHours()
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] Old "Billable Hours" could be out of step with the logged time (a worklog
        // corrected in Jira, a value typed by hand). The migration clamps B to [0, L]: a worklog
        // can never be approved or invoiced for more than it logs, nor for less than nothing.
        // [GIVEN] A 2 h worklog Billable with 5 h allocated, and a 3 h worklog Billed with -1 h
        Initialize();
        BCJTestLibrary.CreateLegacyTimeEntry(TimeEntry, JiraId('OVER'), JobNo, 'T1', BCJTestLibrary.BaseDate(), 2, "BCJ Billing Status"::Billable, 5, 0);
        BCJTestLibrary.CreateLegacyTimeEntry(TimeEntry, JiraId('NEG'), JobNo, 'T1', BCJTestLibrary.BaseDate(), 3, "BCJ Billing Status"::Billed, -1, 0);
        // [WHEN] The migration runs
        HourAllocationMgt.MigrateLegacyEntries();
        // [THEN]
        BCJTestLibrary.AssertBuckets(JiraId('OVER'), 0, 0, 2, 0, 0, 'An allocation above the logged hours must be clamped to them');
        BCJTestLibrary.AssertBuckets(JiraId('NEG'), 3, 0, 0, 0, 0, 'A negative allocation must be clamped to 0, leaving the worklog Open');
    end;

    [Test]
    procedure Migrate_SecondRunChangesNothing()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Allocation: Record "BCJ Time Entry Allocation";
        SentReviewNo: Integer;
        AnsweredReviewNo: Integer;
        RowsAfterFirst: Integer;
    begin
        // [SCENARIO] The migration runs from the upgrade and again from install when the upgrade
        // tag is missing, so it must be idempotent: a second run over already migrated worklogs
        // must change nothing - running the Open cases again would otherwise, for instance, wipe
        // out an approval or double a reservation.
        // [GIVEN] Legacy worklogs in every state, migrated once
        Initialize();
        SentReviewNo := BCJTestLibrary.CreateLegacyReview(JobNo, CustomerNo, "BCJ Review Status"::Sent);
        BCJTestLibrary.CreateLegacyReviewLine(SentReviewNo, 'T1', 4, 3);
        AnsweredReviewNo := BCJTestLibrary.CreateLegacyReview(JobNo, CustomerNo, "BCJ Review Status"::Answered);
        BCJTestLibrary.CreateLegacyTimeEntry(TimeEntry, JiraId('OP'), JobNo, 'T1', BCJTestLibrary.BaseDate(), 1, "BCJ Billing Status"::Open, 1, 0);
        BCJTestLibrary.CreateLegacyTimeEntry(TimeEntry, JiraId('SR'), JobNo, 'T1', BCJTestLibrary.BaseDate(), 4, "BCJ Billing Status"::"Sent for Review", 4, SentReviewNo);
        BCJTestLibrary.CreateLegacyTimeEntry(TimeEntry, JiraId('BR'), JobNo, 'T1', BCJTestLibrary.BaseDate(), 4, "BCJ Billing Status"::Billable, 2.5, AnsweredReviewNo);
        BCJTestLibrary.CreateLegacyTimeEntry(TimeEntry, JiraId('NR'), JobNo, 'T1', BCJTestLibrary.BaseDate(), 2, "BCJ Billing Status"::"Not Billable", 0, AnsweredReviewNo);
        BCJTestLibrary.CreateLegacyTimeEntry(TimeEntry, JiraId('BM'), JobNo, 'T1', BCJTestLibrary.BaseDate(), 3, "BCJ Billing Status"::Billable, 2, 0);
        BCJTestLibrary.CreateLegacyTimeEntry(TimeEntry, JiraId('NM'), JobNo, 'T1', BCJTestLibrary.BaseDate(), 2, "BCJ Billing Status"::"Not Billable", 2, 0);
        BCJTestLibrary.CreateLegacyTimeEntry(TimeEntry, JiraId('BD'), JobNo, 'T1', BCJTestLibrary.BaseDate(), 5, "BCJ Billing Status"::Billed, 3, AnsweredReviewNo);
        HourAllocationMgt.MigrateLegacyEntries();
        Allocation.SetFilter("Jira ID", Stem + '*');
        RowsAfterFirst := Allocation.Count();
        // [WHEN] The migration runs a second time
        HourAllocationMgt.MigrateLegacyEntries();
        // [THEN] Every worklog and every row is exactly as after the first run
        Assert.AreEqual(RowsAfterFirst, Allocation.Count(), 'A second run must not add or remove allocation rows');
        BCJTestLibrary.AssertBuckets(JiraId('OP'), 1, 0, 0, 0, 0, 'Second run: Open worklog unchanged');
        BCJTestLibrary.AssertBuckets(JiraId('SR'), 1, 3, 0, 0, 0, 'Second run: worklog in a sent review unchanged');
        BCJTestLibrary.AssertBuckets(JiraId('BR'), 1.5, 0, 2.5, 0, 0, 'Second run: review-approved worklog unchanged');
        BCJTestLibrary.AssertBuckets(JiraId('NR'), 2, 0, 0, 0, 0, 'Second run: worklog rejected in a review unchanged');
        BCJTestLibrary.AssertBuckets(JiraId('BM'), 1, 0, 2, 0, 0, 'Second run: manually approved worklog unchanged');
        BCJTestLibrary.AssertBuckets(JiraId('NM'), 0, 0, 0, 2, 0, 'Second run: written-off worklog unchanged');
        BCJTestLibrary.AssertBuckets(JiraId('BD'), 2, 0, 0, 0, 3, 'Second run: invoiced worklog unchanged');
        AssertReserved('SR', SentReviewNo, 4, 'Second run: the reservation must not be doubled');
        AssertOwnInvariant('After two migration runs');
    end;

    [Test]
    procedure Migrate_SkipsWorklogsAlreadyInTheNewModel()
    var
        Review: Record "BCJ Customer Review";
    begin
        // [SCENARIO] Worklogs created or decided after the upgrade already have allocation rows or
        // a built cache and must be skipped. A worklog partly approved in a new-style review shows
        // "Open" (Open > 0 wins); if the migration mistook it for a legacy Open worklog it would
        // wipe out the customer's approval.
        // [GIVEN] A new-model 4 h worklog: 2 approved in a review, 2 Open; and a fresh Open worklog
        Initialize();
        AddOpenEntry('E1', 4);
        BCJTestLibrary.ReviewSingleEntry(JiraId('E1'), 4, 2, Review);
        BCJTestLibrary.AssertStatus(JiraId('E1'), "BCJ Billing Status"::Open, 'Fixture: the partly approved worklog must show Open');
        AddOpenEntry('E2', 3);
        // [WHEN] The migration runs
        HourAllocationMgt.MigrateLegacyEntries();
        // [THEN] Both are untouched
        BCJTestLibrary.AssertBuckets(JiraId('E1'), 2, 0, 2, 0, 0, 'The migration must not touch a worklog that already has allocation rows');
        BCJTestLibrary.AssertRow(JiraId('E1'), Review."Review No.", 0, 2, 0, 0, 'The customer''s approval must survive the migration');
        BCJTestLibrary.AssertBuckets(JiraId('E2'), 3, 0, 0, 0, 0, 'The migration must not touch a worklog whose cache is already built');
    end;

    // ---------------------------------------------------------------------------------
    // Fixtures and helpers
    // ---------------------------------------------------------------------------------

    local procedure Initialize()
    begin
        // Run on every test, never guarded by a "done" flag: the runner rolls the database back
        // but not codeunit variables.
        Stem := BCJTestLibrary.NewStem();
        BCJTestLibrary.EnsureSetup('https://review.example.com');
        CustomerNo := CopyStr(Stem + 'C', 1, 20);
        JobNo := CopyStr(Stem + 'P1', 1, 20);
        BCJTestLibrary.CreateCustomer(CustomerNo, CopyStr('Customer ' + CustomerNo, 1, 100));
        BCJTestLibrary.CreateJob(JobNo, CustomerNo, CopyStr('Project ' + JobNo, 1, 100));
        BCJTestLibrary.CreateJobTask(JobNo, 'T1', CopyStr('Task T1 of ' + JobNo, 1, 100), 'IN PROGRESS');
    end;

    local procedure JiraId(Suffix: Text): Text[50]
    begin
        exit(CopyStr(Stem + '-' + Suffix, 1, 50));
    end;

    local procedure FakeReviewNo(): Integer
    begin
        // A review number no real review in the sandbox will have; the allocation row does not
        // validate its table relation, and RecalcEntry only sums rows.
        exit(2147483000);
    end;

    local procedure AddOpenEntry(Suffix: Text; Hours: Decimal)
    begin
        AddOpenEntryOn(Suffix, Hours, BCJTestLibrary.BaseDate());
    end;

    local procedure AddOpenEntryOn(Suffix: Text; Hours: Decimal; PostingDate: Date)
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        BCJTestLibrary.CreateOpenTimeEntry(TimeEntry, JiraId(Suffix), JobNo, 'T1', Stem, PostingDate, Hours);
    end;

    local procedure AddEntry(Suffix: Text; Hours: Decimal; Status: Enum "BCJ Billing Status")
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        BCJTestLibrary.CreateTimeEntry(TimeEntry, JiraId(Suffix), JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), Hours, Status);
    end;

    local procedure GetEntry(Suffix: Text; var TimeEntry: Record "BCJ Project Time Entry")
    begin
        BCJTestLibrary.GetEntry(JiraId(Suffix), TimeEntry);
    end;

    local procedure FilterOwnProjects(var TimeEntry: Record "BCJ Project Time Entry")
    begin
        TimeEntry.Reset();
        TimeEntry.SetFilter("Project No.", Stem + '*');
    end;

    local procedure CreateDraftOverOwnEntries(var Review: Record "BCJ Customer Review")
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        FilterOwnProjects(TimeEntry);
        BCJTestLibrary.CreateDraftReview(TimeEntry, Review);
    end;

    local procedure InsertRow(Suffix: Text; ReviewNo: Integer; InReviewHours: Decimal; BillableHours: Decimal; BilledHours: Decimal; NotBillableHours: Decimal)
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Allocation: Record "BCJ Time Entry Allocation";
    begin
        // RecalcEntry's input is the set of rows, so its tests build rows directly.
        GetEntry(Suffix, TimeEntry);
        Allocation.Init();
        Allocation."Jira ID" := TimeEntry."Jira ID";
        Allocation."Jira Issue Id" := TimeEntry."Jira Issue Id";
        Allocation."Review No." := ReviewNo;
        Allocation."Project No." := TimeEntry."Project No.";
        Allocation."Project Task No." := TimeEntry."Project Task No.";
        Allocation."Posting Date" := TimeEntry."Posting Date";
        Allocation."Reserved Hours" := InReviewHours;
        Allocation."In Review Hours" := InReviewHours;
        Allocation."Billable Hours" := BillableHours;
        Allocation."Billed Hours" := BilledHours;
        Allocation."Not Billable Hours" := NotBillableHours;
        Allocation.Insert(false);
    end;

    local procedure RecalcAndAssert(Suffix: Text; OpenHours: Decimal; InReviewHours: Decimal; BillableHours: Decimal; BilledHours: Decimal; NotBillableHours: Decimal; ExpectedStatus: Enum "BCJ Billing Status"; Msg: Text)
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Stored: Record "BCJ Project Time Entry";
    begin
        GetEntry(Suffix, TimeEntry);
        HourAllocationMgt.RecalcEntry(TimeEntry);
        Assert.AreEqual(OpenHours, TimeEntry."Open Hours", Msg + ' (Open Hours = L - the row buckets)');
        Assert.AreEqual(InReviewHours, TimeEntry."In Review Hours", Msg + ' (In Review Hours = sum of rows)');
        Assert.AreEqual(BillableHours, TimeEntry."Billable Hours", Msg + ' (Billable Hours = sum of rows)');
        Assert.AreEqual(BilledHours, TimeEntry."Billed Hours", Msg + ' (Billed Hours = sum of rows)');
        Assert.AreEqual(NotBillableHours, TimeEntry."Not Billable Hours", Msg + ' (Not Billable Hours = sum of rows)');
        Assert.AreEqual(OpenHours + InReviewHours + BillableHours, TimeEntry."Unbilled Hours", Msg + ' (Unbilled Hours = Open + In Review + Billable)');
        Assert.AreEqual(ExpectedStatus, TimeEntry."Billing Status", Msg + ' (derived Billing Status)');
        // RecalcEntry works on the var record only
        GetEntry(Suffix, Stored);
        Assert.AreEqual(Stored."Time Spent in Hours", Stored."Open Hours", Msg + ' (RecalcEntry must not modify the stored record)');
    end;

    local procedure AssertReserved(Suffix: Text; ReviewNo: Integer; ReservedHours: Decimal; Msg: Text)
    var
        Allocation: Record "BCJ Time Entry Allocation";
    begin
        Assert.IsTrue(Allocation.Get(JiraId(Suffix), BCJTestLibrary.IssueId(JiraId(Suffix)), ReviewNo), Msg + ' (the review row must exist)');
        Assert.AreEqual(ReservedHours, Allocation."Reserved Hours", Msg);
    end;

    local procedure AssertOwnInvariant(Context: Text)
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        FilterOwnProjects(TimeEntry);
        BCJTestLibrary.AssertInvariant(TimeEntry, Context);
    end;
}
