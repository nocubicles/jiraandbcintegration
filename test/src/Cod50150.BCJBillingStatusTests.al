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
    procedure SetBillingStatusCountExcludesEntriesAlreadyInStatus()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Stem: Code[13];
        JobNo: Code[20];
        Changed: Integer;
    begin
        // [SCENARIO] The returned count is shown to the user as "N entries updated". Entries that
        // already had the status were not updated, so counting them would overstate the change.
        // [GIVEN] Three entries, one already Billable
        Stem := BCJTestLibrary.NewStem();
        JobNo := CreateJobWithTask(Stem);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-1', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 1, "BCJ Billing Status"::Open);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-2', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 2, "BCJ Billing Status"::Billable);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-3', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 3, "BCJ Billing Status"::"Not Billable");
        // [WHEN] SetBillingStatus(Billable) on the whole project
        TimeEntry.Reset();
        TimeEntry.SetRange("Project No.", JobNo);
        Changed := BillingMgt.SetBillingStatus(TimeEntry, "BCJ Billing Status"::Billable);
        // [THEN] Only the two that actually changed are counted, and all three are Billable
        Assert.AreEqual(2, Changed, 'Entries already in the new status must not be counted as changed');
        Assert.AreEqual("BCJ Billing Status"::Billable, GetStatus(Stem + '-1'), 'Open entry must become Billable');
        Assert.AreEqual("BCJ Billing Status"::Billable, GetStatus(Stem + '-2'), 'Already Billable entry must stay Billable');
        Assert.AreEqual("BCJ Billing Status"::Billable, GetStatus(Stem + '-3'), 'Not Billable entry must become Billable');
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
    procedure SetBillingStatusPersistsStatusAndLegacyFlags()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Stored: Record "BCJ Project Time Entry";
        Stem: Code[13];
        JobNo: Code[20];
    begin
        // [SCENARIO] SetBillingStatus must go through Validate so the legacy flags that the old page
        // and existing reports read stay consistent with the new status in the database.
        // [GIVEN] One open entry with no flags
        Stem := BCJTestLibrary.NewStem();
        JobNo := CreateJobWithTask(Stem);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-1', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 1, "BCJ Billing Status"::Open);
        TimeEntry.Reset();
        TimeEntry.SetRange("Project No.", JobNo);
        // [WHEN] Status set to Billed
        BillingMgt.SetBillingStatus(TimeEntry, "BCJ Billing Status"::Billed);
        // [THEN] Stored entry is Billed with both flags set
        Stored.Get(Stem + '-1', 'I-' + Stem + '-1');
        Assert.AreEqual("BCJ Billing Status"::Billed, Stored."Billing Status", 'Billed status must be persisted');
        Assert.IsTrue(Stored."Is Billable", 'Persisted Billed entry must have Is Billable set');
        Assert.IsTrue(Stored."Is Billed", 'Persisted Billed entry must have Is Billed set');

        // [WHEN] Status then set to Not Billable
        BillingMgt.SetBillingStatus(TimeEntry, "BCJ Billing Status"::"Not Billable");
        // [THEN] Stored entry has both flags cleared
        Stored.Get(Stem + '-1', 'I-' + Stem + '-1');
        Assert.AreEqual("BCJ Billing Status"::"Not Billable", Stored."Billing Status", 'Not Billable status must be persisted');
        Assert.IsFalse(Stored."Is Billable", 'Persisted Not Billable entry must have Is Billable cleared');
        Assert.IsFalse(Stored."Is Billed", 'Persisted Not Billable entry must have Is Billed cleared');
    end;

    // ---------------------------------------------------------------------------------
    // SyncStatusFromLegacyFlags
    // ---------------------------------------------------------------------------------

    [Test]
    procedure SyncPromotesOpenEntriesFromLegacyFlags()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Stem: Code[13];
        JobNo: Code[20];
    begin
        // [SCENARIO] Users still tick Is Billable / Is Billed on the old page, which does not touch
        // Billing Status. The sync picks those decisions up for undecided (Open) entries so the new
        // overview does not show already-invoiced hours as unbilled. Is Billed wins over Is Billable.
        // [GIVEN] Four Open entries with each flag combination
        Stem := BCJTestLibrary.NewStem();
        JobNo := CreateJobWithTask(Stem);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-BILLED', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 1, "BCJ Billing Status"::Open);
        BCJTestLibrary.SetLegacyFlags(TimeEntry, false, true);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-BILLABLE', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 1, "BCJ Billing Status"::Open);
        BCJTestLibrary.SetLegacyFlags(TimeEntry, true, false);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-BOTH', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 1, "BCJ Billing Status"::Open);
        BCJTestLibrary.SetLegacyFlags(TimeEntry, true, true);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-NONE', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 1, "BCJ Billing Status"::Open);
        // [WHEN] Sync runs
        BillingMgt.SyncStatusFromLegacyFlags();
        // [THEN] Status follows the flags, flags themselves are untouched
        Assert.AreEqual("BCJ Billing Status"::Billed, GetStatus(Stem + '-BILLED'), 'Open entry with Is Billed must become Billed');
        Assert.AreEqual("BCJ Billing Status"::Billable, GetStatus(Stem + '-BILLABLE'), 'Open entry with Is Billable must become Billable');
        Assert.AreEqual("BCJ Billing Status"::Billed, GetStatus(Stem + '-BOTH'), 'Open entry with both flags must become Billed');
        Assert.AreEqual("BCJ Billing Status"::Open, GetStatus(Stem + '-NONE'), 'Open entry without flags must stay Open');
        AssertFlags(Stem + '-BILLED', false, true, 'Sync must not change the legacy flags of a synced entry');
        AssertFlags(Stem + '-BILLABLE', true, false, 'Sync must not change the legacy flags of a synced entry');
        AssertFlags(Stem + '-NONE', false, false, 'Sync must not change the legacy flags of an Open entry');
    end;

    [Test]
    procedure SyncNeverChangesEntriesThatAreNotOpen()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Stem: Code[13];
        JobNo: Code[20];
    begin
        // [SCENARIO] A status set in the new overview is an explicit user decision and outranks the
        // legacy flags. Stale flags (e.g. Is Billable left ticked on an entry later marked Not
        // Billable) must never override it, or the sync would silently undo the user's decision.
        // [GIVEN] Non-Open entries whose flags disagree with their status
        Stem := BCJTestLibrary.NewStem();
        JobNo := CreateJobWithTask(Stem);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-NB', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 1, "BCJ Billing Status"::"Not Billable");
        BCJTestLibrary.SetLegacyFlags(TimeEntry, true, false);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-BL', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 1, "BCJ Billing Status"::Billable);
        BCJTestLibrary.SetLegacyFlags(TimeEntry, true, true);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, Stem + '-BD', JobNo, 'T1', Stem, BCJTestLibrary.BaseDate(), 1, "BCJ Billing Status"::Billed);
        BCJTestLibrary.SetLegacyFlags(TimeEntry, false, false);
        // [WHEN] Sync runs
        BillingMgt.SyncStatusFromLegacyFlags();
        // [THEN] Every status is unchanged
        Assert.AreEqual("BCJ Billing Status"::"Not Billable", GetStatus(Stem + '-NB'), 'Not Billable entry must stay Not Billable despite Is Billable');
        Assert.AreEqual("BCJ Billing Status"::Billable, GetStatus(Stem + '-BL'), 'Billable entry must stay Billable despite Is Billed');
        Assert.AreEqual("BCJ Billing Status"::Billed, GetStatus(Stem + '-BD'), 'Billed entry must stay Billed despite cleared flags');
        AssertFlags(Stem + '-NB', true, false, 'Sync must not change the legacy flags of a non-Open entry');
        AssertFlags(Stem + '-BD', false, false, 'Sync must not change the legacy flags of a non-Open entry');
    end;

    // ---------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------

    local procedure CreateJobWithTask(Stem: Code[13]): Code[20]
    var
        JobNo: Code[20];
    begin
        JobNo := Stem + 'P';
        BCJTestLibrary.CreateJob(JobNo, '', 'Project ' + Stem);
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

    local procedure AssertFlags(JiraId: Text[50]; ExpectedIsBillable: Boolean; ExpectedIsBilled: Boolean; Msg: Text)
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        TimeEntry.Get(JiraId, CopyStr('I-' + JiraId, 1, 50));
        Assert.AreEqual(ExpectedIsBillable, TimeEntry."Is Billable", Msg);
        Assert.AreEqual(ExpectedIsBilled, TimeEntry."Is Billed", Msg);
    end;
}
