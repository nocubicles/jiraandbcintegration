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
        // [GIVEN] The standard scenario, filtered to posting date D
        CreateScenario();
        FilterOwnProjects(TimeEntryFilter);
        TimeEntryFilter.SetRange("Posting Date", BCJTestLibrary.BaseDate());
        // [WHEN] Task A1/T1 is set to Billed
        Changed := OverviewMgt.SetStatusForLine(MakeLine(LineType::Task, CustA, JobA1, 'T1', ''), TimeEntryFilter, "BCJ Billing Status"::Billed);
        // [THEN] E2 and E3 (date D) are Billed; E1 (D+1) is untouched
        Assert.AreEqual(2, Changed, 'Only entries of the task inside the posting date filter may be changed');
        Assert.AreEqual("BCJ Billing Status"::Billed, GetStatus('E2'), 'Entry of the task inside the date filter must be Billed');
        Assert.AreEqual("BCJ Billing Status"::Billed, GetStatus('E3'), 'Entry of the task inside the date filter must be Billed');
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
        // unassigned projects' worklogs.
        // [GIVEN] The standard scenario
        CreateScenario();
        FilterOwnProjects(TimeEntryFilter);
        // [WHEN] Customer A is set to Not Billable
        Changed := OverviewMgt.SetStatusForLine(MakeLine(LineType::Customer, CustA, '', '', ''), TimeEntryFilter, "BCJ Billing Status"::"Not Billable");
        // [THEN] E1, E2, E4, E5 changed (E3 already Not Billable); other customers untouched
        Assert.AreEqual(4, Changed, 'All of customer A''s entries not yet Not Billable must be changed');
        Assert.AreEqual("BCJ Billing Status"::"Not Billable", GetStatus('E4'), 'Customer A''s Billed entry must become Not Billable');
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
        // [THEN] E8 and E9 changed; customer A's Open entry untouched
        Assert.AreEqual(2, Changed, 'Both entries of the project without Bill-to customer must be changed');
        Assert.AreEqual("BCJ Billing Status"::Billable, GetStatus('E8'), 'Unassigned project entry must become Billable');
        Assert.AreEqual("BCJ Billing Status"::Billable, GetStatus('E9'), 'Unassigned project entry must become Billable');
        Assert.AreEqual("BCJ Billing Status"::Open, GetStatus('E1'), 'Customer A''s entry must stay untouched');
    end;

    // ---------------------------------------------------------------------------------
    // Fixture and helpers
    // ---------------------------------------------------------------------------------

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
