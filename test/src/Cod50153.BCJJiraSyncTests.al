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
    // Helpers
    // ---------------------------------------------------------------------------------

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
