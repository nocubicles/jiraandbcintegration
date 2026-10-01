codeunit 50151 "BCJ Billing Overview Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    // Standard scenario (built fresh by CreateScenario in every test; D = BaseDate):
    //
    //   Customer ''  (no Bill-to)
    //     JobN  T1   E8 D   0.25 Not Billable | E9 D   0.75 Open
    //   Customer CustA
    //     JobA1 T1   E1 D+1 2.00 Open | E2 D 1.50 Billable | E3 D 0.50 Not Billable
    //     JobA1 T2   E4 D   3.00 Billed
    //     JobA2 T1   E5 D   4.00 Open
    //   Customer CustB
    //     JobB  T1   E6 D   1.00 Billable | E7 D+2 2.00 Billed
    //
    // Entry states are reached through the real overview actions (BCJ Test Library CreateTimeEntry
    // drives SetBillingStatus), so every entry holds all its hours in the one bucket named above.
    //
    // All keys derive from a fresh GUID stem, and every TimeEntryFilter is constrained to
    // "Project No." = Stem* so real synced Jira data in the sandbox never enters the result.

    var
        BCJTestLibrary: Codeunit "BCJ Test Library";
        Assert: Codeunit "Library Assert";
        OverviewMgt: Codeunit "BCJ Billing Overview Mgt.";
        Stem: Code[13];
        CustA: Code[20];
        CustB: Code[20];
        JobA1: Code[20];
        JobA2: Code[20];
        JobB: Code[20];
        JobN: Code[20];
        LineType: Enum "BCJ Overview Line Type";

    // ---------------------------------------------------------------------------------
    // BuildOverview - structure
    // ---------------------------------------------------------------------------------

    [Test]
    procedure BuildOverviewWithoutTimeEntriesBuildsCustomerProjectTaskTree()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] The overview is read top-down like an invoice proposal: customer, then its
        // projects, then tasks. Order and indentation are what make the page readable as a tree;
        // projects without a Bill-to customer are grouped under one blank customer sorted first,
        // so unassigned work is the first thing the reviewer sees.
        // [GIVEN] The standard scenario
        CreateScenario();
        FilterOwnProjects(TimeEntryFilter);
        // [WHEN] BuildOverview without time entry lines
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, false);
        // [THEN] 12 lines in customer/project/task order, no time entry lines
        Assert.AreEqual(12, Buffer.Count(), 'Tree without time entries must contain exactly 3 customers, 4 projects and 5 tasks');
        Buffer.Reset();
        Buffer.SetCurrentKey("Entry No.");
        Buffer.FindSet();
        AssertLineAndNext(Buffer, LineType::Customer, '', '', '', '');
        AssertLineAndNext(Buffer, LineType::Project, '', JobN, '', '');
        AssertLineAndNext(Buffer, LineType::Task, '', JobN, 'T1', '');
        AssertLineAndNext(Buffer, LineType::Customer, CustA, '', '', '');
        AssertLineAndNext(Buffer, LineType::Project, CustA, JobA1, '', '');
        AssertLineAndNext(Buffer, LineType::Task, CustA, JobA1, 'T1', '');
        AssertLineAndNext(Buffer, LineType::Task, CustA, JobA1, 'T2', '');
        AssertLineAndNext(Buffer, LineType::Project, CustA, JobA2, '', '');
        AssertLineAndNext(Buffer, LineType::Task, CustA, JobA2, 'T1', '');
        AssertLineAndNext(Buffer, LineType::Customer, CustB, '', '', '');
        AssertLineAndNext(Buffer, LineType::Project, CustB, JobB, '', '');
        AssertLineAndNext(Buffer, LineType::Task, CustB, JobB, 'T1', '');
        Buffer.Reset();
        Buffer.SetRange("Line Type", LineType::"Time Entry");
        Assert.IsTrue(Buffer.IsEmpty(), 'No Time Entry lines may be created when IncludeTimeEntries is false');
    end;

    [Test]
    procedure BuildOverviewWithTimeEntriesOrdersEntriesByDateThenJiraId()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] With time entries shown, worklogs appear under their task in chronological
        // order (ties broken by Jira ID) so the reviewer can match them against the Jira timeline.
        // [GIVEN] The standard scenario
        CreateScenario();
        FilterOwnProjects(TimeEntryFilter);
        // [WHEN] BuildOverview including time entry lines
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, true);
        // [THEN] 21 lines: 12 tree lines + 9 time entries in date/Jira ID order under their task
        Assert.AreEqual(21, Buffer.Count(), 'Tree with time entries must contain the 12 grouping lines plus the 9 time entries');
        Buffer.Reset();
        Buffer.SetCurrentKey("Entry No.");
        Buffer.FindSet();
        AssertLineAndNext(Buffer, LineType::Customer, '', '', '', '');
        AssertLineAndNext(Buffer, LineType::Project, '', JobN, '', '');
        AssertLineAndNext(Buffer, LineType::Task, '', JobN, 'T1', '');
        AssertLineAndNext(Buffer, LineType::"Time Entry", '', JobN, 'T1', JiraId('E8'));
        AssertLineAndNext(Buffer, LineType::"Time Entry", '', JobN, 'T1', JiraId('E9'));
        AssertLineAndNext(Buffer, LineType::Customer, CustA, '', '', '');
        AssertLineAndNext(Buffer, LineType::Project, CustA, JobA1, '', '');
        AssertLineAndNext(Buffer, LineType::Task, CustA, JobA1, 'T1', '');
        AssertLineAndNext(Buffer, LineType::"Time Entry", CustA, JobA1, 'T1', JiraId('E2'));
        AssertLineAndNext(Buffer, LineType::"Time Entry", CustA, JobA1, 'T1', JiraId('E3'));
        AssertLineAndNext(Buffer, LineType::"Time Entry", CustA, JobA1, 'T1', JiraId('E1'));
        AssertLineAndNext(Buffer, LineType::Task, CustA, JobA1, 'T2', '');
        AssertLineAndNext(Buffer, LineType::"Time Entry", CustA, JobA1, 'T2', JiraId('E4'));
        AssertLineAndNext(Buffer, LineType::Project, CustA, JobA2, '', '');
        AssertLineAndNext(Buffer, LineType::Task, CustA, JobA2, 'T1', '');
        AssertLineAndNext(Buffer, LineType::"Time Entry", CustA, JobA2, 'T1', JiraId('E5'));
        AssertLineAndNext(Buffer, LineType::Customer, CustB, '', '', '');
        AssertLineAndNext(Buffer, LineType::Project, CustB, JobB, '', '');
        AssertLineAndNext(Buffer, LineType::Task, CustB, JobB, 'T1', '');
        AssertLineAndNext(Buffer, LineType::"Time Entry", CustB, JobB, 'T1', JiraId('E6'));
        AssertLineAndNext(Buffer, LineType::"Time Entry", CustB, JobB, 'T1', JiraId('E7'));
    end;

    [Test]
    procedure BuildOverviewGroupsAllProjectsWithoutBillToUnderOneBlankCustomer()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        TimeEntry: Record "BCJ Project Time Entry";
        JobN2: Code[20];
    begin
        // [SCENARIO] Internal/unassigned projects have no Bill-to customer. They must collect under a
        // single blank-customer node, not one blank node per project, or the tree fragments and the
        // "unassigned" total is split across several rows.
        // [GIVEN] The standard scenario plus a second project without Bill-to customer
        CreateScenario();
        JobN2 := Stem + 'P5';
        BCJTestLibrary.CreateJob(JobN2, '', 'Project N2 ' + Stem);
        BCJTestLibrary.CreateJobTask(JobN2, 'T1', 'Task N2 ' + Stem, '');
        BCJTestLibrary.CreateTimeEntry(TimeEntry, JiraId('E10'), JobN2, 'T1', Stem, BCJTestLibrary.BaseDate(), 5, "BCJ Billing Status"::Open);
        FilterOwnProjects(TimeEntryFilter);
        // [WHEN] BuildOverview
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, false);
        // [THEN] Exactly one blank customer line, holding both projects and both projects' hours
        Buffer.SetRange("Line Type", LineType::Customer);
        Buffer.SetRange("Customer No.", '');
        Assert.AreEqual(1, Buffer.Count(), 'Projects without Bill-to customer must share exactly one blank customer line');
        Buffer.FindFirst();
        Assert.AreEqual(6.0, Buffer."Total Hours", 'Blank customer line must total the hours of all projects without Bill-to customer');
        Buffer.Reset();
        Buffer.SetRange("Line Type", LineType::Project);
        Buffer.SetRange("Customer No.", '');
        Assert.AreEqual(2, Buffer.Count(), 'Both projects without Bill-to customer must appear under the blank customer');
    end;

    [Test]
    procedure BuildOverviewRespectsBillingStatusFilterAndPrunesEmptyNodes()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] Filtering the overview on Open is how the reviewer finds work still to decide on.
        // Customers, projects and tasks with nothing Open must disappear entirely - an empty node
        // with zero hours is noise that hides the rows that need attention.
        // [GIVEN] The standard scenario, filtered to Open entries (E1, E5, E9)
        CreateScenario();
        FilterOwnProjects(TimeEntryFilter);
        TimeEntryFilter.SetRange("Billing Status", "BCJ Billing Status"::Open);
        // [WHEN] BuildOverview
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, false);
        // [THEN] Only nodes with Open entries exist; CustB and JobA1/T2 are pruned
        Assert.AreEqual(8, Buffer.Count(), 'Only customers/projects/tasks with Open entries may be created');
        Buffer.Reset();
        Buffer.SetCurrentKey("Entry No.");
        Buffer.FindSet();
        AssertLineAndNext(Buffer, LineType::Customer, '', '', '', '');
        AssertLineAndNext(Buffer, LineType::Project, '', JobN, '', '');
        AssertLineAndNext(Buffer, LineType::Task, '', JobN, 'T1', '');
        AssertLineAndNext(Buffer, LineType::Customer, CustA, '', '', '');
        AssertLineAndNext(Buffer, LineType::Project, CustA, JobA1, '', '');
        AssertLineAndNext(Buffer, LineType::Task, CustA, JobA1, 'T1', '');
        AssertLineAndNext(Buffer, LineType::Project, CustA, JobA2, '', '');
        AssertLineAndNext(Buffer, LineType::Task, CustA, JobA2, 'T1', '');
        FindLine(Buffer, LineType::Customer, CustA, '', '', '');
        AssertHours(Buffer, 6, 6, 0, 0, 0, 6, 'Customer A filtered to Open');
    end;

    [Test]
    procedure BuildOverviewRespectsPostingDateFilterAndPrunesEmptyNodes()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] Billing is done per period. Hours posted outside the period must not count
        // toward any total, and nodes with no hours in the period must not be shown.
        // [GIVEN] The standard scenario, filtered to D+1..D+2 (E1 and E7 only)
        CreateScenario();
        FilterOwnProjects(TimeEntryFilter);
        TimeEntryFilter.SetRange("Posting Date", BCJTestLibrary.BaseDate() + 1, BCJTestLibrary.BaseDate() + 2);
        // [WHEN] BuildOverview
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, false);
        // [THEN] Only CustA/JobA1/T1 and CustB/JobB/T1 remain, with the period's hours only
        Assert.AreEqual(6, Buffer.Count(), 'Only nodes with entries inside the posting date filter may be created');
        Buffer.Reset();
        Buffer.SetCurrentKey("Entry No.");
        Buffer.FindSet();
        AssertLineAndNext(Buffer, LineType::Customer, CustA, '', '', '');
        AssertLineAndNext(Buffer, LineType::Project, CustA, JobA1, '', '');
        AssertLineAndNext(Buffer, LineType::Task, CustA, JobA1, 'T1', '');
        AssertLineAndNext(Buffer, LineType::Customer, CustB, '', '', '');
        AssertLineAndNext(Buffer, LineType::Project, CustB, JobB, '', '');
        AssertLineAndNext(Buffer, LineType::Task, CustB, JobB, 'T1', '');
        FindLine(Buffer, LineType::Customer, CustA, '', '', '');
        AssertHours(Buffer, 2, 2, 0, 0, 0, 2, 'Customer A within date filter');
        FindLine(Buffer, LineType::Customer, CustB, '', '', '');
        AssertHours(Buffer, 2, 0, 0, 0, 2, 0, 'Customer B within date filter');
    end;

    [Test]
    procedure BuildOverviewWithNoMatchingEntriesLeavesBufferEmpty()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] An empty period is a normal situation; the overview must simply be empty,
        // not contain orphan customer/project rows and not raise an error.
        // [GIVEN] The standard scenario and a filter that matches none of its entries
        CreateScenario();
        FilterOwnProjects(TimeEntryFilter);
        TimeEntryFilter.SetRange("Posting Date", BCJTestLibrary.BaseDate() + 100);
        // [WHEN] BuildOverview
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, true);
        // [THEN] Buffer is empty
        Assert.IsTrue(Buffer.IsEmpty(), 'Overview must be empty when no entries match the filters');
    end;

    [Test]
    procedure BuildOverviewEmptiesBufferBeforeRebuilding()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] The page rebuilds the overview on every refresh / filter change using the same
        // buffer. Stale lines from a previous build would duplicate hours and show removed nodes.
        // [GIVEN] A buffer holding a stale line, and the standard scenario
        CreateScenario();
        Buffer.Init();
        Buffer."Entry No." := 100000;
        Buffer."Line Type" := LineType::Customer;
        Buffer."Customer No." := Stem + 'JUNK';
        Buffer."Total Hours" := 99;
        Buffer.Insert();
        FilterOwnProjects(TimeEntryFilter);
        // [WHEN] BuildOverview is called twice
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, false);
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, false);
        // [THEN] The stale line is gone and no line is duplicated
        Buffer.Reset();
        Buffer.SetRange("Customer No.", Stem + 'JUNK');
        Assert.IsTrue(Buffer.IsEmpty(), 'Lines present before BuildOverview must be removed');
        Buffer.Reset();
        Assert.AreEqual(12, Buffer.Count(), 'Rebuilding must not duplicate lines from the previous build');
    end;

    [Test]
    procedure BuildOverviewKeepsFiltersOnTimeEntryFilter()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        ProjectFilterBefore: Text;
        DateFilterBefore: Text;
        StatusFilterBefore: Text;
    begin
        // [SCENARIO] The page keeps TimeEntryFilter and reuses it for SetStatusForLine after the
        // build. If BuildOverview cleared or changed its filters, the next status change would hit
        // entries outside the period the user is looking at.
        // [GIVEN] The standard scenario and filters on project, date and status
        CreateScenario();
        FilterOwnProjects(TimeEntryFilter);
        TimeEntryFilter.SetRange("Posting Date", BCJTestLibrary.BaseDate(), BCJTestLibrary.BaseDate() + 2);
        TimeEntryFilter.SetFilter("Billing Status", '%1|%2', "BCJ Billing Status"::Open, "BCJ Billing Status"::Billable);
        ProjectFilterBefore := TimeEntryFilter.GetFilter("Project No.");
        DateFilterBefore := TimeEntryFilter.GetFilter("Posting Date");
        StatusFilterBefore := TimeEntryFilter.GetFilter("Billing Status");
        // [WHEN] BuildOverview
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, true);
        // [THEN] Filters are unchanged
        Assert.AreEqual(ProjectFilterBefore, TimeEntryFilter.GetFilter("Project No."), 'Project No. filter must be unchanged after BuildOverview');
        Assert.AreEqual(DateFilterBefore, TimeEntryFilter.GetFilter("Posting Date"), 'Posting Date filter must be unchanged after BuildOverview');
        Assert.AreEqual(StatusFilterBefore, TimeEntryFilter.GetFilter("Billing Status"), 'Billing Status filter must be unchanged after BuildOverview');
        Assert.AreEqual(5, TimeEntryFilter.Count(), 'TimeEntryFilter must still select the same entries after BuildOverview');
    end;

    // ---------------------------------------------------------------------------------
    // BuildOverview - hours and descriptions
    // ---------------------------------------------------------------------------------

    [Test]
    procedure BuildOverviewRollsUpHoursByStatusAtEveryLevel()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] The overview replaces manual spreadsheets for invoice preparation: each row's
        // total and its split by status must equal the sum of the worklogs beneath it, and
        // Unbilled = Open + Billable is the "still to invoice or decide" figure the reviewer acts on.
        // Not Billable and Billed hours are settled and must never count as unbilled.
        // [GIVEN] The standard scenario
        CreateScenario();
        FilterOwnProjects(TimeEntryFilter);
        // [WHEN] BuildOverview including time entries
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, true);
        // [THEN] Every level sums correctly (Total, Open, Billable, Not Billable, Billed, Unbilled)
        FindLine(Buffer, LineType::Customer, '', '', '', '');
        AssertHours(Buffer, 1, 0.75, 0, 0.25, 0, 0.75, 'Blank customer');
        FindLine(Buffer, LineType::Customer, CustA, '', '', '');
        AssertHours(Buffer, 11, 6, 1.5, 0.5, 3, 7.5, 'Customer A');
        FindLine(Buffer, LineType::Customer, CustB, '', '', '');
        AssertHours(Buffer, 3, 0, 1, 0, 2, 1, 'Customer B');
        FindLine(Buffer, LineType::Project, CustA, JobA1, '', '');
        AssertHours(Buffer, 7, 2, 1.5, 0.5, 3, 3.5, 'Project A1');
        FindLine(Buffer, LineType::Project, CustA, JobA2, '', '');
        AssertHours(Buffer, 4, 4, 0, 0, 0, 4, 'Project A2');
        FindLine(Buffer, LineType::Task, CustA, JobA1, 'T1', '');
        AssertHours(Buffer, 4, 2, 1.5, 0.5, 0, 3.5, 'Task A1/T1');
        FindLine(Buffer, LineType::Task, CustA, JobA1, 'T2', '');
        AssertHours(Buffer, 3, 0, 0, 0, 3, 0, 'Task A1/T2');
        FindLine(Buffer, LineType::"Time Entry", CustA, JobA1, 'T1', JiraId('E2'));
        AssertHours(Buffer, 1.5, 0, 1.5, 0, 0, 1.5, 'Time entry E2 (Billable)');
        FindLine(Buffer, LineType::"Time Entry", CustA, JobA1, 'T1', JiraId('E3'));
        AssertHours(Buffer, 0.5, 0, 0, 0.5, 0, 0, 'Time entry E3 (Not Billable)');
        FindLine(Buffer, LineType::"Time Entry", CustB, JobB, 'T1', JiraId('E7'));
        AssertHours(Buffer, 2, 0, 0, 0, 2, 0, 'Time entry E7 (Billed)');
    end;

    [Test]
    procedure BuildOverviewPopulatesDescriptionsAndKeys()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] Each row must be recognisable without drilling down: the customer's name, the
        // project and task descriptions from BC, the Jira issue status on the task (is the work
        // actually done?), and on worklog rows the worklog comment and identifying keys that the
        // status actions use.
        // [GIVEN] The standard scenario
        CreateScenario();
        FilterOwnProjects(TimeEntryFilter);
        // [WHEN] BuildOverview including time entries
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, true);
        // [THEN] Descriptions and keys come from the right sources
        FindLine(Buffer, LineType::Customer, CustA, '', '', '');
        Assert.AreEqual('Customer A ' + Stem, Buffer.Description, 'Customer line description must be the customer name');
        Assert.AreEqual(0, Buffer.Indentation, 'Customer line must have indentation 0');
        FindLine(Buffer, LineType::Customer, '', '', '', '');
        Assert.AreNotEqual('', Buffer.Description, 'Blank customer line must have a non-empty description');
        FindLine(Buffer, LineType::Project, CustA, JobA1, '', '');
        Assert.AreEqual('Project A1 ' + Stem, Buffer.Description, 'Project line description must be the job description');
        Assert.AreEqual(1, Buffer.Indentation, 'Project line must have indentation 1');
        FindLine(Buffer, LineType::Task, CustA, JobA1, 'T1', '');
        Assert.AreEqual('Task A1-T1 ' + Stem, Buffer.Description, 'Task line description must be the job task description');
        Assert.AreEqual('IN PROGRESS', Buffer."Jira Status", 'Task line Jira Status must come from the job task BCJ Jira Status');
        Assert.AreEqual(2, Buffer.Indentation, 'Task line must have indentation 2');
        FindLine(Buffer, LineType::Task, CustA, JobA1, 'T2', '');
        Assert.AreEqual('DONE', Buffer."Jira Status", 'Task line Jira Status must come from its own job task');
        FindLine(Buffer, LineType::"Time Entry", CustA, JobA1, 'T1', JiraId('E1'));
        Assert.AreEqual('Worklog ' + JiraId('E1'), Buffer.Description, 'Time entry line description must be the worklog comment');
        Assert.AreEqual(3, Buffer.Indentation, 'Time entry line must have indentation 3');
        Assert.AreEqual('I-' + JiraId('E1'), Buffer."Jira Issue Id", 'Time entry line must carry the Jira Issue Id');
        Assert.AreEqual(Stem, Buffer."Resource No.", 'Time entry line must carry the resource');
        Assert.AreEqual(BCJTestLibrary.BaseDate() + 1, Buffer."Posting Date", 'Time entry line must carry the posting date');
        Assert.AreEqual("BCJ Billing Status"::Open, Buffer."Billing Status", 'Time entry line must carry the entry billing status');
        FindLine(Buffer, LineType::"Time Entry", CustB, JobB, 'T1', JiraId('E7'));
        Assert.AreEqual("BCJ Billing Status"::Billed, Buffer."Billing Status", 'Time entry line must carry the entry billing status');
    end;

    [Test]
    procedure BuildOverviewTruncatesLongWorklogCommentTo250()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        TimeEntry: Record "BCJ Project Time Entry";
        LongComment: Text;
    begin
        // [SCENARIO] Jira worklog comments can be up to 2024 chars but the buffer description is 250.
        // A long comment must be cut to its first 250 characters, not raise an overflow error that
        // would make the whole overview unusable because of one verbose worklog.
        // [GIVEN] The standard scenario with a 300-character comment on E5
        CreateScenario();
        LongComment := PadStr('', 245, 'A') + 'BCDEFGHIJ' + PadStr('', 46, 'Z');
        TimeEntry.Get(JiraId('E5'), 'I-' + JiraId('E5'));
        TimeEntry.Comment := CopyStr(LongComment, 1, MaxStrLen(TimeEntry.Comment));
        TimeEntry.Modify(false);
        FilterOwnProjects(TimeEntryFilter);
        // [WHEN] BuildOverview including time entries
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, true);
        // [THEN] Description holds the first 250 characters
        FindLine(Buffer, LineType::"Time Entry", CustA, JobA2, 'T1', JiraId('E5'));
        Assert.AreEqual(CopyStr(LongComment, 1, 250), Buffer.Description, 'Long worklog comment must be truncated to its first 250 characters');
    end;

    // ---------------------------------------------------------------------------------
    // ApplyLineFilter
    // ---------------------------------------------------------------------------------

    [Test]
    procedure ApplyLineFilterCustomerLineSelectsAllEntriesOfCustomerProjects()
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] Drilling down from a customer row must show every worklog billed to that
        // customer across all its projects - and nothing billed to anyone else.
        // [GIVEN] The standard scenario
        CreateScenario();
        TimeEntry.SetRange("BC Resource No.", Stem);
        // [WHEN] ApplyLineFilter for customer A
        OverviewMgt.ApplyLineFilter(MakeLine(LineType::Customer, CustA, '', '', ''), TimeEntry);
        // [THEN] Exactly E1..E5
        Assert.AreEqual(5, TimeEntry.Count(), 'Customer line must select all entries of the customer''s projects');
        TimeEntry.SetRange("Project No.", JobB);
        Assert.IsTrue(TimeEntry.IsEmpty(), 'Customer line must not select entries of another customer''s project');
    end;

    [Test]
    procedure ApplyLineFilterBlankCustomerLineSelectsProjectsWithoutBillTo()
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] The blank customer row stands for "projects with no Bill-to customer". Its
        // drill-down must return exactly that work; a naive blank filter that matches everything
        // (or nothing) would let the user mark other customers' hours by mistake.
        // [GIVEN] The standard scenario, entries pre-filtered to this test's resource
        CreateScenario();
        TimeEntry.SetRange("BC Resource No.", Stem);
        // [WHEN] ApplyLineFilter for the blank customer
        OverviewMgt.ApplyLineFilter(MakeLine(LineType::Customer, '', '', '', ''), TimeEntry);
        // [THEN] Exactly E8 and E9 of JobN
        Assert.AreEqual(2, TimeEntry.Count(), 'Blank customer line must select only entries of projects without Bill-to customer');
        TimeEntry.SetFilter("Project No.", '<>%1', JobN);
        Assert.IsTrue(TimeEntry.IsEmpty(), 'Blank customer line must not select entries of projects that have a Bill-to customer');
    end;

    [Test]
    procedure ApplyLineFilterProjectLineSelectsThatProject()
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] A project row's drill-down must cover all tasks of that project only.
        // [GIVEN] The standard scenario
        CreateScenario();
        TimeEntry.SetRange("BC Resource No.", Stem);
        // [WHEN] ApplyLineFilter for project A1
        OverviewMgt.ApplyLineFilter(MakeLine(LineType::Project, CustA, JobA1, '', ''), TimeEntry);
        // [THEN] Exactly E1..E4
        Assert.AreEqual(4, TimeEntry.Count(), 'Project line must select all entries of that project across its tasks');
        TimeEntry.SetFilter("Project No.", '<>%1', JobA1);
        Assert.IsTrue(TimeEntry.IsEmpty(), 'Project line must not select entries of other projects');
    end;

    [Test]
    procedure ApplyLineFilterTaskLineSelectsThatProjectTask()
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] Task numbers repeat across projects (every project here has a T1), so a task
        // row must filter on project AND task, or it would pull in other projects' T1 worklogs.
        // [GIVEN] The standard scenario
        CreateScenario();
        TimeEntry.SetRange("BC Resource No.", Stem);
        // [WHEN] ApplyLineFilter for task A1/T1
        OverviewMgt.ApplyLineFilter(MakeLine(LineType::Task, CustA, JobA1, 'T1', ''), TimeEntry);
        // [THEN] Exactly E1..E3
        Assert.AreEqual(3, TimeEntry.Count(), 'Task line must select only entries of that project and task');
    end;

    [Test]
    procedure ApplyLineFilterTimeEntryLineSelectsSingleEntry()
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] A worklog row must act on that one worklog only, identified by its full
        // primary key (Jira ID + Jira Issue Id).
        // [GIVEN] The standard scenario
        CreateScenario();
        TimeEntry.SetRange("BC Resource No.", Stem);
        // [WHEN] ApplyLineFilter for time entry E2
        OverviewMgt.ApplyLineFilter(MakeLine(LineType::"Time Entry", CustA, JobA1, 'T1', JiraId('E2')), TimeEntry);
        // [THEN] Only E2
        Assert.AreEqual(1, TimeEntry.Count(), 'Time entry line must select exactly one entry');
        TimeEntry.FindFirst();
        Assert.AreEqual(JiraId('E2'), TimeEntry."Jira ID", 'Time entry line must select the entry it represents');
    end;

    [Test]
    procedure ApplyLineFilterKeepsExistingFiltersOnOtherFields()
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] The page's period and status filters must survive a drill-down; otherwise
        // "mark customer A billable" within January would also mark February.
        // [GIVEN] The standard scenario, entries pre-filtered to status Open
        CreateScenario();
        TimeEntry.SetRange("BC Resource No.", Stem);
        TimeEntry.SetRange("Billing Status", "BCJ Billing Status"::Open);
        // [WHEN] ApplyLineFilter for customer A
        OverviewMgt.ApplyLineFilter(MakeLine(LineType::Customer, CustA, '', '', ''), TimeEntry);
        // [THEN] Only customer A's Open entries (E1, E5)
        Assert.AreEqual(2, TimeEntry.Count(), 'ApplyLineFilter must keep existing filters on other fields');
    end;

    // ---------------------------------------------------------------------------------
    // SetStatusForLine
    // ---------------------------------------------------------------------------------

    [Test]
    procedure SetStatusForLineRespectsPostingDateFilter()
    var
        TimeEntryFilter: Record "BCJ Project Time Entry";
        Changed: Integer;
    begin
        // [SCENARIO] Marking a task as Billed for January must not mark the same task's February
        // worklogs: they have not been invoiced yet and would silently drop out of the next invoice.
        // Mark Billed bills Billable hours only (hour-allocation contract), so inside the period
        // the written-off worklog stays written off - it was never on the invoice.
        // [GIVEN] The standard scenario, filtered to posting date D
        CreateScenario();
        FilterOwnProjects(TimeEntryFilter);
        TimeEntryFilter.SetRange("Posting Date", BCJTestLibrary.BaseDate());
        // [WHEN] Task A1/T1 is set to Billed
        Changed := OverviewMgt.SetStatusForLine(MakeLine(LineType::Task, CustA, JobA1, 'T1', ''), TimeEntryFilter, "BCJ Billing Status"::Billed);
        // [THEN] E2 (Billable, date D) is Billed; E3 (Not Billable) and E1 (D+1) are untouched
        Assert.AreEqual(1, Changed, 'Only the Billable entry of the task inside the posting date filter may be changed');
        Assert.AreEqual("BCJ Billing Status"::Billed, GetStatus('E2'), 'Billable entry of the task inside the date filter must be Billed');
        Assert.AreEqual("BCJ Billing Status"::"Not Billable", GetStatus('E3'), 'A written-off entry must never be billed by Mark Billed');
        Assert.AreEqual("BCJ Billing Status"::Open, GetStatus('E1'), 'Entry of the same task outside the date filter must stay Open');
        Assert.AreEqual("BCJ Billing Status"::Open, GetStatus('E5'), 'Entry of another project must stay untouched');
    end;

    [Test]
    procedure SetStatusForLineCountExcludesEntriesAlreadyInStatus()
    var
        TimeEntryFilter: Record "BCJ Project Time Entry";
        Stored: Record "BCJ Project Time Entry";
        Changed: Integer;
    begin
        // [SCENARIO] The returned count feeds the "N entries updated" message; entries already in
        // the target status were not updated and must not be counted. Flags must follow the status.
        // [GIVEN] The standard scenario (customer B: E6 Billable, E7 Billed)
        CreateScenario();
        FilterOwnProjects(TimeEntryFilter);
        // [WHEN] Customer B is set to Billed
        Changed := OverviewMgt.SetStatusForLine(MakeLine(LineType::Customer, CustB, '', '', ''), TimeEntryFilter, "BCJ Billing Status"::Billed);
        // [THEN] Only E6 counted; both Billed with legacy flags set
        Assert.AreEqual(1, Changed, 'Entries already Billed must not be counted as changed');
        Stored.Get(JiraId('E6'), 'I-' + JiraId('E6'));
        Assert.AreEqual("BCJ Billing Status"::Billed, Stored."Billing Status", 'Billable entry of customer B must become Billed');
        Assert.IsTrue(Stored."Is Billed", 'Entry set to Billed via the overview must have Is Billed set');
        Assert.IsTrue(Stored."Is Billable", 'Entry set to Billed via the overview must have Is Billable set');
        Assert.AreEqual("BCJ Billing Status"::Billed, GetStatus('E7'), 'Already Billed entry must stay Billed');
    end;

    [Test]
    procedure SetStatusForLineCustomerLineLeavesOtherCustomersUntouched()
    var
        TimeEntryFilter: Record "BCJ Project Time Entry";
        Changed: Integer;
    begin
        // [SCENARIO] Acting on one customer's row must never change another customer's or the
        // unassigned projects' worklogs. Mark Not Billable writes off Open hours only
        // (hour-allocation contract), so customer A's approved and invoiced hours stand.
        // [GIVEN] The standard scenario
        CreateScenario();
        FilterOwnProjects(TimeEntryFilter);
        // [WHEN] Customer A is set to Not Billable
        Changed := OverviewMgt.SetStatusForLine(MakeLine(LineType::Customer, CustA, '', '', ''), TimeEntryFilter, "BCJ Billing Status"::"Not Billable");
        // [THEN] E1 and E5 (the Open ones) changed; E2 Billable and E4 Billed kept; other customers untouched
        Assert.AreEqual(2, Changed, 'Only customer A''s entries with Open hours may be changed');
        Assert.AreEqual("BCJ Billing Status"::"Not Billable", GetStatus('E1'), 'Customer A''s Open entry must be written off');
        Assert.AreEqual("BCJ Billing Status"::"Not Billable", GetStatus('E5'), 'Customer A''s Open entry must be written off');
        Assert.AreEqual("BCJ Billing Status"::Billable, GetStatus('E2'), 'Customer A''s Billable entry must not be written off');
        Assert.AreEqual("BCJ Billing Status"::Billed, GetStatus('E4'), 'Customer A''s Billed entry must never be written off');
        Assert.AreEqual("BCJ Billing Status"::Billable, GetStatus('E6'), 'Customer B''s entry must stay untouched');
        Assert.AreEqual("BCJ Billing Status"::Open, GetStatus('E9'), 'Unassigned project''s entry must stay untouched');
    end;

    [Test]
    procedure SetStatusForLineBlankCustomerChangesOnlyProjectsWithoutBillTo()
    var
        TimeEntryFilter: Record "BCJ Project Time Entry";
        Changed: Integer;
    begin
        // [SCENARIO] Marking the unassigned (blank customer) row must affect only projects without
        // a Bill-to customer - never real customers' hours.
        // [GIVEN] The standard scenario
        CreateScenario();
        FilterOwnProjects(TimeEntryFilter);
        // [WHEN] The blank customer is set to Billable
        Changed := OverviewMgt.SetStatusForLine(MakeLine(LineType::Customer, '', '', '', ''), TimeEntryFilter, "BCJ Billing Status"::Billable);
        // [THEN] E9 (Open) changed; E8 stays written off (Billable moves Open hours only); customer A untouched
        Assert.AreEqual(1, Changed, 'Only the Open entry of the project without Bill-to customer may be changed');
        Assert.AreEqual("BCJ Billing Status"::"Not Billable", GetStatus('E8'), 'A written-off entry must not be made Billable by Mark Billable');
        Assert.AreEqual("BCJ Billing Status"::Billable, GetStatus('E9'), 'Unassigned project Open entry must become Billable');
        Assert.AreEqual("BCJ Billing Status"::Open, GetStatus('E1'), 'Customer A''s entry must stay untouched');
    end;

    // ---------------------------------------------------------------------------------
    // BuildOverview with a Show view (ViewFilter) - the tree never loses nodes
    //
    // The page puts date/customer/project filters on TimeEntryFilter and the Show view on
    // ViewFilter. Customer/project/task lines and their totals come from TimeEntryFilter alone;
    // ViewFilter only decides which worklog lines are listed.
    // ---------------------------------------------------------------------------------

    [Test]
    procedure BuildOverviewUnbilledViewKeepsProjectWhoseHoursAreAllWrittenOff()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        ViewFilter: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] Reported bug: with Show = Unbilled a project vanished from the overview the
        // moment its last unbilled hours were marked Not Billable. The user decided every customer
        // and project must stay in the tree whichever Show view is selected - the view only narrows
        // the worklog lines. The project row must then show Unbilled 0 (that is the answer the
        // reviewer is looking for), with its written-off hours still counted, and no worklog lines.
        // [GIVEN] The standard scenario with E9 written off, so project N holds only Not Billable hours
        CreateScenario();
        BCJTestLibrary.MarkEntryById(JiraId('E9'), "BCJ Billing Status"::"Not Billable");
        FilterOwnProjects(TimeEntryFilter);
        ViewFilter.SetFilter("Unbilled Hours", '<>0');
        // [WHEN] BuildOverview with the Unbilled view, including time entries
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, ViewFilter, true);
        // [THEN] Project N, its task and the blank customer stay, with Unbilled 0 and no worklog lines
        FindLine(Buffer, LineType::Customer, '', '', '', '');
        AssertAllHours(Buffer, 1, 0, 0, 0, 1, 0, 0, 'Blank customer under Unbilled view');
        FindLine(Buffer, LineType::Project, '', JobN, '', '');
        AssertAllHours(Buffer, 1, 0, 0, 0, 1, 0, 0, 'Fully written-off project N under Unbilled view');
        FindLine(Buffer, LineType::Task, '', JobN, 'T1', '');
        AssertAllHours(Buffer, 1, 0, 0, 0, 1, 0, 0, 'Task N/T1 under Unbilled view');
        Assert.AreEqual(0, CountEntryLines(Buffer, JobN), 'A project without unbilled hours must list no worklog lines under the Unbilled view');
    end;

    [Test]
    procedure BuildOverviewUnbilledViewKeepsWholeTreeInOrderAndListsOnlyUnbilledEntries()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        ViewFilter: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] The whole tree - every customer, project and task within the period - stays in
        // the same order and indentation as without a view; only worklogs with unbilled hours are
        // listed beneath it (Not Billable and Billed worklogs are settled and hidden by this view).
        // Task A1/T2 (only Billed) and project N (only written off) keep their rows without entries.
        // [GIVEN] The standard scenario with E9 written off
        CreateScenario();
        BCJTestLibrary.MarkEntryById(JiraId('E9'), "BCJ Billing Status"::"Not Billable");
        FilterOwnProjects(TimeEntryFilter);
        ViewFilter.SetFilter("Unbilled Hours", '<>0');
        // [WHEN] BuildOverview with the Unbilled view, including time entries
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, ViewFilter, true);
        // [THEN] 12 tree lines + 4 unbilled worklogs (E2, E1, E5, E6), in tree order
        Assert.AreEqual(16, Buffer.Count(), 'Unbilled view must keep all 12 tree lines and list only the 4 worklogs with unbilled hours');
        Buffer.Reset();
        Buffer.SetCurrentKey("Entry No.");
        Buffer.FindSet();
        AssertLineAndNext(Buffer, LineType::Customer, '', '', '', '');
        AssertLineAndNext(Buffer, LineType::Project, '', JobN, '', '');
        AssertLineAndNext(Buffer, LineType::Task, '', JobN, 'T1', '');
        AssertLineAndNext(Buffer, LineType::Customer, CustA, '', '', '');
        AssertLineAndNext(Buffer, LineType::Project, CustA, JobA1, '', '');
        AssertLineAndNext(Buffer, LineType::Task, CustA, JobA1, 'T1', '');
        AssertLineAndNext(Buffer, LineType::"Time Entry", CustA, JobA1, 'T1', JiraId('E2'));
        AssertLineAndNext(Buffer, LineType::"Time Entry", CustA, JobA1, 'T1', JiraId('E1'));
        AssertLineAndNext(Buffer, LineType::Task, CustA, JobA1, 'T2', '');
        AssertLineAndNext(Buffer, LineType::Project, CustA, JobA2, '', '');
        AssertLineAndNext(Buffer, LineType::Task, CustA, JobA2, 'T1', '');
        AssertLineAndNext(Buffer, LineType::"Time Entry", CustA, JobA2, 'T1', JiraId('E5'));
        AssertLineAndNext(Buffer, LineType::Customer, CustB, '', '', '');
        AssertLineAndNext(Buffer, LineType::Project, CustB, JobB, '', '');
        AssertLineAndNext(Buffer, LineType::Task, CustB, JobB, 'T1', '');
        AssertLineAndNext(Buffer, LineType::"Time Entry", CustB, JobB, 'T1', JiraId('E6'));
        // [THEN] Group totals still include the hidden settled worklogs
        FindLine(Buffer, LineType::Task, CustA, JobA1, 'T2', '');
        AssertAllHours(Buffer, 3, 0, 0, 0, 0, 3, 0, 'Task A1/T2 (only Billed) under Unbilled view');
        FindLine(Buffer, LineType::Customer, CustA, '', '', '');
        AssertAllHours(Buffer, 11, 6, 0, 1.5, 0.5, 3, 7.5, 'Customer A under Unbilled view');
        FindLine(Buffer, LineType::Customer, CustB, '', '', '');
        AssertAllHours(Buffer, 3, 0, 0, 1, 0, 2, 1, 'Customer B under Unbilled view');
    end;

    [Test]
    procedure BuildOverviewUnbilledViewTotalsBothEntriesButListsOnlyTheUnbilledOne()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        ViewFilter: Record "BCJ Project Time Entry";
        TimeEntry: Record "BCJ Project Time Entry";
        JobM: Code[20];
    begin
        // [SCENARIO] The project row is the reviewer's summary of the period: it must show all the
        // hours logged (2 still open plus 1 written off = 3), not only those the view lists. The
        // worklog lines under it follow the view, and the listed line carries its own buckets.
        // [GIVEN] The standard scenario plus project M (customer B) with one Open 2 h worklog
        // and one written-off 1 h worklog
        CreateScenario();
        JobM := Stem + 'P5';
        BCJTestLibrary.CreateJob(JobM, CustB, 'Project M ' + Stem);
        BCJTestLibrary.CreateJobTask(JobM, 'T1', 'Task M-T1 ' + Stem, 'IN PROGRESS');
        BCJTestLibrary.CreateTimeEntry(TimeEntry, JiraId('M1'), JobM, 'T1', Stem, BCJTestLibrary.BaseDate(), 2, "BCJ Billing Status"::Open);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, JiraId('M2'), JobM, 'T1', Stem, BCJTestLibrary.BaseDate(), 1, "BCJ Billing Status"::"Not Billable");
        FilterOwnProjects(TimeEntryFilter);
        ViewFilter.SetFilter("Unbilled Hours", '<>0');
        // [WHEN] BuildOverview with the Unbilled view, including time entries
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, ViewFilter, true);
        // [THEN] Project and task total both worklogs
        FindLine(Buffer, LineType::Project, CustB, JobM, '', '');
        AssertAllHours(Buffer, 3, 2, 0, 0, 1, 0, 2, 'Project M under Unbilled view');
        FindLine(Buffer, LineType::Task, CustB, JobM, 'T1', '');
        AssertAllHours(Buffer, 3, 2, 0, 0, 1, 0, 2, 'Task M/T1 under Unbilled view');
        // [THEN] Only the unbilled worklog is listed, with its own buckets
        Assert.AreEqual(1, CountEntryLines(Buffer, JobM), 'Only the worklog with unbilled hours may be listed under the Unbilled view');
        FindLine(Buffer, LineType::"Time Entry", CustB, JobM, 'T1', JiraId('M1'));
        AssertAllHours(Buffer, 2, 2, 0, 0, 0, 0, 2, 'Listed worklog M1');
        // [THEN] Customer B adds project M's full 3 h to its own 3 h
        FindLine(Buffer, LineType::Customer, CustB, '', '', '');
        AssertAllHours(Buffer, 6, 2, 0, 1, 1, 2, 3, 'Customer B under Unbilled view');
    end;

    [Test]
    procedure BuildOverviewBillableViewKeepsProjectWhoseHoursAreInReview()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        ViewFilter: Record "BCJ Project Time Entry";
        TimeEntry: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
        JobR: Code[20];
    begin
        // [SCENARIO] A project waiting for the customer's answer has no Billable hours yet, but it is
        // exactly the project the reviewer must not lose sight of. Under Show = Billable it stays in
        // the tree with its hours in Sent for Review (which still count as Unbilled), and lists no
        // worklog because none of them is billable yet.
        // [GIVEN] The standard scenario plus project R (customer B) whose 3 h worklog is in a sent review
        CreateScenario();
        BCJTestLibrary.EnsureSetup('https://review.example.com');
        JobR := Stem + 'P6';
        BCJTestLibrary.CreateJob(JobR, CustB, 'Project R ' + Stem);
        BCJTestLibrary.CreateJobTask(JobR, 'T1', 'Task R-T1 ' + Stem, 'DONE');
        BCJTestLibrary.CreateOpenTimeEntry(TimeEntry, JiraId('R1'), JobR, 'T1', Stem, BCJTestLibrary.BaseDate(), 3);
        TimeEntry.SetRange("Jira ID", JiraId('R1'));
        BCJTestLibrary.CreateDraftReview(TimeEntry, Review);
        BCJTestLibrary.SendDraftReview(Review);
        BCJTestLibrary.AssertBuckets(JiraId('R1'), 0, 3, 0, 0, 0, 'Fixture: the sent review must hold all 3 h of R1 in review');
        FilterOwnProjects(TimeEntryFilter);
        ViewFilter.SetFilter("Billable Hours", '<>0');
        // [WHEN] BuildOverview with the Billable view, including time entries
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, ViewFilter, true);
        // [THEN] Project R stays with its in-review hours and lists no worklog
        FindLine(Buffer, LineType::Project, CustB, JobR, '', '');
        AssertAllHours(Buffer, 3, 0, 3, 0, 0, 0, 3, 'Project R (in review) under Billable view');
        Assert.AreEqual(0, CountEntryLines(Buffer, JobR), 'A project with no Billable hours must list no worklog lines under the Billable view');
        // [THEN] The Billable view lists exactly the two Billable worklogs E2 and E6
        Buffer.Reset();
        Buffer.SetRange("Line Type", LineType::"Time Entry");
        Assert.AreEqual(2, Buffer.Count(), 'The Billable view must list exactly the worklogs with Billable hours');
        FindLine(Buffer, LineType::"Time Entry", CustA, JobA1, 'T1', JiraId('E2'));
        FindLine(Buffer, LineType::"Time Entry", CustB, JobB, 'T1', JiraId('E6'));
    end;

    [Test]
    procedure BuildOverviewViewWithoutTimeEntriesStillBuildsFullTree()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        ViewFilter: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] With worklog lines collapsed the view has nothing to narrow, so the tree must be
        // identical to the unfiltered one: all 3 customers, 4 projects and 5 tasks - including those
        // with no Billable hours at all (blank customer, project A2, task A1/T2) - with full totals.
        // [GIVEN] The standard scenario
        CreateScenario();
        FilterOwnProjects(TimeEntryFilter);
        ViewFilter.SetFilter("Billable Hours", '<>0');
        // [WHEN] BuildOverview with the Billable view, without time entries
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, ViewFilter, false);
        // [THEN] 12 lines in customer/project/task order, no time entry lines
        Assert.AreEqual(12, Buffer.Count(), 'A Show view must not remove customers, projects or tasks when time entries are not shown');
        Buffer.Reset();
        Buffer.SetCurrentKey("Entry No.");
        Buffer.FindSet();
        AssertLineAndNext(Buffer, LineType::Customer, '', '', '', '');
        AssertLineAndNext(Buffer, LineType::Project, '', JobN, '', '');
        AssertLineAndNext(Buffer, LineType::Task, '', JobN, 'T1', '');
        AssertLineAndNext(Buffer, LineType::Customer, CustA, '', '', '');
        AssertLineAndNext(Buffer, LineType::Project, CustA, JobA1, '', '');
        AssertLineAndNext(Buffer, LineType::Task, CustA, JobA1, 'T1', '');
        AssertLineAndNext(Buffer, LineType::Task, CustA, JobA1, 'T2', '');
        AssertLineAndNext(Buffer, LineType::Project, CustA, JobA2, '', '');
        AssertLineAndNext(Buffer, LineType::Task, CustA, JobA2, 'T1', '');
        AssertLineAndNext(Buffer, LineType::Customer, CustB, '', '', '');
        AssertLineAndNext(Buffer, LineType::Project, CustB, JobB, '', '');
        AssertLineAndNext(Buffer, LineType::Task, CustB, JobB, 'T1', '');
        Buffer.Reset();
        Buffer.SetRange("Line Type", LineType::"Time Entry");
        Assert.IsTrue(Buffer.IsEmpty(), 'No Time Entry lines may be created when IncludeTimeEntries is false');
        FindLine(Buffer, LineType::Project, CustA, JobA2, '', '');
        AssertAllHours(Buffer, 4, 4, 0, 0, 0, 0, 4, 'Project A2 (no Billable hours) under Billable view');
    end;

    [Test]
    procedure BuildOverviewEmptyViewFilterEqualsThreeParameterOverview()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        ExpectedBuffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        ViewFilter: Record "BCJ Project Time Entry";
        Position: Text;
    begin
        // [SCENARIO] Show = All puts no filter on ViewFilter. That view must be exactly the overview
        // the page has shown so far (3-parameter BuildOverview): same lines, order, keys,
        // descriptions and hours - the new overload may not change anything for the default view.
        // [GIVEN] The standard scenario
        CreateScenario();
        FilterOwnProjects(TimeEntryFilter);
        OverviewMgt.BuildOverview(ExpectedBuffer, TimeEntryFilter, true);
        // [WHEN] BuildOverview with an unfiltered ViewFilter
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, ViewFilter, true);
        // [THEN] Line for line identical
        Assert.AreEqual(ExpectedBuffer.Count(), Buffer.Count(), 'An empty ViewFilter must produce as many lines as the 3-parameter BuildOverview');
        ExpectedBuffer.Reset();
        ExpectedBuffer.SetCurrentKey("Entry No.");
        Buffer.Reset();
        Buffer.SetCurrentKey("Entry No.");
        ExpectedBuffer.FindSet();
        Buffer.FindSet();
        repeat
            Position := StrSubstNo('line %1 of the 3-parameter overview', ExpectedBuffer."Entry No.");
            Assert.AreEqual(ExpectedBuffer."Line Type", Buffer."Line Type", Position + ': Line Type must match');
            Assert.AreEqual(ExpectedBuffer.Indentation, Buffer.Indentation, Position + ': Indentation must match');
            Assert.AreEqual(ExpectedBuffer."Customer No.", Buffer."Customer No.", Position + ': Customer No. must match');
            Assert.AreEqual(ExpectedBuffer."Project No.", Buffer."Project No.", Position + ': Project No. must match');
            Assert.AreEqual(ExpectedBuffer."Project Task No.", Buffer."Project Task No.", Position + ': Project Task No. must match');
            Assert.AreEqual(ExpectedBuffer."Jira ID", Buffer."Jira ID", Position + ': Jira ID must match');
            Assert.AreEqual(ExpectedBuffer."Jira Issue Id", Buffer."Jira Issue Id", Position + ': Jira Issue Id must match');
            Assert.AreEqual(ExpectedBuffer.Description, Buffer.Description, Position + ': Description must match');
            Assert.AreEqual(ExpectedBuffer."Jira Status", Buffer."Jira Status", Position + ': Jira Status must match');
            Assert.AreEqual(ExpectedBuffer."Resource No.", Buffer."Resource No.", Position + ': Resource No. must match');
            Assert.AreEqual(ExpectedBuffer."Posting Date", Buffer."Posting Date", Position + ': Posting Date must match');
            Assert.AreEqual(ExpectedBuffer."Billing Status", Buffer."Billing Status", Position + ': Billing Status must match');
            Assert.AreEqual(ExpectedBuffer."Total Hours", Buffer."Total Hours", Position + ': Total Hours must match');
            Assert.AreEqual(ExpectedBuffer."Open Hours", Buffer."Open Hours", Position + ': Open Hours must match');
            Assert.AreEqual(ExpectedBuffer."Sent for Review Hours", Buffer."Sent for Review Hours", Position + ': Sent for Review Hours must match');
            Assert.AreEqual(ExpectedBuffer."Billable Hours", Buffer."Billable Hours", Position + ': Billable Hours must match');
            Assert.AreEqual(ExpectedBuffer."Not Billable Hours", Buffer."Not Billable Hours", Position + ': Not Billable Hours must match');
            Assert.AreEqual(ExpectedBuffer."Billed Hours", Buffer."Billed Hours", Position + ': Billed Hours must match');
            Assert.AreEqual(ExpectedBuffer."Unbilled Hours", Buffer."Unbilled Hours", Position + ': Unbilled Hours must match');
            Buffer.Next();
        until ExpectedBuffer.Next() = 0;
    end;

    [Test]
    procedure BuildOverviewViewStillPrunesProjectsOutsideDateFilter()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        ViewFilter: Record "BCJ Project Time Entry";
    begin
        // [SCENARIO] "Every project stays" means every project with work in the selected period -
        // the period on TimeEntryFilter still decides which nodes exist. Project A2 has 4 unbilled
        // hours, but none in the period, so it must not appear; project B's period work is only
        // Billed, yet it stays (with Unbilled 0) because it has work in the period.
        // [GIVEN] The standard scenario, period D+1..D+2 (E1 Open, E7 Billed), Unbilled view
        CreateScenario();
        FilterOwnProjects(TimeEntryFilter);
        TimeEntryFilter.SetRange("Posting Date", BCJTestLibrary.BaseDate() + 1, BCJTestLibrary.BaseDate() + 2);
        ViewFilter.SetFilter("Unbilled Hours", '<>0');
        // [WHEN] BuildOverview with the Unbilled view, including time entries
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, ViewFilter, true);
        // [THEN] CustA/A1/T1 with E1, and CustB/B/T1 without entries; nothing else
        Assert.AreEqual(7, Buffer.Count(), 'Only nodes with entries inside the posting date filter may be created, plus the unbilled worklog E1');
        Buffer.Reset();
        Buffer.SetCurrentKey("Entry No.");
        Buffer.FindSet();
        AssertLineAndNext(Buffer, LineType::Customer, CustA, '', '', '');
        AssertLineAndNext(Buffer, LineType::Project, CustA, JobA1, '', '');
        AssertLineAndNext(Buffer, LineType::Task, CustA, JobA1, 'T1', '');
        AssertLineAndNext(Buffer, LineType::"Time Entry", CustA, JobA1, 'T1', JiraId('E1'));
        AssertLineAndNext(Buffer, LineType::Customer, CustB, '', '', '');
        AssertLineAndNext(Buffer, LineType::Project, CustB, JobB, '', '');
        AssertLineAndNext(Buffer, LineType::Task, CustB, JobB, 'T1', '');
        FindLine(Buffer, LineType::Customer, CustA, '', '', '');
        AssertAllHours(Buffer, 2, 2, 0, 0, 0, 0, 2, 'Customer A within date filter under Unbilled view');
        FindLine(Buffer, LineType::Customer, CustB, '', '', '');
        AssertAllHours(Buffer, 2, 0, 0, 0, 0, 2, 0, 'Customer B within date filter under Unbilled view');
    end;

    [Test]
    procedure BuildOverviewWithViewKeepsBothFilterSetsUnchanged()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        ViewFilter: Record "BCJ Project Time Entry";
        TimeEntryFiltersBefore: Text;
        ViewFiltersBefore: Text;
    begin
        // [SCENARIO] The page reuses TimeEntryFilter for the status actions after the build and
        // keeps ViewFilter for the next refresh. If the view leaked into TimeEntryFilter, "Mark
        // Billed" on a customer would silently skip the worklogs the view hides; if the period
        // leaked into ViewFilter, changing the period would keep listing the old one.
        // [GIVEN] The standard scenario, project + period on TimeEntryFilter, Unbilled view on ViewFilter
        CreateScenario();
        FilterOwnProjects(TimeEntryFilter);
        TimeEntryFilter.SetRange("Posting Date", BCJTestLibrary.BaseDate(), BCJTestLibrary.BaseDate() + 2);
        ViewFilter.SetFilter("Unbilled Hours", '<>0');
        TimeEntryFiltersBefore := TimeEntryFilter.GetFilters();
        ViewFiltersBefore := ViewFilter.GetFilters();
        // [WHEN] BuildOverview
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, ViewFilter, true);
        // [THEN] Both filter sets are exactly as before
        Assert.AreEqual(TimeEntryFiltersBefore, TimeEntryFilter.GetFilters(), 'TimeEntryFilter must keep exactly its own filters after BuildOverview');
        Assert.AreEqual(ViewFiltersBefore, ViewFilter.GetFilters(), 'ViewFilter must keep exactly its own filters after BuildOverview');
        Assert.AreEqual('', TimeEntryFilter.GetFilter("Unbilled Hours"), 'The view filter must not leak into TimeEntryFilter');
        Assert.AreEqual('', ViewFilter.GetFilter("Project No."), 'The project filter must not leak into ViewFilter');
        Assert.AreEqual('', ViewFilter.GetFilter("Posting Date"), 'The period filter must not leak into ViewFilter');
        Assert.AreEqual(9, TimeEntryFilter.Count(), 'TimeEntryFilter must still select all 9 worklogs of the period after BuildOverview');
    end;

    // ---------------------------------------------------------------------------------
    // Fixture and helpers
    // ---------------------------------------------------------------------------------

    local procedure CountEntryLines(var Buffer: Record "BCJ Billing Overview Buffer" temporary; ProjectNo: Code[20]): Integer
    begin
        Buffer.Reset();
        Buffer.SetRange("Line Type", LineType::"Time Entry");
        Buffer.SetRange("Project No.", ProjectNo);
        exit(Buffer.Count());
    end;

    local procedure AssertAllHours(Buffer: Record "BCJ Billing Overview Buffer" temporary; Total: Decimal; Open: Decimal; SentForReview: Decimal; Billable: Decimal; NotBillable: Decimal; Billed: Decimal; Unbilled: Decimal; LineName: Text)
    begin
        AssertHours(Buffer, Total, Open, Billable, NotBillable, Billed, Unbilled, LineName);
        Assert.AreEqual(SentForReview, Buffer."Sent for Review Hours", LineName + ': Sent for Review Hours must equal the in-review hours beneath it');
    end;

    local procedure CreateScenario()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        D: Date;
    begin
        Stem := BCJTestLibrary.NewStem();
        CustA := Stem + 'A';
        CustB := Stem + 'B';
        JobA1 := Stem + 'P1';
        JobA2 := Stem + 'P2';
        JobB := Stem + 'P3';
        JobN := Stem + 'P4';
        D := BCJTestLibrary.BaseDate();

        BCJTestLibrary.CreateCustomer(CustA, 'Customer A ' + Stem);
        BCJTestLibrary.CreateCustomer(CustB, 'Customer B ' + Stem);
        BCJTestLibrary.CreateJob(JobA1, CustA, 'Project A1 ' + Stem);
        BCJTestLibrary.CreateJob(JobA2, CustA, 'Project A2 ' + Stem);
        BCJTestLibrary.CreateJob(JobB, CustB, 'Project B ' + Stem);
        BCJTestLibrary.CreateJob(JobN, '', 'Project N ' + Stem);
        BCJTestLibrary.CreateJobTask(JobA1, 'T1', 'Task A1-T1 ' + Stem, 'IN PROGRESS');
        BCJTestLibrary.CreateJobTask(JobA1, 'T2', 'Task A1-T2 ' + Stem, 'DONE');
        BCJTestLibrary.CreateJobTask(JobA2, 'T1', 'Task A2-T1 ' + Stem, 'TO DO');
        BCJTestLibrary.CreateJobTask(JobB, 'T1', 'Task B-T1 ' + Stem, 'DONE');
        BCJTestLibrary.CreateJobTask(JobN, 'T1', 'Task N-T1 ' + Stem, 'IN PROGRESS');

        BCJTestLibrary.CreateTimeEntry(TimeEntry, JiraId('E1'), JobA1, 'T1', Stem, D + 1, 2, "BCJ Billing Status"::Open);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, JiraId('E2'), JobA1, 'T1', Stem, D, 1.5, "BCJ Billing Status"::Billable);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, JiraId('E3'), JobA1, 'T1', Stem, D, 0.5, "BCJ Billing Status"::"Not Billable");
        BCJTestLibrary.CreateTimeEntry(TimeEntry, JiraId('E4'), JobA1, 'T2', Stem, D, 3, "BCJ Billing Status"::Billed);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, JiraId('E5'), JobA2, 'T1', Stem, D, 4, "BCJ Billing Status"::Open);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, JiraId('E6'), JobB, 'T1', Stem, D, 1, "BCJ Billing Status"::Billable);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, JiraId('E7'), JobB, 'T1', Stem, D + 2, 2, "BCJ Billing Status"::Billed);
        BCJTestLibrary.CreateTimeEntry(TimeEntry, JiraId('E8'), JobN, 'T1', Stem, D, 0.25, "BCJ Billing Status"::"Not Billable");
        BCJTestLibrary.CreateTimeEntry(TimeEntry, JiraId('E9'), JobN, 'T1', Stem, D, 0.75, "BCJ Billing Status"::Open);
    end;

    local procedure JiraId(Suffix: Text): Text[50]
    begin
        exit(CopyStr(Stem + '-' + Suffix, 1, 50));
    end;

    local procedure FilterOwnProjects(var TimeEntryFilter: Record "BCJ Project Time Entry")
    begin
        TimeEntryFilter.Reset();
        TimeEntryFilter.SetFilter("Project No.", Stem + '*');
    end;

    local procedure GetStatus(Suffix: Text): Enum "BCJ Billing Status"
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        TimeEntry.Get(JiraId(Suffix), 'I-' + JiraId(Suffix));
        exit(TimeEntry."Billing Status");
    end;

    local procedure MakeLine(NewLineType: Enum "BCJ Overview Line Type"; CustomerNo: Code[20]; ProjectNo: Code[20]; TaskNo: Code[20]; EntryJiraId: Text[50]) OverviewLine: Record "BCJ Billing Overview Buffer"
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        OverviewLine.Init();
        OverviewLine."Entry No." := 1;
        OverviewLine."Line Type" := NewLineType;
        OverviewLine.Indentation := NewLineType.AsInteger();
        OverviewLine."Customer No." := CustomerNo;
        OverviewLine."Project No." := ProjectNo;
        OverviewLine."Project Task No." := TaskNo;
        if EntryJiraId <> '' then begin
            TimeEntry.Get(EntryJiraId, CopyStr('I-' + EntryJiraId, 1, 50));
            OverviewLine."Jira ID" := TimeEntry."Jira ID";
            OverviewLine."Jira Issue Id" := TimeEntry."Jira Issue Id";
            OverviewLine."Resource No." := TimeEntry."BC Resource No.";
            OverviewLine."Posting Date" := TimeEntry."Posting Date";
            OverviewLine."Billing Status" := TimeEntry."Billing Status";
        end;
    end;

    local procedure FindLine(var Buffer: Record "BCJ Billing Overview Buffer" temporary; ExpectedLineType: Enum "BCJ Overview Line Type"; CustomerNo: Code[20]; ProjectNo: Code[20]; TaskNo: Code[20]; EntryJiraId: Text[50])
    begin
        Buffer.Reset();
        Buffer.SetRange("Line Type", ExpectedLineType);
        Buffer.SetRange("Customer No.", CustomerNo);
        if ExpectedLineType <> LineType::Customer then
            Buffer.SetRange("Project No.", ProjectNo);
        if ExpectedLineType in [LineType::Task, LineType::"Time Entry"] then
            Buffer.SetRange("Project Task No.", TaskNo);
        if ExpectedLineType = LineType::"Time Entry" then
            Buffer.SetRange("Jira ID", EntryJiraId);
        Assert.AreEqual(1, Buffer.Count(), StrSubstNo('Exactly one %1 line must exist for %2 %3 %4 %5', ExpectedLineType, CustomerNo, ProjectNo, TaskNo, EntryJiraId));
        Buffer.FindFirst();
    end;

    local procedure AssertLineAndNext(var Buffer: Record "BCJ Billing Overview Buffer" temporary; ExpectedLineType: Enum "BCJ Overview Line Type"; CustomerNo: Code[20]; ProjectNo: Code[20]; TaskNo: Code[20]; EntryJiraId: Text[50])
    var
        Position: Text;
    begin
        Position := StrSubstNo('line with Entry No. %1', Buffer."Entry No.");
        Assert.AreEqual(ExpectedLineType, Buffer."Line Type", 'Tree order: ' + Position + ' must be of the expected line type');
        Assert.AreEqual(ExpectedLineType.AsInteger(), Buffer.Indentation, 'Indentation of ' + Position + ' must match its line type level');
        Assert.AreEqual(CustomerNo, Buffer."Customer No.", 'Tree order: ' + Position + ' must belong to the expected customer');
        if ExpectedLineType <> LineType::Customer then
            Assert.AreEqual(ProjectNo, Buffer."Project No.", 'Tree order: ' + Position + ' must belong to the expected project');
        if ExpectedLineType in [LineType::Task, LineType::"Time Entry"] then
            Assert.AreEqual(TaskNo, Buffer."Project Task No.", 'Tree order: ' + Position + ' must belong to the expected task');
        if ExpectedLineType = LineType::"Time Entry" then
            Assert.AreEqual(EntryJiraId, Buffer."Jira ID", 'Tree order: ' + Position + ' must be the expected time entry');
        Buffer.Next();
    end;

    local procedure AssertHours(Buffer: Record "BCJ Billing Overview Buffer" temporary; Total: Decimal; Open: Decimal; Billable: Decimal; NotBillable: Decimal; Billed: Decimal; Unbilled: Decimal; LineName: Text)
    begin
        Assert.AreEqual(Total, Buffer."Total Hours", LineName + ': Total Hours must equal the sum of hours beneath it');
        Assert.AreEqual(Open, Buffer."Open Hours", LineName + ': Open Hours must equal the sum of Open entries beneath it');
        Assert.AreEqual(Billable, Buffer."Billable Hours", LineName + ': Billable Hours must equal the sum of Billable entries beneath it');
        Assert.AreEqual(NotBillable, Buffer."Not Billable Hours", LineName + ': Not Billable Hours must equal the sum of Not Billable entries beneath it');
        Assert.AreEqual(Billed, Buffer."Billed Hours", LineName + ': Billed Hours must equal the sum of Billed entries beneath it');
        Assert.AreEqual(Unbilled, Buffer."Unbilled Hours", LineName + ': Unbilled Hours must equal Open + Billable');
    end;
}
