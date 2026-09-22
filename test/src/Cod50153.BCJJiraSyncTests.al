codeunit 50153 "BCJ Jira Sync Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    // Regression cover for the production sync crash: a Jira issue with a 109-character summary
    // aborted the whole full sync with "The length of the string is 109, but it must be less than
    // or equal to 100 characters." Jira puts no useful limit on an issue summary, BC's
    // "Job Task".Description is Text[100], so the sync is the place where the two meet - it must
    // truncate and keep going. One over-long summary must never stop every other issue from syncing.
    //
    // The same bug class reaches two more fields on the worklog side of the sync: the author's
    // display name (Resource.Name is Text[100], the resource No. Code[20]) and the worklog comment
    // ("BCJ Project Time Entry".Comment is Text[2024]). Those are covered below.
    //
    // All fixture keys derive from a fresh GUID stem, so these tests never touch real synced Jira
    // data in the sandbox or collide with each other.

    var
        BCJTestLibrary: Codeunit "BCJ Test Library";
        Assert: Codeunit "Library Assert";
        ProcessJiraQueue: Codeunit "BCJ Process Jira Queue";

    // ---------------------------------------------------------------------------------
    // SyncJobTask - description truncation
    // ---------------------------------------------------------------------------------

    [Test]
    procedure SyncJobTaskTruncatesLongDescriptionOnInsert()
    var
        JobTask: Record "Job Task";
        Stem: Code[13];
        JobNo: Code[20];
        LongDescription: Text;
        Synced: Boolean;
    begin
        // [SCENARIO] This is the reported failure, reproduced: a Jira summary of 109 characters on
        // an issue BC has not seen before. The summary is the caller's data and cannot be
        // constrained, so the sync - not Jira - owns the fit into Text[100]. Truncating loses the
        // tail of a title; erroring loses the entire sync run, which is what happened in
        // production. It must truncate, store the first 100 characters, and report success.
        // [GIVEN] A project with no task T1, and a 109-character Jira summary
        Stem := BCJTestLibrary.NewStem();
        JobNo := CreateJob(Stem);
        LongDescription := MakeDescription(109);
        // [WHEN] The task is synced for the first time
        Synced := ProcessJiraQueue.SyncJobTask(JobNo, 'T1', LongDescription, Stem + '-ISSUE', 'IN PROGRESS');
        // [THEN] The sync reports success and the task exists with the first 100 characters
        Assert.IsTrue(Synced, 'Syncing a task whose Jira summary is longer than 100 characters must succeed, not fail');
        Assert.IsTrue(JobTask.Get(JobNo, 'T1'), 'An over-long Jira summary must not prevent the job task from being created');
        Assert.AreEqual(CopyStr(LongDescription, 1, 100), JobTask.Description, 'Description must hold the first 100 characters of the Jira summary');
        Assert.AreEqual(100, StrLen(JobTask.Description), 'A 109-character Jira summary must be stored truncated to exactly 100 characters');
        Assert.AreEqual(Stem + '-ISSUE', JobTask."BCJ Jira Task Id", 'Truncating the summary must not stop the Jira issue id from being stored');
        Assert.AreEqual('IN PROGRESS', JobTask."BCJ Jira Status", 'Truncating the summary must not stop the Jira status from being stored');
    end;

    [Test]
    procedure SyncJobTaskTruncatesLongDescriptionOnUpdate()
    var
        JobTask: Record "Job Task";
        Stem: Code[13];
        JobNo: Code[20];
        LongDescription: Text;
        Synced: Boolean;
    begin
        // [SCENARIO] The crash was in a *full* sync, which re-syncs issues BC already has. Renaming
        // an existing Jira issue to a long summary hits the update path, not the insert path, so
        // the update path needs the same truncation - otherwise the first full sync after a rename
        // dies exactly as the reported one did.
        // [GIVEN] A task that already exists with a short description
        Stem := BCJTestLibrary.NewStem();
        JobNo := CreateJob(Stem);
        BCJTestLibrary.CreateJobTask(JobNo, 'T1', 'Short task name', 'TO DO');
        LongDescription := MakeDescription(140);
        // [WHEN] The same task is synced again with a 140-character summary
        Synced := ProcessJiraQueue.SyncJobTask(JobNo, 'T1', LongDescription, Stem + '-ISSUE', 'DONE');
        // [THEN] The sync succeeds and the stored description is the first 100 characters
        Assert.IsTrue(Synced, 'Re-syncing an existing task with an over-long Jira summary must succeed, not fail');
        JobTask.Get(JobNo, 'T1');
        Assert.AreEqual(CopyStr(LongDescription, 1, 100), JobTask.Description, 'An updated task must hold the first 100 characters of the new Jira summary');
        Assert.AreEqual(100, StrLen(JobTask.Description), 'A 140-character Jira summary must be stored truncated to exactly 100 characters');
        Assert.AreEqual('DONE', JobTask."BCJ Jira Status", 'The Jira status of an existing task must be updated by the sync');
    end;

    [Test]
    procedure SyncJobTaskKeepsShortDescription()
    var
        JobTask: Record "Job Task";
        Stem: Code[13];
        JobNo: Code[20];
        BoundaryDescription: Text;
    begin
        // [SCENARIO] 100 characters is the last length that still fits, so it is the boundary where
        // an off-by-one in the truncation would show. Whatever fits must reach BC untouched - the
        // fix must not start shortening titles users can currently read in full.
        // [GIVEN] A project with no task T1 and a summary of exactly 100 characters
        Stem := BCJTestLibrary.NewStem();
        JobNo := CreateJob(Stem);
        BoundaryDescription := MakeDescription(100);
        // [WHEN] The task is synced
        ProcessJiraQueue.SyncJobTask(JobNo, 'T1', BoundaryDescription, Stem + '-ISSUE', 'TO DO');
        // [THEN] The description is stored character for character
        JobTask.Get(JobNo, 'T1');
        Assert.AreEqual(BoundaryDescription, JobTask.Description, 'A summary of exactly 100 characters must be stored unchanged');
        Assert.AreEqual(100, StrLen(JobTask.Description), 'A summary of exactly 100 characters must keep all 100 characters');
    end;

    // ---------------------------------------------------------------------------------
    // SyncJob - description truncation
    // ---------------------------------------------------------------------------------

    [Test]
    procedure SyncJobTruncatesLongDescription()
    var
        Job: Record Job;
        Stem: Code[13];
        JobNo: Code[20];
        LongDescription: Text;
        Synced: Boolean;
    begin
        // [SCENARIO] Job.Description is Text[100] just like the task's, and a Jira project name is
        // as unconstrained as an issue summary. The same sync run creates the project before the
        // task, so an over-long project name would abort the run one step earlier - the same bug,
        // a different field.
        // [GIVEN] A project number that does not exist in BC and a 120-character project name
        Stem := BCJTestLibrary.NewStem();
        JobNo := Stem + 'P';
        LongDescription := MakeDescription(120);
        // [WHEN] The job is synced
        Synced := ProcessJiraQueue.SyncJob(JobNo, LongDescription);
        // [THEN] The job exists with the first 100 characters of the name
        Assert.IsTrue(Synced, 'Syncing a project whose Jira name is longer than 100 characters must succeed, not fail');
        Assert.IsTrue(Job.Get(JobNo), 'An over-long Jira project name must not prevent the job from being created');
        Assert.AreEqual(CopyStr(LongDescription, 1, 100), Job.Description, 'Job Description must hold the first 100 characters of the Jira project name');
        Assert.AreEqual(100, StrLen(Job.Description), 'A 120-character Jira project name must be stored truncated to exactly 100 characters');
    end;

    [Test]
    procedure SyncJobOnExistingJobReportsSuccess()
    var
        Stem: Code[13];
        JobNo: Code[20];
        Synced: Boolean;
    begin
        // [SCENARIO] Every full sync re-syncs projects that already exist. The caller treats false
        // as "this project could not be synced" and logs/aborts on it, so "already there" must read
        // as success - otherwise a normal re-run looks like a run of failures.
        // [GIVEN] A job that already exists
        Stem := BCJTestLibrary.NewStem();
        JobNo := Stem + 'P';
        BCJTestLibrary.CreateJob(JobNo, '', 'Existing project ' + Stem);
        // [WHEN] The same job is synced again
        Synced := ProcessJiraQueue.SyncJob(JobNo, MakeDescription(120));
        // [THEN] The sync reports success
        Assert.IsTrue(Synced, 'Syncing a project that already exists in BC must report success');
    end;

    // ---------------------------------------------------------------------------------
    // SyncJobTimeEntry - comment and resource name truncation
    // ---------------------------------------------------------------------------------

    [Test]
    procedure SyncJobTimeEntryTruncatesLongCommentOnInsert()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Stem: Code[13];
        JobNo: Code[20];
        JiraIssueId: Code[20];
        TimeEntryId: Code[20];
        LongComment: Text;
        Synced: Boolean;
    begin
        // [SCENARIO] Same bug class as the issue summary, one field further down the sync: a Jira
        // worklog comment is free text a developer types with no limit, while Comment on the time
        // entry is Text[2024]. One chatty worklog must not abort the run that brings in everybody
        // else's hours - the hours are what the customer invoices from, so losing a whole sync
        // costs money in a way that losing the tail of a comment does not.
        // [GIVEN] A job task linked to a Jira issue, and a worklog comment of 2100 characters
        Stem := BCJTestLibrary.NewStem();
        JiraIssueId := Stem;
        TimeEntryId := Stem + '-W1';
        JobNo := CreateTaskForIssue(Stem, JiraIssueId);
        LongComment := MakeDescription(2100);
        // [WHEN] The worklog is synced for the first time
        Synced := ProcessJiraQueue.SyncJobTimeEntry(TimeEntryId, JiraIssueId, Stem + 'RES', WorklogPostingDate(), '3600', LongComment);
        // [THEN] The sync reports success and the entry holds the first 2024 characters
        Assert.IsTrue(Synced, 'Syncing a worklog whose comment is longer than 2024 characters must succeed, not fail');
        Assert.IsTrue(TimeEntry.Get(TimeEntryId, JiraIssueId), 'An over-long worklog comment must not prevent the time entry from being created');
        Assert.AreEqual(CopyStr(LongComment, 1, 2024), TimeEntry.Comment, 'Comment must hold the first 2024 characters of the Jira worklog comment');
        Assert.AreEqual(2024, StrLen(TimeEntry.Comment), 'A 2100-character worklog comment must be stored truncated to exactly 2024 characters');
        Assert.AreEqual(JobNo, TimeEntry."Project No.", 'A truncated comment must not stop the entry from being linked to the project of the Jira issue');
        Assert.AreEqual('T1', TimeEntry."Project Task No.", 'A truncated comment must not stop the entry from being linked to the task of the Jira issue');
        Assert.AreEqual(3600, TimeEntry."Time Spend Seconds", 'The worklog duration must be stored even when the comment had to be truncated');
    end;

    [Test]
    procedure SyncJobTimeEntryTruncatesLongCommentOnUpdate()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        ExistingEntry: Record "BCJ Project Time Entry";
        Stem: Code[13];
        JiraIssueId: Code[20];
        TimeEntryId: Code[20];
        LongComment: Text;
        Synced: Boolean;
    begin
        // [SCENARIO] A full sync re-reads worklogs BC already has, so editing a worklog comment in
        // Jira to something long lands on the update path. The production crash was in a full sync;
        // fixing only the insert path would leave the run dying on the second pass instead of the
        // first, which is the same outage with a longer fuse.
        // [GIVEN] A worklog already synced with a short comment
        Stem := BCJTestLibrary.NewStem();
        JiraIssueId := Stem;
        TimeEntryId := Stem + '-W1';
        CreateTaskForIssue(Stem, JiraIssueId);
        ProcessJiraQueue.SyncJobTimeEntry(TimeEntryId, JiraIssueId, Stem + 'RES', WorklogPostingDate(), '3600', 'Short worklog comment');
        LongComment := MakeDescription(2100);
        // [WHEN] The same worklog is synced again with a 2100-character comment
        Synced := ProcessJiraQueue.SyncJobTimeEntry(TimeEntryId, JiraIssueId, Stem + 'RES', WorklogPostingDate(), '7200', LongComment);
        // [THEN] The sync succeeds and the one existing entry now holds the first 2024 characters
        Assert.IsTrue(Synced, 'Re-syncing an existing worklog with an over-long comment must succeed, not fail');
        TimeEntry.Get(TimeEntryId, JiraIssueId);
        Assert.AreEqual(CopyStr(LongComment, 1, 2024), TimeEntry.Comment, 'An updated entry must hold the first 2024 characters of the new worklog comment');
        Assert.AreEqual(2024, StrLen(TimeEntry.Comment), 'A 2100-character worklog comment must be stored truncated to exactly 2024 characters on update');
        Assert.AreEqual(7200, TimeEntry."Time Spend Seconds", 'A re-synced worklog must take the duration from the latest sync');
        ExistingEntry.SetRange("Jira ID", TimeEntryId);
        Assert.AreEqual(1, ExistingEntry.Count(), 'Re-syncing a worklog must update the entry it already has, not add a second one');
    end;

    [Test]
    procedure SyncJobTimeEntryTruncatesLongResourceName()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Resource: Record Resource;
        Stem: Code[13];
        JiraIssueId: Code[20];
        TimeEntryId: Code[20];
        LongResourceName: Text;
        Synced: Boolean;
    begin
        // [SCENARIO] The worklog author arrives as a Jira display name, which people set freely -
        // full names with titles run well past Resource.Name's Text[100]. The sync derives both the
        // resource No. (Code[20]) and its Name from that one string, so the long name must be cut to
        // fit rather than stopping the run. The No. is the first 20 characters because that is what
        // ties every later worklog from the same author to the same resource - it has to be
        // derived the same way every time, not once per sync.
        // [GIVEN] A job task linked to a Jira issue and an author display name of 133 characters
        Stem := BCJTestLibrary.NewStem();
        JiraIssueId := Stem;
        TimeEntryId := Stem + '-W1';
        CreateTaskForIssue(Stem, JiraIssueId);
        LongResourceName := Stem + MakeDescription(120);
        // [WHEN] The worklog is synced for that author
        Synced := ProcessJiraQueue.SyncJobTimeEntry(TimeEntryId, JiraIssueId, LongResourceName, WorklogPostingDate(), '3600', 'Worklog by a long-named author');
        // [THEN] The entry points at a resource whose No. and Name are the name cut to fit
        Assert.IsTrue(Synced, 'Syncing a worklog whose author name is longer than 100 characters must succeed, not fail');
        Assert.IsTrue(TimeEntry.Get(TimeEntryId, JiraIssueId), 'An over-long author name must not prevent the time entry from being created');
        Assert.AreEqual(CopyStr(LongResourceName, 1, 20), TimeEntry."BC Resource No.", 'The entry must point at the resource named by the first 20 characters of the Jira author name');
        Assert.IsTrue(Resource.Get(CopyStr(LongResourceName, 1, 20)), 'The sync must create the resource for a Jira author it has not seen before');
        Assert.AreEqual(CopyStr(LongResourceName, 1, 100), Resource.Name, 'Resource Name must hold the first 100 characters of the Jira author display name');
        Assert.AreEqual(100, StrLen(Resource.Name), 'A 133-character author display name must be stored truncated to exactly 100 characters');
        Assert.AreEqual(Resource.Type::Person, Resource.Type, 'A resource created from a Jira author is a person, not a machine');
    end;

    [Test]
    procedure SyncJobTimeEntryKeepsShortComment()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Stem: Code[13];
        JiraIssueId: Code[20];
        TimeEntryId: Code[20];
        BoundaryComment: Text;
    begin
        // [SCENARIO] 2024 characters is the last length that still fits, so it is where an
        // off-by-one in the truncation would show. Worklog comments are what the customer reads
        // when querying an invoice line, so anything that fits today must keep arriving whole -
        // the fix must not start silently shortening comments that were never a problem.
        // [GIVEN] A job task linked to a Jira issue and a comment of exactly 2024 characters
        Stem := BCJTestLibrary.NewStem();
        JiraIssueId := Stem;
        TimeEntryId := Stem + '-W1';
        CreateTaskForIssue(Stem, JiraIssueId);
        BoundaryComment := MakeDescription(2024);
        // [WHEN] The worklog is synced
        ProcessJiraQueue.SyncJobTimeEntry(TimeEntryId, JiraIssueId, Stem + 'RES', WorklogPostingDate(), '3600', BoundaryComment);
        // [THEN] The comment is stored character for character
        TimeEntry.Get(TimeEntryId, JiraIssueId);
        Assert.AreEqual(BoundaryComment, TimeEntry.Comment, 'A worklog comment of exactly 2024 characters must be stored unchanged');
        Assert.AreEqual(2024, StrLen(TimeEntry.Comment), 'A worklog comment of exactly 2024 characters must keep all 2024 characters');
    end;

    // ---------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------

    local procedure CreateTaskForIssue(Stem: Code[13]; JiraIssueId: Code[20]): Code[20]
    var
        JobNo: Code[20];
    begin
        // The worklog sync resolves project and task from the Jira issue id on the job task, and
        // reads the Projects setup singleton, so both have to be in place before it is called.
        JobNo := CreateJob(Stem);
        BCJTestLibrary.CreateJobTask(JobNo, 'T1', 'Task ' + Stem, 'IN PROGRESS');
        BCJTestLibrary.SetJobTaskJiraId(JobNo, 'T1', JiraIssueId);
        BCJTestLibrary.EnsureJobsSetup();
        exit(JobNo);
    end;

    local procedure WorklogPostingDate(): Text
    begin
        // The sync takes the worklog timestamp as opaque text and parses it itself; these tests are
        // about lengths, not dates, so they hand it a value it can parse and assert nothing on it.
        exit(Format(CreateDateTime(BCJTestLibrary.BaseDate(), 120000T)));
    end;

    local procedure CreateJob(Stem: Code[13]): Code[20]
    var
        JobNo: Code[20];
    begin
        JobNo := Stem + 'P';
        BCJTestLibrary.CreateJob(JobNo, '', 'Project ' + Stem);
        exit(JobNo);
    end;

    local procedure MakeDescription(Length: Integer) Result: Text
    var
        Builder: TextBuilder;
        Pattern: Text;
        i: Integer;
    begin
        // Deterministic filler: 'ABCDEFGHIJ' repeated, so the exact length is what the caller asked
        // for and the expected value never depends on counting characters in a literal.
        Pattern := 'ABCDEFGHIJ';
        for i := 1 to Length do
            Builder.Append(CopyStr(Pattern, 1 + (i - 1) mod StrLen(Pattern), 1));
        Result := Builder.ToText();
    end;
}
