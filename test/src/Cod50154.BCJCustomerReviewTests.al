codeunit 50154 "BCJ Customer Review Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    // Customer time review: the consultant reserves a project's Open hours in a Draft review,
    // lowers Hours to Bill per task, sends it, the customer approves a number of hours per task,
    // and the approved hours are allocated back onto the individual worklogs. Money changes
    // hands on the result, so every number asserted here is a business decision recorded in
    // tasks/hour-allocation-contract.md (v1.2.0.0), not an implementation detail.
    //
    // Hour buckets per worklog: Open / In Review / Billable / Billed / Not Billable, always
    // adding up to the logged hours. Allocation inside a task is always oldest first (Posting
    // Date, then Jira ID): older hours are kept in review / approved first, the newest go back
    // to Open.
    //
    // All fixture keys derive from a fresh GUID stem, so these tests never touch real synced
    // Jira data in the sandbox and never collide with each other. Nothing is cached between
    // tests: Initialize() rebuilds the stem and the setup singleton on every run, because the
    // test runner rolls the database back but not codeunit variables.

    var
        BCJTestLibrary: Codeunit "BCJ Test Library";
        Assert: Codeunit "Library Assert";
        CustomerReviewMgt: Codeunit "BCJ Customer Review Mgt.";
        ReviewMail: Codeunit "BCJ Review Mail";
        BillingMgt: Codeunit "BCJ Billing Mgt.";
        OverviewMgt: Codeunit "BCJ Billing Overview Mgt.";
        LineType: Enum "BCJ Overview Line Type";
        Stem: Code[13];

    // ---------------------------------------------------------------------------------
    // CreateReviews - Draft reviews reserve Open hours
    // ---------------------------------------------------------------------------------

    [Test]
    procedure CreateReviews_OnePerProjectWithLinesPerTask()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        CustomerNo: Code[20];
        JobNo: Code[20];
        Created: Integer;
    begin
        // [SCENARIO] The customer is asked to approve a project, not a worklog: one review per
        // project, one line per task. Creating it makes a Draft (business flow step 2) that the
        // consultant can still adjust before anything reaches the customer, and it reserves the
        // Open hours (In Review) so the same hours cannot go into a second review meanwhile.
        // [GIVEN] One project with two tasks and three open entries
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobNo := CreateProject('P1', CustomerNo);
        CreateTask(JobNo, 'T1');
        CreateTask(JobNo, 'T2');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('E2', JobNo, 'T1', D() + 1, 1, "BCJ Billing Status"::Open);
        AddEntry('E3', JobNo, 'T2', D(), 3, "BCJ Billing Status"::Open);
        // [WHEN] The whole project is put in a review
        FilterOwnProjects(TimeEntry);
        Created := CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        // [THEN] Exactly one Draft review, one line per task, hours summed per task
        Assert.AreEqual(1, Created, 'Open entries of one project must produce exactly one review, not one per task or per entry');
        Assert.AreEqual(1, TempReview.Count(), 'The returned temporary buffer must hold one header per review created');
        TempReview.FindFirst();
        Review.Get(TempReview."Review No.");
        Assert.AreEqual("BCJ Review Status"::Draft, Review.Status, 'A newly created review must be a Draft - nothing reaches the customer until it is sent');
        Assert.AreEqual(JobNo, Review."Project No.", 'The review must belong to the project its entries came from');
        Assert.AreEqual(CustomerNo, Review."Customer No.", 'The review must snapshot the project Bill-to customer, so a later change of Bill-to does not rewrite history');
        ReviewLine.SetRange("Review No.", Review."Review No.");
        Assert.AreEqual(2, ReviewLine.Count(), 'A review must have exactly one line per task that had hours reserved');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(3.0, ReviewLine."Logged Hours", 'Task T1 must show the hours reserved from both of its entries');
        Assert.AreEqual(3.0, ReviewLine."Hours to Bill", 'Hours to Bill must start at the hours reserved on the task');
        Assert.AreEqual(TaskDescription(JobNo, 'T1'), ReviewLine."Task Description", 'The line must carry the task description the customer recognises');
        ReviewLine.Get(Review."Review No.", 'T2');
        Assert.AreEqual(3.0, ReviewLine."Logged Hours", 'Task T2 must show the hours of the single entry reserved for it');
        // [THEN] Every hour is reserved in this review
        AssertBuckets('E1', 0, 2, 0, 0, 0, 'Entry E1 must have all its Open hours reserved');
        AssertBuckets('E2', 0, 1, 0, 0, 0, 'Entry E2 must have all its Open hours reserved');
        AssertBuckets('E3', 0, 3, 0, 0, 0, 'Entry E3 must have all its Open hours reserved');
        BCJTestLibrary.AssertRow(JiraId('E1'), Review."Review No.", 2, 0, 0, 0, 'The reserved hours of E1 must sit on the row of this review');
        AssertStatus('E1', "BCJ Billing Status"::"Sent for Review", 'An entry with hours in review must show Sent for Review');
        AssertOwnInvariant('After CreateReviews');
    end;

    [Test]
    procedure CreateReviews_SelectionSpanningTwoProjectsCreatesTwoReviews()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        ReviewA: Record "BCJ Customer Review";
        ReviewB: Record "BCJ Customer Review";
        CustomerNo: Code[20];
        JobA: Code[20];
        JobB: Code[20];
        Created: Integer;
    begin
        // [SCENARIO] A consultant selects a whole customer in the overview. Each project is a
        // separate agreement with its own budget, so it gets its own review - one combined review
        // would make the customer approve hours across projects that may be invoiced separately.
        // [GIVEN] Two projects of one customer, each with open entries
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobA := CreateProject('P1', CustomerNo);
        JobB := CreateProject('P2', CustomerNo);
        CreateTask(JobA, 'T1');
        CreateTask(JobB, 'T1');
        AddEntry('A1', JobA, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('A2', JobA, 'T1', D(), 1, "BCJ Billing Status"::Open);
        AddEntry('B1', JobB, 'T1', D(), 4, "BCJ Billing Status"::Open);
        // [WHEN] Both projects are put in review in one call
        FilterOwnProjects(TimeEntry);
        Created := CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        // [THEN] Two reviews, one per project, each holding only its own hours
        Assert.AreEqual(2, Created, 'A selection spanning two projects must produce one review per project');
        Assert.AreEqual(2, TempReview.Count(), 'The returned temporary buffer must hold both review headers');
        GetReviewOfProject(JobA, ReviewA);
        GetReviewOfProject(JobB, ReviewB);
        Assert.AreNotEqual(ReviewA."Review No.", ReviewB."Review No.", 'The two projects must get two distinct reviews');
        BCJTestLibrary.AssertRow(JiraId('A1'), ReviewA."Review No.", 2, 0, 0, 0, 'Entry A1 must be reserved in the review of its own project');
        BCJTestLibrary.AssertRow(JiraId('A2'), ReviewA."Review No.", 1, 0, 0, 0, 'Entry A2 must be reserved in the review of its own project');
        BCJTestLibrary.AssertRow(JiraId('B1'), ReviewB."Review No.", 4, 0, 0, 0, 'Entry B1 must be reserved in the review of its own project');
    end;

    [Test]
    procedure CreateReviews_TakesOnlyOpenHours()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
        Created: Integer;
    begin
        // [SCENARIO] Only Open hours are the customer's business. Hours already approved,
        // written off or above all invoiced must never be put in front of the customer again -
        // the customer would be asked to approve an invoice that has already been sent. Entries
        // without Open hours inside the selection are skipped rather than rejected, because
        // selecting a whole task or project is the normal way to work.
        // [GIVEN] One task holding one Open entry and one entry in each decided state
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('OPEN', JobNo, 'T1', D(), 1, "BCJ Billing Status"::Open);
        AddEntry('BILLABLE', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Billable);
        AddEntry('BILLED', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Billed);
        AddEntry('NOTBILL', JobNo, 'T1', D(), 4, "BCJ Billing Status"::"Not Billable");
        // [WHEN] The whole task is put in review
        FilterOwnProjects(TimeEntry);
        Created := CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        // [THEN] Only the Open hour is on the review; the decided entries are untouched
        Assert.AreEqual(1, Created, 'A selection with at least one Open hour must create the review for that project');
        TempReview.FindFirst();
        Review.Get(TempReview."Review No.");
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(1.0, ReviewLine."Logged Hours", 'Only Open hours may be put in front of the customer');
        AssertBuckets('OPEN', 0, 1, 0, 0, 0, 'The Open entry must be the one reserved in the review');
        AssertBuckets('BILLABLE', 0, 0, 2, 0, 0, 'An already Billable entry must stay decided and outside the review');
        AssertBuckets('BILLED', 0, 0, 0, 0, 3, 'An already invoiced entry must never be sent for approval again');
        AssertBuckets('NOTBILL', 0, 0, 0, 4, 0, 'A written-off entry must stay decided and outside the review');
    end;

    [Test]
    procedure CreateReviews_WithoutOpenEntriesErrorsAndCreatesNothing()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] A selection that holds nothing to approve must tell the consultant so, not
        // silently create an empty review that the customer then receives a mail about.
        // [GIVEN] A project whose entries are all already decided
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('B1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Billable);
        AddEntry('B2', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Billed);
        // [WHEN] It is put in review
        FilterOwnProjects(TimeEntry);
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        // [THEN] A plain error, no review, and the entries untouched
        Assert.ExpectedErrorCode('Dialog');
        Review.SetRange("Project No.", JobNo);
        Assert.IsTrue(Review.IsEmpty(), 'A selection with nothing to approve must leave no review behind');
        AssertBuckets('B1', 0, 0, 2, 0, 0, 'A failed create must leave the Billable entry exactly as it was');
        AssertBuckets('B2', 0, 0, 0, 0, 3, 'A failed create must leave the Billed entry exactly as it was');
    end;

    [Test]
    procedure CreateReviews_BlankReviewBaseUrlErrorsBeforeAnyWrite()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] Without a review base URL the review could never be answered, while its hours
        // would already be reserved - invisible to invoicing. The setup is therefore checked
        // before anything is written (contract: "Setup check before any write").
        // [GIVEN] Open entries and no review base URL configured
        Initialize();
        BCJTestLibrary.EnsureSetup('');
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        // [WHEN] The project is put in review
        FilterOwnProjects(TimeEntry);
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        // [THEN] A field check fails and nothing at all was created or moved
        Assert.ExpectedErrorCode('TestField');
        Review.SetRange("Project No.", JobNo);
        Assert.IsTrue(Review.IsEmpty(), 'A missing review base URL must leave no review behind');
        AssertBuckets('E1', 2, 0, 0, 0, 0, 'The entry must still be fully Open after the setup check failed');
    end;

    [Test]
    procedure CreateReviews_AccessTokenIsUniquePerReview()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        ReviewA: Record "BCJ Customer Review";
        ReviewB: Record "BCJ Customer Review";
        FoundReview: Record "BCJ Customer Review";
        JobA: Code[20];
        JobB: Code[20];
    begin
        // [SCENARIO] The access token is the only thing standing between a review link and a
        // customer's hours: whoever holds it can read and answer that review without signing in.
        // It must therefore be long, unguessable and different for every review - if two reviews
        // created in the same run shared a token, one customer would answer another's review.
        // [GIVEN] Two projects with open entries
        Initialize();
        JobA := CreateProject('P1', CreateCustomer('C'));
        JobB := CreateProject('P2', CreateCustomer('D'));
        CreateTask(JobA, 'T1');
        CreateTask(JobB, 'T1');
        AddEntry('A1', JobA, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('B1', JobB, 'T1', D(), 3, "BCJ Billing Status"::Open);
        // [WHEN] Both are put in review in one call
        FilterOwnProjects(TimeEntry);
        CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        GetReviewOfProject(JobA, ReviewA);
        GetReviewOfProject(JobB, ReviewB);
        // [THEN] Each token is 32 hex characters and the two differ
        Assert.AreEqual(32, StrLen(ReviewA."Access Token"), 'An access token must be exactly 32 characters, the full entropy of a GUID');
        Assert.AreEqual(32, StrLen(ReviewB."Access Token"), 'An access token must be exactly 32 characters, the full entropy of a GUID');
        Assert.AreEqual('', DelChr(ReviewA."Access Token", '=', '0123456789ABCDEF'), 'An access token must contain uppercase hex characters only, so it survives any URL unescaped');
        Assert.AreNotEqual(ReviewA."Access Token", ReviewB."Access Token", 'Two reviews created in one call must never share an access token');
        // [THEN] The token is what the web app looks a review up by, and nothing else is
        Assert.IsTrue(CustomerReviewMgt.FindByToken(ReviewA."Access Token", FoundReview), 'A valid token must find its review');
        Assert.AreEqual(ReviewA."Review No.", FoundReview."Review No.", 'A token must find the review it belongs to and no other');
        Assert.IsFalse(CustomerReviewMgt.FindByToken('', FoundReview), 'A blank token must never find a review');
        Assert.IsFalse(CustomerReviewMgt.FindByToken('NOSUCHTOKENNOSUCHTOKENNOSUCHTOK', FoundReview), 'An unknown token must never find a review');
    end;

    [Test]
    procedure CreateReviews_FromMarkedCustomerAndTaskLinesCountsEachEntryOnce()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        SelectedLine: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        ReviewA: Record "BCJ Customer Review";
        ReviewB: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        CustomerNo: Code[20];
        JobA: Code[20];
        JobB: Code[20];
        MarkedCount: Integer;
        Created: Integer;
    begin
        // [SCENARIO] In the overview the consultant can select a customer row and, in the same
        // selection, a task row already contained in it. The overlap must collapse: an entry
        // reached twice is still one entry, reserved once, on one review line. Double counting
        // would show the customer the same hours twice and double what they approve.
        // [GIVEN] A customer with two projects and four open entries
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobA := CreateProject('P1', CustomerNo);
        JobB := CreateProject('P2', CustomerNo);
        CreateTask(JobA, 'T1');
        CreateTask(JobA, 'T2');
        CreateTask(JobB, 'T1');
        AddEntry('A1', JobA, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('A2', JobA, 'T1', D(), 1, "BCJ Billing Status"::Open);
        AddEntry('A3', JobA, 'T2', D(), 3, "BCJ Billing Status"::Open);
        AddEntry('B1', JobB, 'T1', D(), 4, "BCJ Billing Status"::Open);
        FilterOwnProjects(TimeEntryFilter);
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, true);
        // [WHEN] The customer row and one of its own task rows are both selected and marked
        FindLine(Buffer, LineType::Customer, CustomerNo, '', '');
        SelectedLine := Buffer;
        SelectedLine.Insert();
        FindLine(Buffer, LineType::Task, CustomerNo, JobA, 'T1');
        SelectedLine := Buffer;
        SelectedLine.Insert();
        MarkedCount := OverviewMgt.MarkEntriesForLines(SelectedLine, TimeEntryFilter, TimeEntry);
        Created := CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        // [THEN] Four distinct entries, two reviews, and T1 holds its two entries once
        Assert.AreEqual(4, MarkedCount, 'An entry reached through both a customer row and a task row must be marked once, not twice');
        Assert.AreEqual(2, Created, 'The marked entries must produce exactly one review per project');
        GetReviewOfProject(JobA, ReviewA);
        GetReviewOfProject(JobB, ReviewB);
        ReviewLine.Get(ReviewA."Review No.", 'T1');
        Assert.AreEqual(3.0, ReviewLine."Logged Hours", 'The overlapping task must show its hours once, not doubled');
        ReviewLine.Get(ReviewA."Review No.", 'T2');
        Assert.AreEqual(3.0, ReviewLine."Logged Hours", 'The task reached only through the customer row must be reserved too');
        ReviewLine.Get(ReviewB."Review No.", 'T1');
        Assert.AreEqual(4.0, ReviewLine."Logged Hours", 'The second project of the selected customer must be reserved too');
        AssertBuckets('A1', 0, 2, 0, 0, 0, 'Entry A1 must be reserved exactly once');
        BCJTestLibrary.AssertRow(JiraId('B1'), ReviewB."Review No.", 4, 0, 0, 0, 'Entry B1 must be reserved exactly once, on the review of its own project');
    end;

    [Test]
    procedure CreateReviews_HonoursPostingDateFilter()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] Reviews are prepared per billing period. An open entry outside the period
        // the consultant filtered on belongs to the next invoice and must stay Open - otherwise
        // the customer approves hours that were never meant to be in the period.
        // [GIVEN] Two open entries on the same task, five days apart
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('IN', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('OUT', JobNo, 'T1', D() + 5, 3, "BCJ Billing Status"::Open);
        // [WHEN] Only the first period is put in review
        FilterOwnProjects(TimeEntry);
        TimeEntry.SetRange("Posting Date", D(), D() + 1);
        CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        // [THEN] The review holds the filtered entry only; the later entry is still Open
        TempReview.FindFirst();
        Review.Get(TempReview."Review No.");
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(2.0, ReviewLine."Logged Hours", 'Only hours inside the posting date filter may be reserved');
        AssertBuckets('IN', 0, 2, 0, 0, 0, 'The entry inside the filter must be reserved in the review');
        AssertBuckets('OUT', 3, 0, 0, 0, 0, 'An open entry outside the posting date filter must stay Open');
    end;

    [Test]
    procedure CreateReviews_SecondCallExtendsExistingDraftWithOnlyNewOpenHours()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] Contract, CreateReviews: "one Draft review per project (hours are added to
        // an existing Draft of that project instead of creating a second one)". The consultant
        // who adds a late worklog to a review still being prepared gets one review, and the
        // hours already reserved in it are not reserved a second time - the same hours cannot go
        // into two drafts, nor twice into one.
        // [GIVEN] A draft review holding E1 (2 h on T1)
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        CreateTask(JobNo, 'T2');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        // [GIVEN] Then E2 (3 h on T1) and E3 (1 h on T2) are synced
        AddEntry('E2', JobNo, 'T1', D() + 1, 3, "BCJ Billing Status"::Open);
        AddEntry('E3', JobNo, 'T2', D() + 1, 1, "BCJ Billing Status"::Open);
        // [WHEN] The whole project is put in review again
        FilterOwnProjects(TimeEntry);
        Assert.AreEqual(1, CustomerReviewMgt.CreateReviews(TimeEntry, TempReview), 'Extending an existing draft must count as one review created or extended');
        // [THEN] Still one review for the project, the same one, now with the new hours added
        GetReviewOfProject(JobNo, Review);
        TempReview.FindFirst();
        Assert.AreEqual(Review."Review No.", TempReview."Review No.", 'The extended draft must be the one returned');
        Assert.AreEqual("BCJ Review Status"::Draft, Review.Status, 'An extended review must still be a Draft');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(5.0, ReviewLine."Logged Hours", 'Task T1 must hold the 2 hours already reserved plus the 3 new ones, not 2 twice');
        Assert.AreEqual(5.0, ReviewLine."Hours to Bill", 'Task T1 must ask for all the hours now reserved on it');
        ReviewLine.Get(Review."Review No.", 'T2');
        Assert.AreEqual(1.0, ReviewLine."Logged Hours", 'A task new to the draft must get its own line in the same review');
        BCJTestLibrary.AssertRow(JiraId('E1'), Review."Review No.", 2, 0, 0, 0, 'E1 must still be reserved once, for its 2 hours');
        BCJTestLibrary.AssertRow(JiraId('E2'), Review."Review No.", 3, 0, 0, 0, 'E2 must be reserved in the same draft');
        AssertBuckets('E1', 0, 2, 0, 0, 0, 'E1 must not be reserved a second time');
        AssertOwnInvariant('After extending a draft');
    end;

    [Test]
    procedure CreateReviews_SecondCallWithNothingNewOpenErrors()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] Hours already reserved in a draft are not Open, so selecting them again
        // selects nothing to approve - the consultant must be told, and the existing draft must
        // stay exactly as it was (no doubled line).
        // [GIVEN] A draft review holding all Open hours of the project
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        // [WHEN] The same project is put in review again
        FilterOwnProjects(TimeEntry);
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        // [THEN] A plain error, and the draft is unchanged
        Assert.ExpectedErrorCode('Dialog');
        GetReviewOfProject(JobNo, Review);
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(2.0, ReviewLine."Logged Hours", 'A refused second call must leave the draft line as it was');
        AssertBuckets('E1', 0, 2, 0, 0, 0, 'A refused second call must leave the reserved hours as they were');
    end;

    [Test]
    procedure CreateReviews_AfterSendNewHoursGoToANewDraft()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        SentReview: Record "BCJ Customer Review";
        NewReview: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] A sent review is frozen (business flow step 4): the customer has been shown
        // its figures. Hours synced afterwards cannot be slipped into it; they start a new Draft,
        // and the hours of the sent review stay where they are.
        // [GIVEN] A sent review holding E1
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        CreateOneReview(SentReview);
        BCJTestLibrary.SendDraftReview(SentReview);
        // [GIVEN] Then E2 is synced
        AddEntry('E2', JobNo, 'T1', D() + 1, 3, "BCJ Billing Status"::Open);
        // [WHEN] The project is put in review again
        FilterOwnProjects(TimeEntry);
        Assert.AreEqual(1, CustomerReviewMgt.CreateReviews(TimeEntry, TempReview), 'The new hours must produce exactly one review');
        // [THEN] A new Draft holds only E2; the sent review is untouched
        TempReview.FindFirst();
        NewReview.Get(TempReview."Review No.");
        Assert.AreNotEqual(SentReview."Review No.", NewReview."Review No.", 'Hours must never be added to a review that was already sent');
        Assert.AreEqual("BCJ Review Status"::Draft, NewReview.Status, 'The new review must be a Draft');
        ReviewLine.Get(NewReview."Review No.", 'T1');
        Assert.AreEqual(3.0, ReviewLine."Logged Hours", 'The new draft must hold only the hours that were Open');
        BCJTestLibrary.AssertRow(JiraId('E1'), SentReview."Review No.", 2, 0, 0, 0, 'E1 must stay in the sent review');
        BCJTestLibrary.AssertRow(JiraId('E2'), NewReview."Review No.", 3, 0, 0, 0, 'E2 must be reserved in the new draft');
        SentReview.Get(SentReview."Review No.");
        Assert.AreEqual("BCJ Review Status"::Sent, SentReview.Status, 'The sent review must stay Sent');
    end;

    // ---------------------------------------------------------------------------------
    // SendReview - the cut hours go back to Open, the review is frozen
    // ---------------------------------------------------------------------------------

    [Test]
    procedure SendReview_ReleasesCutHoursOldestFirstInsideOneWorklog()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
        MailSent: Boolean;
    begin
        // [SCENARIO] Business flow step 4: on Send, the hours cut from the review (in review -
        // Hours to Bill) return to Open immediately, so they can be written off or kept for a
        // next review. Older hours are kept in review first, so the cut comes off the newest
        // worklog and, when the kept amount ends inside a worklog, that worklog is split: the
        // 6 h worklog keeps 5 in review and releases 1, the newer 4 h worklog is fully released.
        // [GIVEN] A draft over 6 h (older) and 4 h (newer) on one task, Hours to Bill 5
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('OLD', JobNo, 'T1', D(), 6, "BCJ Billing Status"::Open);
        AddEntry('NEW', JobNo, 'T1', D() + 1, 4, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        BCJTestLibrary.SetHoursToBill(Review."Review No.", 'T1', 5);
        // [WHEN] The review is sent (the customer has no e-mail address)
        Review.Get(Review."Review No.");
        MailSent := CustomerReviewMgt.SendReview(Review);
        // [THEN] Exactly the 5 hours to bill stay in review, oldest first; the rest is Open
        AssertBuckets('OLD', 1, 5, 0, 0, 0, 'The older worklog must keep 5 hours in review and release its last hour');
        AssertBuckets('NEW', 4, 0, 0, 0, 0, 'The newer worklog must be released completely');
        AssertStatus('OLD', "BCJ Billing Status"::"Sent for Review", 'A worklog with hours still in review must show Sent for Review');
        AssertStatus('NEW', "BCJ Billing Status"::Open, 'A fully released worklog must show Open');
        // [THEN] The review is Sent and stamped; without a recipient no mail went out
        Assert.IsFalse(MailSent, 'Without any recipient address SendReview must report that no e-mail was sent');
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Sent, Review.Status, 'A sent review must be Sent even when no e-mail could go out - the link can be shared by hand');
        Assert.AreNotEqual(0DT, Review."Sent On", 'A sent review must record when it was sent');
        AssertOwnInvariant('After SendReview');
    end;

    [Test]
    procedure SendReview_SamePostingDateKeepsLowerJiraIdInReview()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] Worklogs on the same day are the common case. Jira ID breaks the tie, so the
        // same Send always keeps the same worklog in review - otherwise the overview and the later
        // approval would disagree about which worklog the customer was asked about.
        // [GIVEN] Two 3 h worklogs on the same day, Hours to Bill 4
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('A', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        AddEntry('B', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        BCJTestLibrary.SetHoursToBill(Review."Review No.", 'T1', 4);
        // [WHEN] The review is sent
        BCJTestLibrary.SendDraftReview(Review);
        // [THEN] A is kept in full, B keeps 1 and releases 2
        AssertBuckets('A', 0, 3, 0, 0, 0, 'On equal posting dates the lower Jira ID must be kept in review first');
        AssertBuckets('B', 2, 1, 0, 0, 0, 'On equal posting dates the higher Jira ID must carry the cut');
    end;

    [Test]
    procedure SendReview_RoundingDustIsNotReleased()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
        Logged: Decimal;
    begin
        // [SCENARIO] Jira logs seconds: 8 minutes are 0.133333 h, which the review shows as 0.13
        // and asks the customer for 0.13. Sending that unchanged request must release nothing -
        // releasing the invisible 0.003333 h would leave a worklog half in review and half Open
        // for a figure nobody can see (contract: "If KeepHours >= Round(total in review, 0.01)
        // everything is kept").
        // [GIVEN] A draft over one 8-minute worklog, Hours to Bill left at its default
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        Logged := 480 / 3600;
        AddEntry('E1', JobNo, 'T1', D(), Logged, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(0.13, ReviewLine."Hours to Bill", 'Fixture: the 8-minute worklog must be asked for as 0.13 h');
        // [WHEN] The review is sent
        BCJTestLibrary.SendDraftReview(Review);
        // [THEN] The whole worklog is still in review and nothing is Open
        AssertBuckets('E1', 0, Logged, 0, 0, 0, 'Sending an unchanged rounded request must keep the whole worklog in review');
    end;

    [Test]
    procedure SendReview_DropsLinesWithZeroHoursToBill()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] A task the consultant decided not to charge at all (Hours to Bill 0) is not
        // a question for the customer: the line is removed on Send so the customer is not asked
        // to approve zero hours, and all its hours return to Open for the consultant to write
        // off or keep.
        // [GIVEN] A draft over T1 (3 h, Hours to Bill 0) and T2 (2 h, asked in full)
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        CreateTask(JobNo, 'T2');
        AddEntry('E1', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        AddEntry('E2', JobNo, 'T2', D(), 2, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        BCJTestLibrary.SetHoursToBill(Review."Review No.", 'T1', 0);
        // [WHEN] The review is sent
        BCJTestLibrary.SendDraftReview(Review);
        // [THEN] The T1 line is gone and its hours are Open; T2 is in review
        Assert.IsFalse(ReviewLine.Get(Review."Review No.", 'T1'), 'A line with Hours to Bill 0 must be deleted on Send');
        Assert.IsTrue(ReviewLine.Get(Review."Review No.", 'T2'), 'A line with hours to bill must stay on the sent review');
        AssertBuckets('E1', 3, 0, 0, 0, 0, 'The hours of a dropped line must all return to Open');
        AssertBuckets('E2', 0, 2, 0, 0, 0, 'The hours of a kept line must stay in review');
    end;

    [Test]
    procedure SendReview_ClampsHoursToBillToHoursStillInReview()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] Jira can shrink a worklog while its review is still a draft; the trim then
        // takes the hours out of the draft. The line may never ask the customer for hours that
        // are no longer in review, so Send clamps Hours to Bill to what is actually there.
        // [GIVEN] A draft over a 4 h worklog, which Jira then shrinks to 3 h
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 4, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        BCJTestLibrary.ChangeLoggedHours(JiraId('E1'), 3);
        // [WHEN] The review is sent
        BCJTestLibrary.SendDraftReview(Review);
        // [THEN] The request is 3 and all 3 hours are in review
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(3.0, ReviewLine."Hours to Bill", 'Hours to Bill must be clamped to the hours still in review');
        AssertBuckets('E1', 0, 3, 0, 0, 0, 'All remaining hours must stay in review');
    end;

    [Test]
    procedure SendReview_OnSentReviewIsRefused()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
        SentOn: DateTime;
    begin
        // [SCENARIO] Send turns a Draft into a Sent review and releases its cut hours. Running it
        // on a review that is already out would release hours a second time from a review the
        // customer is looking at. (Re-mailing a sent review is SendReviews' job.)
        // [GIVEN] A sent review
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 4, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        BCJTestLibrary.SetHoursToBill(Review."Review No.", 'T1', 3);
        BCJTestLibrary.SendDraftReview(Review);
        SentOn := Review."Sent On";
        // [WHEN] It is sent again
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror CustomerReviewMgt.SendReview(Review);
        // [THEN] Refused and nothing changed
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Sent, Review.Status, 'A refused second send must leave the review Sent');
        Assert.AreEqual(SentOn, Review."Sent On", 'A refused second send must not restamp Sent On');
        AssertBuckets('E1', 1, 3, 0, 0, 0, 'A refused second send must not release anything');
    end;

    // ---------------------------------------------------------------------------------
    // Review mail - recipient, link and message (nothing is sent)
    // ---------------------------------------------------------------------------------

    [Test]
    procedure GetRecipientEmail_PrefersBillToContactEmail()
    var
        Review: Record "BCJ Customer Review";
        CustomerNo: Code[20];
        JobNo: Code[20];
        ContactNo: Code[20];
    begin
        // [SCENARIO] The person who approves hours is the project's contact, not the accounts
        // mailbox on the customer card. Where both exist the contact wins, or the approval
        // request lands in accounts payable and never reaches anyone who knows what was worked on.
        // [GIVEN] A project with a bill-to contact that has an e-mail, and a customer that also has one
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobNo := CreateProject('P1', CustomerNo);
        CreateTask(JobNo, 'T1');
        ContactNo := CopyStr(Stem + 'CT', 1, 20);
        BCJTestLibrary.CreateContact(ContactNo, 'contact@example.com');
        BCJTestLibrary.SetJobBillToContact(JobNo, ContactNo);
        BCJTestLibrary.SetCustomerEmail(CustomerNo, 'accounts@example.com');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        // [WHEN] / [THEN] The recipient is the contact
        Assert.AreEqual('contact@example.com', ReviewMail.GetRecipientEmail(Review), 'The review must go to the project bill-to contact when that contact has an e-mail address');
    end;

    [Test]
    procedure GetRecipientEmail_FallsBackToCustomerEmail()
    var
        Review: Record "BCJ Customer Review";
        CustomerNo: Code[20];
        JobNo: Code[20];
        ContactNo: Code[20];
    begin
        // [SCENARIO] Contacts are often incomplete in practice. Rather than silently skipping the
        // mail, the customer card's e-mail is used - a review that reaches the wrong desk at the
        // right company can be forwarded; one that is never sent is simply lost revenue.
        // [GIVEN] A project whose bill-to contact has no e-mail, and a customer that has one
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobNo := CreateProject('P1', CustomerNo);
        CreateTask(JobNo, 'T1');
        ContactNo := CopyStr(Stem + 'CT', 1, 20);
        BCJTestLibrary.CreateContact(ContactNo, '');
        BCJTestLibrary.SetJobBillToContact(JobNo, ContactNo);
        BCJTestLibrary.SetCustomerEmail(CustomerNo, 'accounts@example.com');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        // [WHEN] / [THEN] The customer address is used
        Assert.AreEqual('accounts@example.com', ReviewMail.GetRecipientEmail(Review), 'A bill-to contact without an e-mail must fall back to the customer e-mail, not block the mail');
        // [WHEN] The project has no bill-to contact at all
        BCJTestLibrary.SetJobBillToContact(JobNo, '');
        // [THEN] The customer address is used as well
        Assert.AreEqual('accounts@example.com', ReviewMail.GetRecipientEmail(Review), 'A project without a bill-to contact must fall back to the customer e-mail');
    end;

    [Test]
    procedure SendReviews_WithoutRecipientSendsDraftButSkipsMail()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        Sent: Integer;
    begin
        // [SCENARIO] A project with no contact and no customer e-mail is a data gap, not a reason
        // to keep the review from the customer: the consultant can share the link by hand. So
        // SendReviews sends the Draft (it becomes Sent, stamped Sent On, hours stay in review)
        // but no mail is counted and no e-mail stamp is set - a false "e-mail sent on" timestamp
        // would hide the gap forever.
        // [GIVEN] A draft review of a project whose customer has no e-mail and no bill-to contact
        Initialize();
        CreateSingleTaskProjectWithOpenEntry('E1', 2);
        FilterOwnProjects(TimeEntry);
        CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        TempReview.FindFirst();
        Review.Get(TempReview."Review No.");
        Assert.AreEqual('', ReviewMail.GetRecipientEmail(Review), 'With neither contact nor customer e-mail there must be no recipient at all');
        // [WHEN] The reviews are sent
        Sent := CustomerReviewMgt.SendReviews(TempReview);
        // [THEN] No mail counted, review Sent without e-mail stamps, hours still in review
        Assert.AreEqual(0, Sent, 'A review without a recipient must count as not e-mailed');
        Review.Get(TempReview."Review No.");
        Assert.AreEqual("BCJ Review Status"::Sent, Review.Status, 'SendReviews must send a Draft even when no e-mail can go out');
        Assert.AreNotEqual(0DT, Review."Sent On", 'A sent review must record when it was sent, mail or no mail');
        Assert.AreEqual('', Review."Sent To E-Mail", 'No recipient may be stamped when no mail was sent');
        Assert.AreEqual(0DT, Review."E-Mail Sent On", 'No e-mail timestamp may be stamped when no mail was sent');
        AssertBuckets('E1', 0, 2, 0, 0, 0, 'The hours must stay in review when the mail could not be sent');
    end;

    [Test]
    procedure GetReviewLink_IsBaseUrlPlusReviewPathAndToken()
    var
        Review: Record "BCJ Customer Review";
    begin
        // [SCENARIO] The link is the whole product for the customer: the web app routes on
        // /review/<token>, so the shape is a contract with that app, not a preference. A base URL
        // entered with a trailing slash is normal typing and must not produce a double slash,
        // which some mail clients and proxies mangle.
        // [GIVEN] A review and a base URL without a trailing slash
        Initialize();
        BCJTestLibrary.EnsureSetup('https://review.example.com');
        CreateSingleTaskProjectWithOpenEntry('E1', 2);
        CreateOneReview(Review);
        // [WHEN] / [THEN] The link is base + /review/ + token
        Assert.AreEqual('https://review.example.com/review/' + Review."Access Token", ReviewMail.GetReviewLink(Review), 'The review link must be the base URL followed by /review/ and the access token');
        // [WHEN] The same base URL is configured with a trailing slash
        BCJTestLibrary.EnsureSetup('https://review.example.com/');
        // [THEN] The link is identical - no double slash
        Assert.AreEqual('https://review.example.com/review/' + Review."Access Token", ReviewMail.GetReviewLink(Review), 'A trailing slash on the base URL must not produce a double slash in the review link');
    end;

    [Test]
    procedure BuildReviewEmail_HasRecipientTasksHoursAndLink()
    var
        Review: Record "BCJ Customer Review";
        EmailMessage: Codeunit "Email Message";
        Recipients: List of [Text];
        JobNo: Code[20];
        Body: Text;
    begin
        // [SCENARIO] The mail is all the customer gets: they must see which project it concerns,
        // which tasks were worked on and how many hours each, and be able to reach the review.
        // A mail missing a task is a mail that under-reports the work; a mail missing the link is
        // unanswerable. Only the given address may be addressed - a stray recipient leaks another
        // customer's hours.
        // [GIVEN] A review over two tasks with distinct hours
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        CreateTask(JobNo, 'T2');
        AddEntry('E1', JobNo, 'T1', D(), 7.5, "BCJ Billing Status"::Open);
        AddEntry('E2', JobNo, 'T2', D(), 13.25, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        // [WHEN] The message is built for one address
        ReviewMail.BuildReviewEmail(Review, 'reviewer@example.com', EmailMessage);
        EmailMessage.GetRecipients(Enum::"Email Recipient Type"::"To", Recipients);
        Body := EmailMessage.GetBody();
        // [THEN] Exactly that address, the project in the subject, both tasks, both figures and the link
        Assert.AreEqual(1, Recipients.Count(), 'The review mail must be addressed to exactly one recipient, the one it was built for');
        Assert.AreEqual('reviewer@example.com', Recipients.Get(1), 'The review mail must be addressed to the recipient it was built for');
        Assert.IsTrue(StrPos(EmailMessage.GetSubject(), JobNo) > 0, 'The subject must name the project, so a customer with several projects knows which one to open');
        Assert.IsTrue(StrPos(Body, 'T1') > 0, 'The body must list task T1, which had hours sent');
        Assert.IsTrue(StrPos(Body, 'T2') > 0, 'The body must list task T2, which had hours sent');
        Assert.IsTrue(ContainsHours(Body, 7.5), 'The body must show the hours logged on T1');
        Assert.IsTrue(ContainsHours(Body, 13.25), 'The body must show the hours logged on T2');
        Assert.IsTrue(StrPos(Body, Review."Access Token") > 0, 'The body must carry the access token, without which the customer cannot open the review');
        Assert.IsTrue(StrPos(Body, ReviewMail.GetReviewLink(Review)) > 0, 'The body must contain the full review link');
        Assert.IsTrue(StrPos(Body, 'href') > 0, 'The link must be a clickable anchor, not bare text a customer has to copy');
    end;

    // ---------------------------------------------------------------------------------
    // Submit and apply - approved hours Billable oldest first, the rest back to Open
    // ---------------------------------------------------------------------------------

    [Test]
    procedure SubmitReview_FullApprovalMakesEveryHourBillable()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] The customer approves everything. Every hour sent then becomes Billable
        // (approved, not invoiced) exactly as logged - the answer is applied immediately, because
        // a consultant who has to apply each answer by hand will eventually not bother.
        // [GIVEN] A sent review over two tasks and three entries
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        CreateTask(JobNo, 'T2');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('E2', JobNo, 'T1', D() + 1, 1, "BCJ Billing Status"::Open);
        AddEntry('E3', JobNo, 'T2', D(), 3, "BCJ Billing Status"::Open);
        CreateSentReview(Review);
        // [WHEN] Every line is approved in full and the review is submitted
        ApproveAllHoursToBill(Review."Review No.");
        CustomerReviewMgt.SubmitReview(Review);
        // [THEN] The review is answered and every hour is Billable
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Answered, Review.Status, 'A submitted review must be Answered');
        Assert.AreNotEqual(0DT, Review."Answered On", 'A submitted review must record when the customer answered');
        AssertBuckets('E1', 0, 0, 2, 0, 0, 'A fully approved entry must be Billable for all of its hours');
        AssertBuckets('E2', 0, 0, 1, 0, 0, 'A fully approved entry must be Billable for all of its hours');
        AssertBuckets('E3', 0, 0, 3, 0, 0, 'A fully approved entry must be Billable for all of its hours');
        BCJTestLibrary.AssertRow(JiraId('E1'), Review."Review No.", 0, 2, 0, 0, 'The approved hours must sit on the row of the review that approved them');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(3.0, ReviewLine."Applied Hours", 'Applied Hours must equal the approved hours when every approved hour found an entry');
        ReviewLine.Get(Review."Review No.", 'T2');
        Assert.AreEqual(3.0, ReviewLine."Applied Hours", 'Applied Hours must equal the approved hours when every approved hour found an entry');
        AssertOwnInvariant('After a full approval');
    end;

    [Test]
    procedure SubmitReview_ZeroApprovalReturnsEveryHourToOpen()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] Business flow step 5: "every hour not approved returns to Open". A rejection
        // is the customer's answer, not the consultant's write-off: the hours go back to the
        // consultant, who decides from the overview whether to write them off or raise them again.
        // [GIVEN] A sent review over one task with two entries
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('E2', JobNo, 'T1', D() + 1, 1, "BCJ Billing Status"::Open);
        CreateSentReview(Review);
        // [WHEN] The line is approved for zero hours and submitted
        BCJTestLibrary.SetApprovedHours(Review."Review No.", 'T1', 0);
        CustomerReviewMgt.SubmitReview(Review);
        // [THEN] Both entries are fully Open again
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Answered, Review.Status, 'A submitted review must be Answered even when nothing was approved');
        AssertBuckets('E1', 2, 0, 0, 0, 0, 'Hours the customer did not approve must return to Open, not be written off');
        AssertBuckets('E2', 1, 0, 0, 0, 0, 'Hours the customer did not approve must return to Open, not be written off');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(0.0, ReviewLine."Applied Hours", 'Nothing may be recorded as applied when nothing was approved');
    end;

    [Test]
    procedure SubmitReview_PartialApprovalAllocatesOldestEntryFirst()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] The customer approves fewer hours than were asked. The approval is per task,
        // so someone has to decide which worklog carries the cut: oldest first, deterministic and
        // auditable. The approval ends inside the newer worklog, which is split: its approved part
        // is Billable, its remainder returns to Open.
        // [GIVEN] A task with 1 h on day D and 3 h on day D+1, of which 2.5 are approved
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('OLD', JobNo, 'T1', D(), 1, "BCJ Billing Status"::Open);
        AddEntry('NEW', JobNo, 'T1', D() + 1, 3, "BCJ Billing Status"::Open);
        CreateSentReview(Review);
        // [WHEN] 2.5 hours are approved and the review is submitted
        BCJTestLibrary.SetApprovedHours(Review."Review No.", 'T1', 2.5);
        CustomerReviewMgt.SubmitReview(Review);
        // [THEN] The older entry is filled first, the newer takes the remainder and releases the rest
        AssertBuckets('OLD', 0, 0, 1, 0, 0, 'The oldest entry must be approved first and in full');
        AssertBuckets('NEW', 1.5, 0, 1.5, 0, 0, 'The newer entry must carry the cut: 1.5 approved, 1.5 back to Open');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(2.5, ReviewLine."Applied Hours", 'All approved hours must be applied when the entries can absorb them');
        AssertOwnInvariant('After a partial approval');
    end;

    [Test]
    procedure SubmitReview_PartialApprovalReturnsTheEntryLeftWithNothingToOpen()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] When the approved hours run out before the entries do, the entries left over
        // were not approved - they go back to Open, where the consultant decides on them. They
        // must not stay Billable for zero hours nor be silently written off.
        // [GIVEN] A task with 2 h on day D and 1 h on day D+1, of which exactly 2 are approved
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('OLD', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('NEW', JobNo, 'T1', D() + 1, 1, "BCJ Billing Status"::Open);
        CreateSentReview(Review);
        // [WHEN] 2 hours are approved and the review is submitted
        BCJTestLibrary.SetApprovedHours(Review."Review No.", 'T1', 2);
        CustomerReviewMgt.SubmitReview(Review);
        // [THEN] The older entry is Billable, the newer is Open again
        AssertBuckets('OLD', 0, 0, 2, 0, 0, 'The oldest entry must absorb the approved hours in full');
        AssertBuckets('NEW', 1, 0, 0, 0, 0, 'An entry left with no approved hours must be fully Open again');
        AssertStatus('NEW', "BCJ Billing Status"::Open, 'An entry left with no approved hours must show Open');
    end;

    [Test]
    procedure SubmitReview_SamePostingDateAllocatesInJiraIdOrder()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] Two worklogs on the same day are the common case, so posting date alone does
        // not determine the order. The Jira ID breaks the tie: the same answer applied twice must
        // always cut the same worklog, or two runs of the same review produce two invoices.
        // [GIVEN] Two 3-hour entries on the same day, of which only 3 hours are approved
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('A', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        AddEntry('B', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        CreateSentReview(Review);
        // [WHEN] 3 hours are approved and the review is submitted
        BCJTestLibrary.SetApprovedHours(Review."Review No.", 'T1', 3);
        CustomerReviewMgt.SubmitReview(Review);
        // [THEN] The lower Jira ID is served first and the other goes back to Open
        AssertBuckets('A', 0, 0, 3, 0, 0, 'On equal posting dates the lower Jira ID must be approved first');
        AssertBuckets('B', 3, 0, 0, 0, 0, 'On equal posting dates the higher Jira ID must be the one returned to Open');
    end;

    [Test]
    procedure ApplyAnswer_PartialApprovalInsideOneWorklogThenNextReviewTakesOnlyRemainder()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        FirstReview: Record "BCJ Customer Review";
        SecondReview: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] The reason for per-hour buckets: one Jira worklog can be partly approved and
        // partly unbilled. The customer approves 2.5 of a 4 h worklog; the 1.5 h not approved are
        // Open and can go into the next review - and only those 1.5 h, never the approved part.
        // [GIVEN] A 4 h worklog sent in full, of which the customer approves 2.5
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 4, "BCJ Billing Status"::Open);
        BCJTestLibrary.ReviewSingleEntry(JiraId('E1'), 4, 2.5, FirstReview);
        // [THEN] The worklog is split: 2.5 Billable, 1.5 Open
        AssertBuckets('E1', 1.5, 0, 2.5, 0, 0, 'A partly approved worklog must be Billable for the approved part and Open for the rest');
        AssertStatus('E1', "BCJ Billing Status"::Open, 'A worklog with Open hours left must show Open');
        // [WHEN] The project is put in review again
        FilterOwnProjects(TimeEntry);
        BCJTestLibrary.CreateDraftReview(TimeEntry, SecondReview);
        // [THEN] The new draft reserves only the 1.5 Open hours; the approved 2.5 stay with the first review
        Assert.AreNotEqual(FirstReview."Review No.", SecondReview."Review No.", 'The remainder must go into a new review');
        ReviewLine.Get(SecondReview."Review No.", 'T1');
        Assert.AreEqual(1.5, ReviewLine."Logged Hours", 'The next review must hold only the hours that were Open');
        BCJTestLibrary.AssertRow(JiraId('E1'), FirstReview."Review No.", 0, 2.5, 0, 0, 'The approved hours must stay on the first review''s row');
        BCJTestLibrary.AssertRow(JiraId('E1'), SecondReview."Review No.", 1.5, 0, 0, 0, 'Only the Open remainder may be reserved in the second review');
        AssertBuckets('E1', 0, 1.5, 2.5, 0, 0, 'The worklog must now be 1.5 in review and 2.5 approved');
        AssertOwnInvariant('After reviewing the remainder');
    end;

    [Test]
    procedure SubmitReview_SecondSubmitIsRejected()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] The customer's browser can be reloaded and the API can be called twice. A
        // second submit must not apply the answer again: the hours are no longer in review, so a
        // re-run would find nothing and could silently undo the allocation that was already made.
        // [GIVEN] A review that has been submitted once
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        CreateSentReview(Review);
        BCJTestLibrary.SetApprovedHours(Review."Review No.", 'T1', 2);
        CustomerReviewMgt.SubmitReview(Review);
        // [WHEN] It is submitted a second time
        Review.Get(Review."Review No.");
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror CustomerReviewMgt.SubmitReview(Review);
        // [THEN] The second submit is refused and nothing moved
        Assert.ExpectedErrorCode('TestField');
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Answered, Review.Status, 'A review already answered must stay Answered after a refused second submit');
        AssertBuckets('E1', 0, 0, 2, 0, 0, 'A refused second submit must leave the applied allocation untouched');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(2.0, ReviewLine."Applied Hours", 'A refused second submit must not change what was already applied');
    end;

    [Test]
    procedure SubmitReview_OnDraftIsRejected()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] A draft has not been shown to the customer, so there is nothing they could
        // have answered (contract: SubmitReview - review must be Sent). Accepting it would let a
        // leaked draft link decide hours the consultant is still preparing.
        // [GIVEN] A draft review
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        // [WHEN] It is submitted
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror CustomerReviewMgt.SubmitReview(Review);
        // [THEN] Refused; still a draft with its hours reserved
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Draft, Review.Status, 'A draft must stay a draft when a submit is refused');
        AssertBuckets('E1', 0, 2, 0, 0, 0, 'A refused submit must leave the reserved hours in review');
    end;

    [Test]
    procedure SubmitReview_AfterCancelIsRejected()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] The consultant cancels a review and the hours go back to Open. A customer who
        // still has the old link open must not be able to submit it afterwards - that would
        // re-decide hours the consultant has meanwhile taken back.
        // [GIVEN] A cancelled review that had an approval entered
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        CreateSentReview(Review);
        BCJTestLibrary.SetApprovedHours(Review."Review No.", 'T1', 2);
        CustomerReviewMgt.CancelReview(Review);
        // [WHEN] The customer submits the old link
        Review.Get(Review."Review No.");
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror CustomerReviewMgt.SubmitReview(Review);
        // [THEN] Refused; the review stays cancelled and the hours stay open
        Assert.ExpectedErrorCode('TestField');
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Cancelled, Review.Status, 'A cancelled review must stay cancelled when a late submit is refused');
        AssertBuckets('E1', 2, 0, 0, 0, 0, 'A late submit on a cancelled review must not re-decide the released hours');
    end;

    [Test]
    procedure ReviewLine_ApprovedHoursOutsideRangeIsRejected()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] The approved hours come from a public web form. Approving more than was asked
        // would invent hours nobody agreed to sell; approving a negative number is meaningless.
        // Both are refused at the field, before anything is stored, because the API writes the
        // line directly.
        // [GIVEN] A sent review line asking for 3 hours
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        CreateSentReview(Review);
        ReviewLine.Get(Review."Review No.", 'T1');
        // [WHEN] More hours than asked are approved
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror ReviewLine.Validate("Approved Hours", 4);
        // [THEN] Refused and the stored value is unchanged
        Assert.ExpectedErrorCode('Dialog');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(0.0, ReviewLine."Approved Hours", 'Approving more hours than were asked must leave the stored approval unchanged');
        // [WHEN] A negative number of hours is approved
        // (The field minimum may catch this before the range check does, so only the state is asserted.)
        // Nothing has been written since the Commit above, so this rolls back to the same point.
        asserterror ReviewLine.Validate("Approved Hours", -1);
        // [THEN] Refused and the stored value is still unchanged
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(0.0, ReviewLine."Approved Hours", 'Approving a negative number of hours must leave the stored approval unchanged');
    end;

    [Test]
    procedure ReviewLine_ModifyAfterAnsweredIsRejected()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] Once the answer has been applied, the lines are the record of what the
        // customer agreed to and what was billed on the strength of it. "Approved Hours" may only
        // change while the review is Sent, so editing an answered line is refused - it would leave
        // the review saying something different from what the worklogs carry.
        // [GIVEN] A review that has been answered
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        CreateSentReview(Review);
        BCJTestLibrary.SetApprovedHours(Review."Review No.", 'T1', 3);
        CustomerReviewMgt.SubmitReview(Review);
        // [WHEN] The customer tries to change the approved hours afterwards
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror BCJTestLibrary.SetApprovedHours(Review."Review No.", 'T1', 1);
        // [THEN] Refused and the answered line is unchanged
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(3.0, ReviewLine."Approved Hours", 'An answered review line must keep the hours the customer actually approved');
        AssertBuckets('E1', 0, 0, 3, 0, 0, 'A refused line edit must not change what was allocated to the entries');
    end;

    [Test]
    procedure SubmitReview_AfterEntriesDeletedAppliesWhatRemains()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        TimeEntry: Record "BCJ Project Time Entry";
        JobNo: Code[20];
    begin
        // [SCENARIO] Jira is the source of the worklogs and a worklog can be deleted there while
        // the customer is still holding the review; the sync deletes it with its allocation. The
        // customer's answer then refers to hours that no longer exist. Applying what remains and
        // recording the shortfall in Applied Hours is right: erroring would trap the review
        // forever, and inventing the missing hours would bill work the consultant has withdrawn.
        // [GIVEN] A sent review over 2 + 3 hours, of which the 3-hour worklog is deleted afterwards
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('KEPT', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('GONE', JobNo, 'T1', D() + 1, 3, "BCJ Billing Status"::Open);
        CreateSentReview(Review);
        GetEntry('GONE', TimeEntry);
        TimeEntry.Delete(true);
        // [WHEN] The customer approves all 5 hours and submits
        BCJTestLibrary.SetApprovedHours(Review."Review No.", 'T1', 5);
        CustomerReviewMgt.SubmitReview(Review);
        // [THEN] The surviving entry is billable in full, and the shortfall is visible, not an error
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Answered, Review.Status, 'A review whose entries partly disappeared must still be answerable');
        AssertBuckets('KEPT', 0, 0, 2, 0, 0, 'The surviving entry must take as much of the approval as it can carry');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(2.0, ReviewLine."Applied Hours", 'Applied Hours must show what could actually be allocated, not what was approved');
        Assert.AreEqual(5.0, ReviewLine."Approved Hours", 'What the customer approved must be kept as the customer stated it');
    end;

    [Test]
    procedure SubmitReview_AfterEntryHoursReducedCapsAllocation()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] A consultant can correct a worklog in Jira while the review is out, and the
        // sync trims the hours in review to the smaller number. The customer then approves 4 hours
        // against a worklog that now only holds 1.5. A worklog may never be billable for more hours
        // than it logs - the customer's approval is a ceiling, not a quantity to be invented.
        // [GIVEN] A sent review over one 4-hour worklog that is re-synced down to 1.5 hours
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 4, "BCJ Billing Status"::Open);
        CreateSentReview(Review);
        BCJTestLibrary.ChangeLoggedHours(JiraId('E1'), 1.5);
        // [WHEN] The customer approves the 4 hours they were originally shown
        BCJTestLibrary.SetApprovedHours(Review."Review No.", 'T1', 4);
        CustomerReviewMgt.SubmitReview(Review);
        // [THEN] Only the hours that still exist are approved
        AssertBuckets('E1', 0, 0, 1.5, 0, 0, 'A worklog must never be billable for more hours than it now logs');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(1.5, ReviewLine."Applied Hours", 'Applied Hours must show the capped allocation, not the approval');
    end;

    // ---------------------------------------------------------------------------------
    // Cancel, delete and reopen
    // ---------------------------------------------------------------------------------

    [Test]
    procedure CancelReview_DraftReturnsHoursToOpen()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] A draft prepared for the wrong period, or superseded, has to be taken back.
        // Its reserved hours must return to exactly the state they were in before - Open - or
        // they are stranded in review where no invoicing run and no later review picks them up.
        // [GIVEN] A draft review holding two entries
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('E2', JobNo, 'T1', D() + 1, 3, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        // [WHEN] The review is cancelled
        CustomerReviewMgt.CancelReview(Review);
        // [THEN] The hours are Open again, and the review records the cancellation
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Cancelled, Review.Status, 'A cancelled review must be Cancelled');
        Assert.AreNotEqual(0DT, Review."Cancelled On", 'A cancelled review must record when it was cancelled');
        AssertBuckets('E1', 2, 0, 0, 0, 0, 'A released entry must be fully Open again');
        AssertBuckets('E2', 3, 0, 0, 0, 0, 'A released entry must be fully Open again');
        AssertOwnInvariant('After cancelling a draft');
    end;

    [Test]
    procedure CancelReview_SentReturnsHoursToOpen()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] A review sent to the wrong customer, or settled by phone, is cancelled while
        // it is out. Everything still in review returns to Open; the hours the Send already cut
        // are Open anyway - so the task ends up exactly as it was before the review.
        // [GIVEN] A review over 6 h + 4 h sent with Hours to Bill 5
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('OLD', JobNo, 'T1', D(), 6, "BCJ Billing Status"::Open);
        AddEntry('NEW', JobNo, 'T1', D() + 1, 4, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        BCJTestLibrary.SetHoursToBill(Review."Review No.", 'T1', 5);
        BCJTestLibrary.SendDraftReview(Review);
        // [WHEN] The review is cancelled
        CustomerReviewMgt.CancelReview(Review);
        // [THEN] Every hour is Open again
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Cancelled, Review.Status, 'A sent review must be cancellable');
        AssertBuckets('OLD', 6, 0, 0, 0, 0, 'The hours still in review must return to Open');
        AssertBuckets('NEW', 4, 0, 0, 0, 0, 'The hours cut on Send must still be Open');
    end;

    [Test]
    procedure CancelReview_LeavesBilledHoursUntouched()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] Contract, ReleaseReview: "All In Review hours of the review return to Open.
        // Billable/Billed untouched". A reopened review can hold hours that were already invoiced
        // (Reopen never un-bills). Cancelling it must not drag an invoiced hour back to Open: the
        // invoice exists, and re-opening it would let the same hour be billed a second time.
        // [GIVEN] A review over E1 (4 h) and E2 (2 h), fully approved; E1 then invoiced; the review reopened
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 4, "BCJ Billing Status"::Open);
        AddEntry('E2', JobNo, 'T1', D() + 1, 2, "BCJ Billing Status"::Open);
        CreateSentReview(Review);
        BCJTestLibrary.SetApprovedHours(Review."Review No.", 'T1', 6);
        BCJTestLibrary.SubmitAnswer(Review);
        BCJTestLibrary.MarkEntryById(JiraId('E1'), "BCJ Billing Status"::Billed);
        CustomerReviewMgt.ReopenReview(Review);
        AssertBuckets('E1', 0, 0, 0, 0, 4, 'Fixture: Reopen must leave the invoiced hours Billed');
        AssertBuckets('E2', 0, 2, 0, 0, 0, 'Fixture: Reopen must put the approved, uninvoiced hours back in review');
        // [WHEN] The reopened review is cancelled
        Review.Get(Review."Review No.");
        CustomerReviewMgt.CancelReview(Review);
        // [THEN] Only the hours still in review are released
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Cancelled, Review.Status, 'A reopened review must be cancellable');
        AssertBuckets('E1', 0, 0, 0, 0, 4, 'Invoiced hours must stay Billed when their review is cancelled');
        AssertBuckets('E2', 2, 0, 0, 0, 0, 'The hours in review must be released back to Open');
    end;

    [Test]
    procedure CancelReview_AfterAnsweredIsRejected()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] Cancelling releases hours back to Open. Doing that after the customer has
        // answered would throw away their decision and re-open hours that are already approved -
        // the way back from an answered review is Reopen, which keeps the answer.
        // [GIVEN] An answered review
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        CreateSentReview(Review);
        BCJTestLibrary.SetApprovedHours(Review."Review No.", 'T1', 2);
        CustomerReviewMgt.SubmitReview(Review);
        // [WHEN] The consultant tries to cancel it
        Review.Get(Review."Review No.");
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror CustomerReviewMgt.CancelReview(Review);
        // [THEN] Refused, and the answer stands
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Answered, Review.Status, 'An answered review must stay Answered when a cancel is refused');
        AssertBuckets('E1', 0, 0, 2, 0, 0, 'A refused cancel must not release hours the customer already approved');
    end;

    [Test]
    procedure DeleteDraftReview_ReleasesItsHours()
    var
        Review: Record "BCJ Customer Review";
        ReviewNo: Integer;
        JobNo: Code[20];
    begin
        // [SCENARIO] Contract, table 50103: "A Draft or Cancelled review may be deleted; deleting a
        // Draft releases its hours to Open first." A consultant who throws a draft away must get
        // the hours back - deleting the review without releasing would reserve them in a review
        // that no longer exists, where nothing can ever reach them again.
        // [GIVEN] A draft review holding 3 hours
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        ReviewNo := Review."Review No.";
        // [WHEN] The draft is deleted
        Review.Delete(true);
        // [THEN] The review is gone and the hours are Open
        Assert.IsFalse(Review.Get(ReviewNo), 'The draft must be deleted');
        AssertBuckets('E1', 3, 0, 0, 0, 0, 'Deleting a draft must release its hours to Open');
        AssertOwnInvariant('After deleting a draft');
    end;

    [Test]
    procedure DeleteSentReview_IsRefused()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] Only Draft and Cancelled reviews may be deleted. A sent review is out with the
        // customer and holds their pending answer; deleting it would strand its hours in review
        // and leave the customer holding a dead link.
        // [GIVEN] A sent review
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        CreateSentReview(Review);
        // [WHEN] It is deleted
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror Review.Delete(true);
        // [THEN] Refused; the review and its reservation are intact
        Assert.IsTrue(Review.Get(Review."Review No."), 'A sent review must not be deletable');
        AssertBuckets('E1', 0, 3, 0, 0, 0, 'A refused delete must leave the hours in review');
    end;

    [Test]
    procedure ReopenReview_MovesApprovedHoursBackInReviewAndKeepsTheAnswer()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] The customer answers, then phones to say they meant something else. Reopen
        // (contract: ReReserveReview(Hours to Bill)) puts the review's approved hours back in
        // review and tops up, oldest first, from the Open hours of its own worklogs until the
        // review again holds the Hours to Bill it asked for. What the customer approved is kept
        // for discussion, and submitting the same answer again must give the same allocation,
        // not a doubled one.
        // [GIVEN] An answered review over OLD 2 h and NEW 3 h, asked 5, approved 4
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('OLD', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('NEW', JobNo, 'T1', D() + 1, 3, "BCJ Billing Status"::Open);
        CreateSentReview(Review);
        BCJTestLibrary.SetApprovedHours(Review."Review No.", 'T1', 4);
        BCJTestLibrary.SubmitAnswer(Review);
        AssertBuckets('OLD', 0, 0, 2, 0, 0, 'Fixture: the first answer must have been applied oldest first');
        AssertBuckets('NEW', 1, 0, 2, 0, 0, 'Fixture: the unapproved hour must have returned to Open');
        // [WHEN] The review is reopened
        CustomerReviewMgt.ReopenReview(Review);
        // [THEN] Sent again, all 5 hours back in review, the answer kept
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Sent, Review.Status, 'A reopened review must be Sent again, waiting for a new answer');
        Assert.AreEqual(0DT, Review."Answered On", 'A reopened review must no longer claim to have been answered');
        AssertBuckets('OLD', 0, 2, 0, 0, 0, 'The approved hours of the older worklog must be back in review');
        AssertBuckets('NEW', 0, 3, 0, 0, 0, 'The approved hours plus the released hour must be back in review, up to Hours to Bill');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(0.0, ReviewLine."Applied Hours", 'A reopened line must show nothing as applied, because the allocation was undone');
        Assert.AreEqual(4.0, ReviewLine."Approved Hours", 'A reopened line must keep what the customer approved, so it can be discussed and adjusted');
        AssertOwnInvariant('After Reopen');
        // [WHEN] It is submitted again unchanged
        BCJTestLibrary.SubmitAnswer(Review);
        // [THEN] The same allocation is produced again, not doubled
        Assert.AreEqual("BCJ Review Status"::Answered, Review.Status, 'A reopened review must be answerable again');
        AssertBuckets('OLD', 0, 0, 2, 0, 0, 'Re-applying the same answer must give the same allocation as the first time');
        AssertBuckets('NEW', 1, 0, 2, 0, 0, 'Re-applying the same answer must give the same allocation as the first time');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(4.0, ReviewLine."Applied Hours", 'Re-applying the same answer must apply the approved hours once, not twice');
    end;

    [Test]
    procedure ReopenReview_WhenHoursNoLongerAvailableErrorsAndChangesNothing()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        FirstReview: Record "BCJ Customer Review";
        SecondReview: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] Contract, ReopenReview: "if any line reaches less than its Hours to Bill the
        // reopen errors and nothing changes". The hours the customer did not approve went back to
        // Open and may meanwhile sit in another review. Reopening must not steal them from that
        // review, and must not leave a half-reopened review asking for hours it no longer holds.
        // [GIVEN] A 4 h worklog, asked 4, approved 2; the 2 Open hours then reserved in a new draft
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 4, "BCJ Billing Status"::Open);
        BCJTestLibrary.ReviewSingleEntry(JiraId('E1'), 4, 2, FirstReview);
        FilterOwnProjects(TimeEntry);
        BCJTestLibrary.CreateDraftReview(TimeEntry, SecondReview);
        // [WHEN] The first review is reopened
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror CustomerReviewMgt.ReopenReview(FirstReview);
        // [THEN] Refused; both reviews and the worklog are exactly as before
        FirstReview.Get(FirstReview."Review No.");
        Assert.AreEqual("BCJ Review Status"::Answered, FirstReview.Status, 'A reopen that cannot restore its Hours to Bill must leave the review Answered');
        BCJTestLibrary.AssertRow(JiraId('E1'), FirstReview."Review No.", 0, 2, 0, 0, 'The approved hours must stay approved when the reopen is refused');
        BCJTestLibrary.AssertRow(JiraId('E1'), SecondReview."Review No.", 2, 0, 0, 0, 'The other review must keep its reserved hours');
        AssertBuckets('E1', 0, 2, 2, 0, 0, 'A refused reopen must not move any hour');
    end;

    [Test]
    procedure ReopenReview_OnSentOrDraftReviewIsRejected()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] Reopen exists to undo an applied answer (Answered -> Sent). On a review the
        // customer has not answered there is nothing to undo; the consultant who wants the hours
        // back uses Cancel.
        // [GIVEN] A draft review
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        // [WHEN] It is reopened
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror CustomerReviewMgt.ReopenReview(Review);
        // [THEN] Refused, and nothing about the review changed
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Draft, Review.Status, 'A draft must stay a draft when a reopen is refused');
        AssertBuckets('E1', 0, 2, 0, 0, 0, 'A refused reopen must leave the hours in review');
        // [WHEN] It is sent and then reopened
        BCJTestLibrary.SendDraftReview(Review);
        // Commit so the sent state survives the next asserterror rollback.
        Commit();
        asserterror CustomerReviewMgt.ReopenReview(Review);
        // [THEN] Refused as well
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Sent, Review.Status, 'A review still waiting for an answer must stay Sent when a reopen is refused');
        AssertBuckets('E1', 0, 2, 0, 0, 0, 'A refused reopen must leave the hours in review');
    end;

    // ---------------------------------------------------------------------------------
    // Interaction with the overview actions
    // ---------------------------------------------------------------------------------

    [Test]
    procedure SetBillingStatus_SkipsHoursInReview()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
        Changed: Integer;
        InReview: Integer;
    begin
        // [SCENARIO] "Mark as Billable" over a project must not overrule a review: deciding hours
        // behind the customer's back would make the answer contradict what was already decided.
        // SetBillingStatus never touches In Review hours; they are not counted as changed, and
        // CountEntriesInReview tells the consultant why the count is smaller than the selection.
        // [GIVEN] A project with an Open entry, an already Billable entry and an entry in a review
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        CreateTask(JobNo, 'T2');
        AddEntry('OPEN', JobNo, 'T1', D(), 1, "BCJ Billing Status"::Open);
        AddEntry('BILLABLE', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Billable);
        AddEntry('INREVIEW', JobNo, 'T2', D(), 3, "BCJ Billing Status"::Open);
        FilterOwnProjects(TimeEntry);
        TimeEntry.SetRange("Project Task No.", 'T2');
        BCJTestLibrary.CreateDraftReview(TimeEntry, Review);
        // [WHEN] The whole project is marked Billable
        FilterOwnProjects(TimeEntry);
        Changed := BillingMgt.SetBillingStatus(TimeEntry, "BCJ Billing Status"::Billable);
        // [THEN] The entry in review is neither changed nor counted, and is reported separately
        Assert.AreEqual(1, Changed, 'Only the Open entry may be changed and counted');
        AssertBuckets('OPEN', 0, 0, 1, 0, 0, 'An Open entry outside any review must become Billable');
        AssertBuckets('BILLABLE', 0, 0, 2, 0, 0, 'An already Billable entry must keep its hours');
        AssertBuckets('INREVIEW', 0, 3, 0, 0, 0, 'Hours in a customer review must not be re-decided behind the customer''s back');
        FilterOwnProjects(TimeEntry);
        InReview := BillingMgt.CountEntriesInReview(TimeEntry);
        Assert.AreEqual(1, InReview, 'CountEntriesInReview must report the entries holding hours in review');
    end;

    [Test]
    procedure TimeEntry_InsertStartsWithAllHoursOpen()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Stored: Record "BCJ Project Time Entry";
        JobNo: Code[20];
    begin
        // [SCENARIO] Contract: "On insert: Open = Unbilled = L, all other buckets 0, status Open.
        // Billable Hours no longer defaults to L." A freshly synced worklog is undecided - calling
        // it Billable would let it be invoiced without anyone approving it. The buckets are written
        // only by the allocation codeunit, so a value a caller put in Billable Hours is not kept.
        // [GIVEN] A project and task
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        // [WHEN] An entry is inserted with triggers
        TimeEntry.Init();
        TimeEntry."Jira ID" := JiraId('E1');
        TimeEntry."Jira Issue Id" := CopyStr('I-' + JiraId('E1'), 1, 50);
        TimeEntry."Project No." := JobNo;
        TimeEntry."Project Task No." := 'T1';
        TimeEntry."Posting Date" := D();
        TimeEntry."Time Spent in Hours" := 2.5;
        TimeEntry.Insert(true);
        // [THEN] Every hour is Open and Unbilled, nothing is Billable
        Stored.Get(JiraId('E1'), CopyStr('I-' + JiraId('E1'), 1, 50));
        Assert.AreEqual(2.5, Stored."Open Hours", 'A newly synced worklog must be fully Open');
        Assert.AreEqual(2.5, Stored."Unbilled Hours", 'A newly synced worklog must be fully Unbilled');
        Assert.AreEqual(0.0, Stored."Billable Hours", 'A newly synced worklog must not be Billable until someone approves it');
        Assert.AreEqual(0.0, Stored."In Review Hours", 'A newly synced worklog must not be in review');
        Assert.AreEqual("BCJ Billing Status"::Open, Stored."Billing Status", 'A newly synced worklog must show Open');
        // [WHEN] An entry is inserted with a Billable Hours value already set by the caller
        TimeEntry.Init();
        TimeEntry."Jira ID" := JiraId('E2');
        TimeEntry."Jira Issue Id" := CopyStr('I-' + JiraId('E2'), 1, 50);
        TimeEntry."Project No." := JobNo;
        TimeEntry."Project Task No." := 'T1';
        TimeEntry."Posting Date" := D();
        TimeEntry."Time Spent in Hours" := 4;
        TimeEntry."Billable Hours" := 1;
        TimeEntry.Insert(true);
        // [THEN] The insert still starts it fully Open
        Stored.Get(JiraId('E2'), CopyStr('I-' + JiraId('E2'), 1, 50));
        Assert.AreEqual(4.0, Stored."Open Hours", 'Insert must start every worklog fully Open whatever the caller put in the buckets');
        Assert.AreEqual(0.0, Stored."Billable Hours", 'Insert must reset Billable Hours - only the allocation codeunit writes buckets');
    end;

    // ---------------------------------------------------------------------------------
    // Overview hours - read from the bucket cache
    // ---------------------------------------------------------------------------------

    [Test]
    procedure Overview_PartlyApprovedEntryIsBillableAndOpen()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
        CustomerNo: Code[20];
        JobNo: Code[20];
    begin
        // [SCENARIO] After a partial approval one worklog carries two buckets: the approved hours
        // are Billable, the rest is Open for the consultant to decide on. The overview must show
        // both, and both are still Unbilled - nothing has been invoiced or written off yet.
        // [GIVEN] A 3 h worklog of which the customer approved 1.5
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobNo := CreateProject('P1', CustomerNo);
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        BCJTestLibrary.ReviewSingleEntry(JiraId('E1'), 3, 1.5, Review);
        // [WHEN] The overview is built
        FilterOwnProjects(TimeEntryFilter);
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, true);
        // [THEN] Total 3, Open 1.5, Billable 1.5, Unbilled 3
        FindLine(Buffer, LineType::Task, CustomerNo, JobNo, 'T1');
        AssertHours(Buffer, 3, 1.5, 0, 1.5, 0, 0, 3, 'Task with a partly approved worklog');
        FindEntryLine(Buffer, 'E1');
        AssertHours(Buffer, 3, 1.5, 0, 1.5, 0, 0, 3, 'Partly approved worklog');
        FindLine(Buffer, LineType::Project, CustomerNo, JobNo, '');
        AssertHours(Buffer, 3, 1.5, 0, 1.5, 0, 0, 3, 'Project with a partly approved worklog');
    end;

    [Test]
    procedure Overview_InvoicedAndWrittenOffPartsOfOneEntry()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
        CustomerNo: Code[20];
        JobNo: Code[20];
    begin
        // [SCENARIO] Business flow step 6: approved hours are billed after invoicing, the rest is
        // written off. The worklog then holds Billed and Not Billable hours and nothing is still
        // to be chased - it must add nothing to Unbilled, or the same hours are chased twice.
        // [GIVEN] A 3 h worklog: 1 approved and invoiced, the 2 unapproved written off
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobNo := CreateProject('P1', CustomerNo);
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        BCJTestLibrary.ReviewSingleEntry(JiraId('E1'), 3, 1, Review);
        BCJTestLibrary.MarkEntryById(JiraId('E1'), "BCJ Billing Status"::Billed);
        BCJTestLibrary.MarkEntryById(JiraId('E1'), "BCJ Billing Status"::"Not Billable");
        // [WHEN] The overview is built
        FilterOwnProjects(TimeEntryFilter);
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, true);
        // [THEN] Total 3, Billed 1, Not Billable 2, nothing unbilled
        FindLine(Buffer, LineType::Task, CustomerNo, JobNo, 'T1');
        AssertHours(Buffer, 3, 0, 0, 0, 2, 1, 0, 'Task with an invoiced and written-off worklog');
        FindLine(Buffer, LineType::Project, CustomerNo, JobNo, '');
        AssertHours(Buffer, 3, 0, 0, 0, 2, 1, 0, 'Project with an invoiced and written-off worklog');
        AssertStatus('E1', "BCJ Billing Status"::Billed, 'A worklog with Billed and Not Billable hours shows Billed (precedence Billed over Not Billable)');
    end;

    [Test]
    procedure Overview_SentForReviewHoursCountAsUnbilled()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
        CustomerNo: Code[20];
        JobNo: Code[20];
    begin
        // [SCENARIO] Hours in a review are undecided but not forgotten: they get their own bucket
        // so the consultant can see what is waiting on an answer, and they still count as
        // unbilled, because they are money the firm expects to invoice once the answer comes.
        // [GIVEN] An open entry of 4 hours that is put in a review
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobNo := CreateProject('P1', CustomerNo);
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 4, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        // [WHEN] The overview is built
        FilterOwnProjects(TimeEntryFilter);
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, true);
        // [THEN] All 4 hours sit in Sent for Review, and Unbilled still includes them
        FindLine(Buffer, LineType::Task, CustomerNo, JobNo, 'T1');
        AssertHours(Buffer, 4, 0, 4, 0, 0, 0, 4, 'Task whose hours are in review');
        FindLine(Buffer, LineType::Customer, CustomerNo, '', '');
        AssertHours(Buffer, 4, 0, 4, 0, 0, 0, 4, 'Customer whose hours are in review');
    end;

    [Test]
    procedure Overview_BucketsSumToTotalOnEveryLevel()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        TimeEntry: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
        CustomerNo: Code[20];
        JobA: Code[20];
        JobB: Code[20];
    begin
        // [SCENARIO] The five buckets are how the overview is read: every logged hour is in
        // exactly one of them, on every row of the tree - including worklogs split across
        // several buckets. If they stop adding up to the total, the page is lying about where the
        // work in progress sits. Unbilled = Open + Sent for Review + Billable.
        // [GIVEN] One customer, two projects and all five buckets at once, several inside one worklog
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobA := CreateProject('P1', CustomerNo);
        JobB := CreateProject('P2', CustomerNo);
        CreateTask(JobA, 'T1');
        CreateTask(JobA, 'T2');
        CreateTask(JobB, 'T1');
        AddEntry('OPEN', JobA, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('BILLABLE', JobA, 'T1', D(), 4, "BCJ Billing Status"::Open);
        BCJTestLibrary.ReviewSingleEntry(JiraId('BILLABLE'), 4, 2.5, Review);
        AddEntry('BILLED', JobA, 'T2', D(), 3, "BCJ Billing Status"::Open);
        BCJTestLibrary.ReviewSingleEntry(JiraId('BILLED'), 3, 1, Review);
        BCJTestLibrary.MarkEntryById(JiraId('BILLED'), "BCJ Billing Status"::Billed);
        AddEntry('NOTBILL', JobB, 'T1', D(), 1.5, "BCJ Billing Status"::"Not Billable");
        AddEntry('INREVIEW', JobB, 'T1', D(), 5, "BCJ Billing Status"::Open);
        FilterOwnProjects(TimeEntry);
        TimeEntry.SetRange("Jira ID", JiraId('INREVIEW'));
        BCJTestLibrary.CreateDraftReview(TimeEntry, Review);
        // [WHEN] The overview is built over the whole customer
        FilterOwnProjects(TimeEntryFilter);
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, true);
        // [THEN] The customer row shows every bucket, and no row anywhere breaks the invariant
        // Open 2 + 1.5 + 2 = 5.5, Sent for Review 5, Billable 2.5, Not Billable 1.5, Billed 1
        FindLine(Buffer, LineType::Customer, CustomerNo, '', '');
        AssertHours(Buffer, 15.5, 5.5, 5, 2.5, 1.5, 1, 13, 'Customer with hours in all five buckets');
        AssertBucketsBalanceOnEveryLine(Buffer);
        AssertOwnInvariant('Overview fixture');
    end;

    [Test]
    procedure Overview_DraftShowsAllReservedHoursUntilSent()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
        CustomerNo: Code[20];
        JobNo: Code[20];
    begin
        // [SCENARIO] Lowering Hours to Bill on a draft is a plan, not yet a decision: the cut hours
        // only return to Open when the review is sent (business flow step 4). Until then the
        // draft still reserves everything, so the overview shows all 10 hours in review.
        // [GIVEN] A draft over 6 h + 4 h with Hours to Bill lowered to 5
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobNo := CreateProject('P1', CustomerNo);
        CreateTask(JobNo, 'T1');
        AddEntry('OLD', JobNo, 'T1', D(), 6, "BCJ Billing Status"::Open);
        AddEntry('NEW', JobNo, 'T1', D() + 1, 4, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        BCJTestLibrary.SetHoursToBill(Review."Review No.", 'T1', 5);
        // [WHEN] The overview is built
        FilterOwnProjects(TimeEntryFilter);
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, false);
        // [THEN] All 10 hours are still in review
        FindLine(Buffer, LineType::Task, CustomerNo, JobNo, 'T1');
        AssertHours(Buffer, 10, 0, 10, 0, 0, 0, 10, 'Task of a draft whose Hours to Bill was lowered but not yet sent');
    end;

    [Test]
    procedure Overview_AfterSendSentForReviewIsHoursToBillAndCutIsOpen()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
        CustomerNo: Code[20];
        JobNo: Code[20];
    begin
        // [SCENARIO] The business case: 10 hours were logged, the consultant charges only half and
        // sends 50%. From then on the customer is being asked for 5 hours, so Sent for Review is 5;
        // the 5 hours cut are Open (the consultant still decides to write them off or keep them),
        // and all 10 are still Unbilled. Total stays the hours worked.
        // [GIVEN] A task with 6 h (older) and 4 h (newer), sent at 50%
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobNo := CreateProject('P1', CustomerNo);
        CreateTask(JobNo, 'T1');
        AddEntry('OLD', JobNo, 'T1', D(), 6, "BCJ Billing Status"::Open);
        AddEntry('NEW', JobNo, 'T1', D() + 1, 4, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        CustomerReviewMgt.SetHoursToBillPct(Review, 50);
        BCJTestLibrary.SendDraftReview(Review);
        // [WHEN] The overview is built
        FilterOwnProjects(TimeEntryFilter);
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, true);
        // [THEN] Task, project and customer: Total 10, Open 5, Sent for Review 5, Unbilled 10
        FindLine(Buffer, LineType::Task, CustomerNo, JobNo, 'T1');
        AssertHours(Buffer, 10, 5, 5, 0, 0, 0, 10, 'Task sent at 50% of 10 logged hours');
        FindLine(Buffer, LineType::Project, CustomerNo, JobNo, '');
        AssertHours(Buffer, 10, 5, 5, 0, 0, 0, 10, 'Project sent at 50% of 10 logged hours');
        FindLine(Buffer, LineType::Customer, CustomerNo, '', '');
        AssertHours(Buffer, 10, 5, 5, 0, 0, 0, 10, 'Customer sent at 50% of 10 logged hours');
        // [THEN] Per worklog, oldest first: OLD 5 in review + 1 Open, NEW 4 Open
        FindEntryLine(Buffer, 'OLD');
        AssertHours(Buffer, 6, 1, 5, 0, 0, 0, 6, 'Older worklog of a task sent for 5 of 10 hours');
        FindEntryLine(Buffer, 'NEW');
        AssertHours(Buffer, 4, 4, 0, 0, 0, 0, 4, 'Newer worklog of a task sent for 5 of 10 hours');
        AssertBucketsBalanceOnEveryLine(Buffer);
    end;

    [Test]
    procedure Overview_AfterSendShareSpillsIntoNewerEntry()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
        CustomerNo: Code[20];
        JobNo: Code[20];
    begin
        // [SCENARIO] When the request is larger than the oldest worklog, that worklog is kept in
        // review completely and the rest spills into the next one - no worklog can hold more in
        // review than it logs, and none of the request may disappear.
        // [GIVEN] A task with 6 h (older) and 4 h (newer), sent asking for 7
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobNo := CreateProject('P1', CustomerNo);
        CreateTask(JobNo, 'T1');
        AddEntry('OLD', JobNo, 'T1', D(), 6, "BCJ Billing Status"::Open);
        AddEntry('NEW', JobNo, 'T1', D() + 1, 4, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        BCJTestLibrary.SetHoursToBill(Review."Review No.", 'T1', 7);
        BCJTestLibrary.SendDraftReview(Review);
        // [WHEN] The overview is built down to the worklogs
        FilterOwnProjects(TimeEntryFilter);
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, true);
        // [THEN] Older 6 in review, newer 1 in review + 3 Open, task 7 + 3
        FindEntryLine(Buffer, 'OLD');
        AssertHours(Buffer, 6, 0, 6, 0, 0, 0, 6, 'Older worklog of a task asking for 7 of 10 hours');
        FindEntryLine(Buffer, 'NEW');
        AssertHours(Buffer, 4, 3, 1, 0, 0, 0, 4, 'Newer worklog of a task asking for 7 of 10 hours');
        FindLine(Buffer, LineType::Task, CustomerNo, JobNo, 'T1');
        AssertHours(Buffer, 10, 3, 7, 0, 0, 0, 10, 'Task asking for 7 of 10 hours');
    end;

    [Test]
    procedure Overview_SplitIsPerWorklogUnderDateFilter()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
        CustomerNo: Code[20];
        JobNo: Code[20];
    begin
        // [SCENARIO] The overview reads each worklog's own buckets, so a worklog shows the same
        // split whether the overview covers the whole review or one day of it. If a date filter
        // re-spread the request over the visible worklogs only, the same 5 requested hours would
        // be counted once per period and the periods together would promise more than was asked.
        // [GIVEN] A task with 6 h (day D) and 4 h (day D+1), sent at 50%
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobNo := CreateProject('P1', CustomerNo);
        CreateTask(JobNo, 'T1');
        AddEntry('OLD', JobNo, 'T1', D(), 6, "BCJ Billing Status"::Open);
        AddEntry('NEW', JobNo, 'T1', D() + 1, 4, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        CustomerReviewMgt.SetHoursToBillPct(Review, 50);
        BCJTestLibrary.SendDraftReview(Review);
        // [WHEN] The overview is built for day D only
        FilterOwnProjects(TimeEntryFilter);
        TimeEntryFilter.SetRange("Posting Date", D());
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, true);
        // [THEN] The task shows the older worklog's own split: 5 in review, 1 Open
        FindLine(Buffer, LineType::Task, CustomerNo, JobNo, 'T1');
        AssertHours(Buffer, 6, 1, 5, 0, 0, 0, 6, 'Task filtered to the day of the older worklog');
        // [WHEN] The overview is built for day D+1 only
        Buffer.Reset();
        Buffer.DeleteAll();
        FilterOwnProjects(TimeEntryFilter);
        TimeEntryFilter.SetRange("Posting Date", D() + 1);
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, true);
        // [THEN] The newer worklog's own split: nothing in review, 4 Open
        FindLine(Buffer, LineType::Task, CustomerNo, JobNo, 'T1');
        AssertHours(Buffer, 4, 4, 0, 0, 0, 0, 4, 'Task filtered to the day of the newer worklog');
    end;

    [Test]
    procedure Overview_CutOnOneTaskLeavesOtherTaskAlone()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
        CustomerNo: Code[20];
        JobNo: Code[20];
    begin
        // [SCENARIO] Hours to Bill is decided per task: cutting one task is a decision about that
        // task only. The other task of the same review is still asked for in full, and the
        // customer and project rows must add the two up correctly.
        // [GIVEN] One review over T1 (6 h + 4 h, 5 asked for) and T2 (3 h, asked in full), sent
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobNo := CreateProject('P1', CustomerNo);
        CreateTask(JobNo, 'T1');
        CreateTask(JobNo, 'T2');
        AddEntry('OLD', JobNo, 'T1', D(), 6, "BCJ Billing Status"::Open);
        AddEntry('NEW', JobNo, 'T1', D() + 1, 4, "BCJ Billing Status"::Open);
        AddEntry('OTHER', JobNo, 'T2', D(), 3, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        BCJTestLibrary.SetHoursToBill(Review."Review No.", 'T1', 5);
        BCJTestLibrary.SendDraftReview(Review);
        // [WHEN] The overview is built down to the worklogs
        FilterOwnProjects(TimeEntryFilter);
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, true);
        // [THEN] T1 is cut, T2 is untouched, and project and customer add both up
        FindLine(Buffer, LineType::Task, CustomerNo, JobNo, 'T1');
        AssertHours(Buffer, 10, 5, 5, 0, 0, 0, 10, 'Task T1 asking for 5 of 10 hours');
        FindLine(Buffer, LineType::Task, CustomerNo, JobNo, 'T2');
        AssertHours(Buffer, 3, 0, 3, 0, 0, 0, 3, 'Task T2 asked for in full next to a cut task');
        FindLine(Buffer, LineType::Project, CustomerNo, JobNo, '');
        AssertHours(Buffer, 13, 5, 8, 0, 0, 0, 13, 'Project with one cut task and one full task');
        FindLine(Buffer, LineType::Customer, CustomerNo, '', '');
        AssertHours(Buffer, 13, 5, 8, 0, 0, 0, 13, 'Customer with one cut task and one full task');
        AssertBucketsBalanceOnEveryLine(Buffer);
    end;

    [Test]
    procedure Overview_FollowsTheWholeLifecycleOfOneTask()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
        CustomerNo: Code[20];
        JobNo: Code[20];
    begin
        // [SCENARIO] BuildOverview reads the cached buckets on every level, so each step of the
        // business flow is visible at once: sent (Sent for Review 5, cut 5 Open), answered with
        // 3 of 5 approved (Billable 3, unapproved 2 back to Open), invoiced (Billed 3) and the
        // rest written off (Not Billable 7, nothing Unbilled).
        // [GIVEN] A task with 6 h (older) and 4 h (newer), sent asking for 5
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobNo := CreateProject('P1', CustomerNo);
        CreateTask(JobNo, 'T1');
        AddEntry('OLD', JobNo, 'T1', D(), 6, "BCJ Billing Status"::Open);
        AddEntry('NEW', JobNo, 'T1', D() + 1, 4, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        BCJTestLibrary.SetHoursToBill(Review."Review No.", 'T1', 5);
        BCJTestLibrary.SendDraftReview(Review);
        FilterOwnProjects(TimeEntryFilter);
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, false);
        FindLine(Buffer, LineType::Project, CustomerNo, JobNo, '');
        AssertHours(Buffer, 10, 5, 5, 0, 0, 0, 10, 'Project after Send');
        // [WHEN] The customer approves 3
        BCJTestLibrary.SetApprovedHours(Review."Review No.", 'T1', 3);
        BCJTestLibrary.SubmitAnswer(Review);
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, false);
        // [THEN] 3 Billable, 7 Open, all still Unbilled
        FindLine(Buffer, LineType::Project, CustomerNo, JobNo, '');
        AssertHours(Buffer, 10, 7, 0, 3, 0, 0, 10, 'Project after the answer');
        // [WHEN] The project is invoiced and the rest written off
        FilterOwnProjects(TimeEntryFilter);
        BillingMgt.SetBillingStatus(TimeEntryFilter, "BCJ Billing Status"::Billed);
        FilterOwnProjects(TimeEntryFilter);
        BillingMgt.SetBillingStatus(TimeEntryFilter, "BCJ Billing Status"::"Not Billable");
        FilterOwnProjects(TimeEntryFilter);
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, false);
        // [THEN] 3 Billed, 7 Not Billable, nothing Unbilled
        FindLine(Buffer, LineType::Project, CustomerNo, JobNo, '');
        AssertHours(Buffer, 10, 0, 0, 0, 7, 3, 0, 'Project after invoicing and write-off');
        AssertOwnInvariant('End of the lifecycle');
    end;

    local procedure FindEntryLine(var Buffer: Record "BCJ Billing Overview Buffer" temporary; Suffix: Text)
    begin
        Buffer.Reset();
        Buffer.SetRange("Line Type", LineType::"Time Entry");
        Buffer.SetRange("Jira ID", JiraId(Suffix));
        Assert.AreEqual(1, Buffer.Count(), StrSubstNo('Exactly one time entry line must exist for worklog %1', JiraId(Suffix)));
        Buffer.FindFirst();
    end;

    local procedure AssertBucketsBalanceOnEveryLine(var Buffer: Record "BCJ Billing Overview Buffer" temporary)
    var
        LineName: Text;
    begin
        Buffer.Reset();
        Buffer.FindSet();
        repeat
            LineName := StrSubstNo('%1 line %2 %3 %4 %5', Buffer."Line Type", Buffer."Customer No.", Buffer."Project No.", Buffer."Project Task No.", Buffer."Jira ID");
            Assert.AreEqual(
              Buffer."Total Hours",
              Buffer."Open Hours" + Buffer."Sent for Review Hours" + Buffer."Billable Hours" + Buffer."Not Billable Hours" + Buffer."Billed Hours",
              LineName + ': every logged hour must sit in exactly one bucket, so the five buckets must add up to Total Hours');
            Assert.AreEqual(
              Buffer."Unbilled Hours",
              Buffer."Open Hours" + Buffer."Sent for Review Hours" + Buffer."Billable Hours",
              LineName + ': Unbilled Hours must be everything not yet invoiced and not written off');
        until Buffer.Next() = 0;
    end;

    // ---------------------------------------------------------------------------------
    // GetOpenReviews - Draft and Sent reviews holding hours of the selection
    // ---------------------------------------------------------------------------------

    [Test]
    procedure GetOpenReviews_OneReviewManyEntriesGivesOneReview()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempOpenReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
        Found: Integer;
    begin
        // [SCENARIO] The consultant selects worklogs to see which review holds them. A review is
        // one thing to act on no matter how many worklogs it covers: listing it once per entry
        // would duplicate it. Looking the review up is read-only.
        // [GIVEN] One draft review holding three entries over two tasks
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        CreateTask(JobNo, 'T2');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('E2', JobNo, 'T1', D() + 1, 1, "BCJ Billing Status"::Open);
        AddEntry('E3', JobNo, 'T2', D(), 3, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        // [WHEN] The open reviews are requested for the whole project
        FilterOwnProjects(TimeEntry);
        Found := CustomerReviewMgt.GetOpenReviews(TimeEntry, TempOpenReview);
        // [THEN] Exactly the one review, once
        Assert.AreEqual(1, Found, 'Several entries of one review must count as exactly one open review');
        Assert.AreEqual(1, TempOpenReview.Count(), 'Several entries of one review must put that review into the result exactly once');
        AssertHoldsReview(TempOpenReview, Review, 'The one draft review must be in the result with its own Review No. and Project No.');
        // [THEN] Nothing was changed by looking
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Draft, Review.Status, 'Looking up the open reviews must leave the review a Draft');
        AssertBuckets('E1', 0, 2, 0, 0, 0, 'Looking up the open reviews must not change the entries in review');
        AssertBuckets('E2', 0, 1, 0, 0, 0, 'Looking up the open reviews must not change the entries in review');
        AssertBuckets('E3', 0, 3, 0, 0, 0, 'Looking up the open reviews must not change the entries in review');
    end;

    [Test]
    procedure GetOpenReviews_ReturnsDraftAndSentButNotAnswered()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempOpenReview: Record "BCJ Customer Review" temporary;
        DraftReview: Record "BCJ Customer Review";
        SentReview: Record "BCJ Customer Review";
        AnsweredReview: Record "BCJ Customer Review";
        CustomerNo: Code[20];
        JobA: Code[20];
        JobB: Code[20];
        JobC: Code[20];
    begin
        // [SCENARIO] Contract: GetOpenReviews returns "the Draft and Sent reviews holding In Review
        // hours of the entries within the filters". A draft still has to be sent and a sent review
        // still has to be answered - both are open work. An answered review holds no hours in
        // review any more and is done.
        // [GIVEN] Three projects: one draft, one sent, one answered review
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobA := CreateProject('P1', CustomerNo);
        JobB := CreateProject('P2', CustomerNo);
        JobC := CreateProject('P3', CustomerNo);
        CreateTask(JobA, 'T1');
        CreateTask(JobB, 'T1');
        CreateTask(JobC, 'T1');
        AddEntry('A1', JobA, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('B1', JobB, 'T1', D(), 3, "BCJ Billing Status"::Open);
        AddEntry('C1', JobC, 'T1', D(), 4, "BCJ Billing Status"::Open);
        FilterOwnProjects(TimeEntry);
        TimeEntry.SetRange("Project No.", JobA);
        BCJTestLibrary.CreateDraftReview(TimeEntry, DraftReview);
        FilterOwnProjects(TimeEntry);
        TimeEntry.SetRange("Project No.", JobB);
        BCJTestLibrary.CreateDraftReview(TimeEntry, SentReview);
        BCJTestLibrary.SendDraftReview(SentReview);
        BCJTestLibrary.ReviewSingleEntry(JiraId('C1'), 4, 4, AnsweredReview);
        // [WHEN] The open reviews are requested for the whole customer
        FilterOwnProjects(TimeEntry);
        // [THEN] The draft and the sent review, not the answered one
        Assert.AreEqual(2, CustomerReviewMgt.GetOpenReviews(TimeEntry, TempOpenReview), 'The draft and the sent review must both count as open');
        AssertHoldsReview(TempOpenReview, DraftReview, 'The draft review must be in the result');
        AssertHoldsReview(TempOpenReview, SentReview, 'The sent review must be in the result');
        Assert.IsFalse(TempOpenReview.Get(AnsweredReview."Review No."), 'An answered review must be left out of the result');
    end;

    [Test]
    procedure GetOpenReviews_TwoProjectsGiveTwoReviews()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        TempOpenReview: Record "BCJ Customer Review" temporary;
        ReviewA: Record "BCJ Customer Review";
        ReviewB: Record "BCJ Customer Review";
        CustomerNo: Code[20];
        JobA: Code[20];
        JobB: Code[20];
        Found: Integer;
    begin
        // [SCENARIO] A selection over a customer can cover several projects, each with its own
        // review. Every one of them is still open, so every one must be listed. Project P2 is
        // deliberately put in review first, so its review has the lower number while its entries
        // sort after P1's: the result must not depend on which of the two is met first.
        // [GIVEN] Two projects of one customer, P2 put in review before P1
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobA := CreateProject('P1', CustomerNo);
        JobB := CreateProject('P2', CustomerNo);
        CreateTask(JobA, 'T1');
        CreateTask(JobB, 'T1');
        AddEntry('A1', JobA, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('A2', JobA, 'T1', D(), 1, "BCJ Billing Status"::Open);
        AddEntry('B1', JobB, 'T1', D(), 4, "BCJ Billing Status"::Open);
        FilterOwnProjects(TimeEntry);
        TimeEntry.SetRange("Project No.", JobB);
        CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        FilterOwnProjects(TimeEntry);
        TimeEntry.SetRange("Project No.", JobA);
        CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        GetReviewOfProject(JobA, ReviewA);
        GetReviewOfProject(JobB, ReviewB);
        Assert.IsTrue(ReviewB."Review No." < ReviewA."Review No.", 'Fixture: the review created first must have the lower Review No.');
        // [WHEN] The open reviews are requested for both projects
        FilterOwnProjects(TimeEntry);
        Found := CustomerReviewMgt.GetOpenReviews(TimeEntry, TempOpenReview);
        // [THEN] Both reviews, each once
        Assert.AreEqual(2, Found, 'Two projects with one open review each must give two open reviews');
        Assert.AreEqual(2, TempOpenReview.Count(), 'The result must hold exactly the two open reviews, each once');
        AssertHoldsReview(TempOpenReview, ReviewA, 'The open review of project P1 must be in the result');
        AssertHoldsReview(TempOpenReview, ReviewB, 'The open review of project P2 must be in the result');
    end;

    [Test]
    procedure GetOpenReviews_EntriesWithoutReviewGiveNone()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempOpenReview: Record "BCJ Customer Review" temporary;
        JobNo: Code[20];
    begin
        // [SCENARIO] Hours that were never put in a review have no review. The manual allocation
        // row (Review No. 0) is the absence of a review, not a review to look up - returning one
        // would hand the consultant a review that does not exist.
        // [GIVEN] Open and billable entries that were never in a review
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('E2', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Billable);
        // [WHEN] / [THEN] There is no open review
        FilterOwnProjects(TimeEntry);
        Assert.AreEqual(0, CustomerReviewMgt.GetOpenReviews(TimeEntry, TempOpenReview), 'Entries that belong to no review must count as no open review');
        Assert.IsTrue(TempOpenReview.IsEmpty(), 'Entries that belong to no review must leave the result empty');
    end;

    [Test]
    procedure GetOpenReviews_CancelledReviewGivesNone()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempOpenReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] A cancelled review has been taken back; it must not be offered, or the
        // customer is reminded about hours the consultant has withdrawn. The cancelled review
        // still has allocation rows for its worklogs, so the lookup must go by hours in review and
        // review status, not merely by the existence of a row.
        // [GIVEN] A sent review, then cancelled
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('E2', JobNo, 'T1', D() + 1, 3, "BCJ Billing Status"::Open);
        CreateSentReview(Review);
        CustomerReviewMgt.CancelReview(Review);
        // [WHEN] / [THEN] There is no open review
        FilterOwnProjects(TimeEntry);
        Assert.AreEqual(0, CustomerReviewMgt.GetOpenReviews(TimeEntry, TempOpenReview), 'A cancelled review must never count as open');
        Assert.IsTrue(TempOpenReview.IsEmpty(), 'A cancelled review must never be put into the result');
    end;

    [Test]
    procedure GetOpenReviews_AnsweredReviewGivesNone()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempOpenReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] Once the customer has answered there is nothing left to chase - even when the
        // answer approved only part of the hours and the worklog keeps a row for that review.
        // Offering it again would invite a second answer, which the review refuses.
        // [GIVEN] A review the customer has answered, approving 1 of 2 hours
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        BCJTestLibrary.ReviewSingleEntry(JiraId('E1'), 2, 1, Review);
        // [WHEN] / [THEN] There is no open review
        FilterOwnProjects(TimeEntry);
        Assert.AreEqual(0, CustomerReviewMgt.GetOpenReviews(TimeEntry, TempOpenReview), 'An answered review must never count as open');
        Assert.IsTrue(TempOpenReview.IsEmpty(), 'An answered review must never be put into the result');
    end;

    [Test]
    procedure GetOpenReviews_MixOfSentAndAnsweredGivesOnlySent()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        TempOpenReview: Record "BCJ Customer Review" temporary;
        ReviewA: Record "BCJ Customer Review";
        ReviewB: Record "BCJ Customer Review";
        CustomerNo: Code[20];
        JobA: Code[20];
        JobB: Code[20];
    begin
        // [SCENARIO] Across a customer some reviews come back and some do not. Only the ones still
        // out are worth a reminder; including an answered one would chase the customer for
        // something they have already done.
        // [GIVEN] Two projects sent together; the customer answers P1 but not P2
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobA := CreateProject('P1', CustomerNo);
        JobB := CreateProject('P2', CustomerNo);
        CreateTask(JobA, 'T1');
        CreateTask(JobB, 'T1');
        AddEntry('A1', JobA, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('B1', JobB, 'T1', D(), 4, "BCJ Billing Status"::Open);
        FilterOwnProjects(TimeEntry);
        CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        GetReviewOfProject(JobA, ReviewA);
        GetReviewOfProject(JobB, ReviewB);
        BCJTestLibrary.SendDraftReview(ReviewA);
        BCJTestLibrary.SendDraftReview(ReviewB);
        BCJTestLibrary.SetApprovedHours(ReviewA."Review No.", 'T1', 2);
        BCJTestLibrary.SubmitAnswer(ReviewA);
        // [WHEN] The open reviews are requested for the whole customer
        FilterOwnProjects(TimeEntry);
        // [THEN] Only the unanswered review
        Assert.AreEqual(1, CustomerReviewMgt.GetOpenReviews(TimeEntry, TempOpenReview), 'Only the review still waiting for an answer may count as open');
        Assert.AreEqual(1, TempOpenReview.Count(), 'Only the review still waiting for an answer may be in the result');
        AssertHoldsReview(TempOpenReview, ReviewB, 'The unanswered review of project P2 must be in the result');
        Assert.IsFalse(TempOpenReview.Get(ReviewA."Review No."), 'The answered review of project P1 must be left out of the result');
    end;

    [Test]
    procedure GetOpenReviews_HonoursCallerFilter()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        TempOpenReview: Record "BCJ Customer Review" temporary;
        ReviewA: Record "BCJ Customer Review";
        CustomerNo: Code[20];
        JobA: Code[20];
        JobB: Code[20];
    begin
        // [SCENARIO] The consultant asks about the worklogs they selected, not about every open
        // review. Another project's review would end up in a reminder to the wrong contact -
        // possibly exposing another project's hours to someone who should not see them.
        // [GIVEN] Two projects, each with an open review
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobA := CreateProject('P1', CustomerNo);
        JobB := CreateProject('P2', CustomerNo);
        CreateTask(JobA, 'T1');
        CreateTask(JobB, 'T1');
        AddEntry('A1', JobA, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('B1', JobB, 'T1', D(), 4, "BCJ Billing Status"::Open);
        FilterOwnProjects(TimeEntry);
        CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        GetReviewOfProject(JobA, ReviewA);
        // [WHEN] The open reviews are requested for project P1 only
        FilterOwnProjects(TimeEntry);
        TimeEntry.SetRange("Project No.", JobA);
        // [THEN] Only P1's review
        Assert.AreEqual(1, CustomerReviewMgt.GetOpenReviews(TimeEntry, TempOpenReview), 'Only reviews of entries inside the caller filter may count as open');
        Assert.AreEqual(1, TempOpenReview.Count(), 'Only reviews of entries inside the caller filter may be in the result');
        AssertHoldsReview(TempOpenReview, ReviewA, 'The open review of the filtered project P1 must be in the result');
    end;

    [Test]
    procedure GetOpenReviews_NoMatchWithBlankBaseUrlGivesNoneWithoutError()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempOpenReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] The lookup is offered on the overview whether or not reviews are in use, and
        // a company that never configured the review web app has no base URL. Asking about hours
        // that have no open review must then answer "none", not fail on setup the answer does not
        // need.
        // [GIVEN] Entries without a review, and entries whose review was cancelled
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        CustomerReviewMgt.CancelReview(Review);
        AddEntry('E2', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        // [GIVEN] The review base URL is then cleared
        BCJTestLibrary.EnsureSetup('');
        // [WHEN] / [THEN] No open review and no error
        FilterOwnProjects(TimeEntry);
        Assert.AreEqual(0, CustomerReviewMgt.GetOpenReviews(TimeEntry, TempOpenReview), 'With no open review in the filter the result must be 0, and a blank review base URL must not cause an error');
        Assert.IsTrue(TempOpenReview.IsEmpty(), 'With no open review in the filter the result must be empty');
    end;

    [Test]
    procedure GetOpenReviews_SentReviewWithBlankBaseUrlIsStillReturned()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempOpenReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] Finding which reviews are open is a question about data, not about the web
        // app. Clearing the base URL (setup changed, web app moved) must not hide or break the list
        // of reviews the customer still owes an answer on.
        // [GIVEN] A sent review, after which the review base URL is cleared
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        CreateSentReview(Review);
        BCJTestLibrary.EnsureSetup('');
        // [WHEN] The open reviews are requested
        FilterOwnProjects(TimeEntry);
        // [THEN] The sent review is returned without error
        Assert.AreEqual(1, CustomerReviewMgt.GetOpenReviews(TimeEntry, TempOpenReview), 'A sent review must still count as open when the review base URL is blank');
        AssertHoldsReview(TempOpenReview, Review, 'A sent review must still be in the result when the review base URL is blank');
    end;

    [Test]
    procedure GetOpenReviews_ClearsPrefilledResultFirst()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempOpenReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] Callers reuse one temporary buffer across selections. A row left over from an
        // earlier call would put a review into the reminder that is not in the current selection -
        // the same wrong-contact exposure the caller filter guards against - so the buffer must be
        // emptied before it is filled.
        // [GIVEN] An open review, and a result buffer already holding an unrelated review 999999
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        TempOpenReview.Init();
        TempOpenReview."Review No." := 999999;
        TempOpenReview."Project No." := 'LEFTOVER';
        TempOpenReview.Insert(false);
        // [WHEN] The open reviews are requested
        FilterOwnProjects(TimeEntry);
        // [THEN] Only the real open review remains
        Assert.AreEqual(1, CustomerReviewMgt.GetOpenReviews(TimeEntry, TempOpenReview), 'The count must cover only the reviews found in this call');
        TempOpenReview.Reset();
        Assert.IsFalse(TempOpenReview.Get(999999), 'A row that was in the buffer before the call must be gone afterwards');
        Assert.AreEqual(1, TempOpenReview.Count(), 'After the call the buffer must hold only the reviews found in this call');
        AssertHoldsReview(TempOpenReview, Review, 'The open review must be in the result');
    end;

    local procedure AssertHoldsReview(var TempOpenReview: Record "BCJ Customer Review" temporary; Review: Record "BCJ Customer Review"; Msg: Text)
    begin
        Assert.IsTrue(TempOpenReview.Get(Review."Review No."), Msg);
        Assert.AreEqual(Review."Project No.", TempOpenReview."Project No.", Msg + ' (Project No. must match the real review)');
    end;

    // ---------------------------------------------------------------------------------
    // Hours to Bill - what the consultant asks the customer to approve (Draft only)
    // ---------------------------------------------------------------------------------

    [Test]
    procedure CreateReviews_HoursToBillDefaultsToLoggedHours()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] Until the consultant decides otherwise, the customer is asked to approve
        // everything reserved - asking for less by default would silently give hours away,
        // asking for more would invent them. The default must be the line's Logged Hours after
        // its 0.01 rounding, not the raw sum: the customer sees two decimals, and Approved Hours
        // is capped by Hours to Bill, so a raw 0.3333 cap would let the customer approve more
        // than the 0.33 they were shown.
        // [GIVEN] Two tasks, one of which holds a third of an hour
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        CreateTask(JobNo, 'T2');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('E2', JobNo, 'T1', D() + 1, 1.5, "BCJ Billing Status"::Open);
        AddEntry('E3', JobNo, 'T2', D(), 1 / 3, "BCJ Billing Status"::Open);
        // [WHEN] The project is put in review
        CreateOneReview(Review);
        // [THEN] Every line asks for exactly its logged hours
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(3.5, ReviewLine."Hours to Bill", 'A new line must ask the customer to approve all of its reserved hours');
        Assert.AreEqual(ReviewLine."Logged Hours", ReviewLine."Hours to Bill", 'A new line must ask for exactly its Logged Hours');
        ReviewLine.Get(Review."Review No.", 'T2');
        Assert.AreEqual(0.33, ReviewLine."Logged Hours", 'Fixture: Logged Hours must be rounded to 0.01');
        Assert.AreEqual(0.33, ReviewLine."Hours to Bill", 'Hours to Bill must default to the rounded Logged Hours the customer is shown, not the raw entry sum');
        // [THEN] The review header totals what is asked of the customer
        Review.CalcFields("Hours to Bill");
        Assert.AreEqual(3.83, Review."Hours to Bill", 'The review Hours to Bill must be the sum of its lines Hours to Bill');
    end;

    [Test]
    procedure CreateReviews_TaskSnapshotCoversWholeTaskHistory()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        CustomerNo: Code[20];
        JobNo: Code[20];
        OtherJobNo: Code[20];
    begin
        // [SCENARIO] The customer judges a task by its whole history, not by this period's slice.
        // Contract task snapshot (over all worklogs of the task): Billed = Billed + Billable
        // (charged or agreed to be charged), Not Billable = Not Billable, Not Billed = Open +
        // In Review (nobody has decided yet, including this review), Logged = sum of logged hours.
        // Another task or project is another agreement and must never leak into the numbers.
        // [GIVEN] Task T1: billed 4 h, billable 2 h, written off 1.5 h, open 0.75 h outside the
        // period, and 2.5 + 1.25 h open in the period
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobNo := CreateProject('P1', CustomerNo);
        OtherJobNo := CreateProject('P2', CustomerNo);
        CreateTask(JobNo, 'T1');
        CreateTask(JobNo, 'T2');
        CreateTask(OtherJobNo, 'T1');
        AddEntry('BILLED', JobNo, 'T1', D() - 30, 4, "BCJ Billing Status"::Billed);
        AddEntry('BILLABLE', JobNo, 'T1', D() - 20, 2, "BCJ Billing Status"::Billable);
        AddEntry('NOTBILL', JobNo, 'T1', D() - 10, 1.5, "BCJ Billing Status"::"Not Billable");
        AddEntry('LATER', JobNo, 'T1', D() + 40, 0.75, "BCJ Billing Status"::Open);
        AddEntry('R1', JobNo, 'T1', D(), 2.5, "BCJ Billing Status"::Open);
        AddEntry('R2', JobNo, 'T1', D() + 1, 1.25, "BCJ Billing Status"::Open);
        // [GIVEN] Decided hours on another task of the same project and on the same task no. of another project
        AddEntry('OTHERTASK', JobNo, 'T2', D() - 5, 7, "BCJ Billing Status"::Billed);
        AddEntry('OTHERPROJ', OtherJobNo, 'T1', D() - 5, 9, "BCJ Billing Status"::Billable);
        // [WHEN] Only project P1 in the current period is put in review
        FilterOwnProjects(TimeEntry);
        TimeEntry.SetRange("Project No.", JobNo);
        TimeEntry.SetRange("Posting Date", D(), D() + 1);
        Assert.AreEqual(1, CustomerReviewMgt.CreateReviews(TimeEntry, TempReview), 'Fixture: the period of project P1 must produce exactly one review');
        TempReview.FindFirst();
        Review.Get(TempReview."Review No.");
        // [THEN] The line holds only this period's hours, but the snapshot holds the whole task
        ReviewLine.SetRange("Review No.", Review."Review No.");
        Assert.AreEqual(1, ReviewLine.Count(), 'Fixture: only task T1 had open hours in the period, so only T1 may get a line');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(3.75, ReviewLine."Logged Hours", 'Fixture: the line must hold only the two entries inside the period');
        Assert.AreEqual(3.75, ReviewLine."Hours to Bill", 'Hours to Bill must default to the hours reserved, not to the task history');
        // Logged 12 = Billed 4 + Billable 2 (6) + Not Billable 1.5 + Open 0.75 + In Review 3.75 (4.5)
        AssertTaskSnapshot(ReviewLine, 12, 6, 1.5, 4.5, 'Task T1 with billed, billable, written-off, later open and reserved hours');
    end;

    [Test]
    procedure ReviewLine_HoursToBillOutsideRangeIsRejected()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] The consultant may ask the customer to approve less than was reserved - never
        // more, because that would bill hours nobody worked, and never less than nothing. Anything
        // between 0 and the reserved hours is a legitimate commercial decision and is accepted.
        // [GIVEN] A draft review line with 3 reserved hours
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        ReviewLine.Get(Review."Review No.", 'T1');
        // [WHEN] More hours than reserved are asked for
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror ReviewLine.Validate("Hours to Bill", 3.01);
        // [THEN] Refused and the stored value is unchanged
        Assert.ExpectedErrorCode('Dialog');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(3.0, ReviewLine."Hours to Bill", 'Asking for more hours than were reserved must leave Hours to Bill unchanged');
        // [WHEN] A negative number of hours is asked for
        // (The field minimum may catch this before the range check does, so only the state is asserted.)
        asserterror ReviewLine.Validate("Hours to Bill", -1);
        // [THEN] Refused and the stored value is still unchanged
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(3.0, ReviewLine."Hours to Bill", 'Asking for a negative number of hours must leave Hours to Bill unchanged');
        // [WHEN] Values inside the range are asked for, including both bounds
        BCJTestLibrary.SetHoursToBill(Review."Review No.", 'T1', 0);
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(0.0, ReviewLine."Hours to Bill", 'Zero hours to bill must be accepted - the consultant may ask for nothing');
        BCJTestLibrary.SetHoursToBill(Review."Review No.", 'T1', 3);
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(3.0, ReviewLine."Hours to Bill", 'Hours to bill equal to the reserved hours must be accepted');
        BCJTestLibrary.SetHoursToBill(Review."Review No.", 'T1', 1.5);
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(1.5, ReviewLine."Hours to Bill", 'Hours to bill between 0 and the reserved hours must be accepted and stored');
    end;

    [Test]
    procedure ReviewLine_HoursToBillCanOnlyChangeInDraft()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] Business flow step 4: "A sent review is frozen: no Hours to Bill changes".
        // The customer has been shown what they are asked to approve; changing the question under
        // them would make their answer refer to figures they never saw, and the hours cut on Send
        // are already back in Open.
        // [GIVEN] A review over 4 h, sent asking for 3
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 4, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        BCJTestLibrary.SetHoursToBill(Review."Review No.", 'T1', 3);
        BCJTestLibrary.SendDraftReview(Review);
        // [WHEN] Hours to Bill is changed on the sent review
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror BCJTestLibrary.SetHoursToBill(Review."Review No.", 'T1', 2);
        // [THEN] Refused; the line and the hours are unchanged
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(3.0, ReviewLine."Hours to Bill", 'Hours to Bill of a sent review must not change');
        AssertBuckets('E1', 1, 3, 0, 0, 0, 'A refused change must not move any hour');
    end;

    [Test]
    procedure ReviewLine_ApprovedHoursCanOnlyChangeWhenSent()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] Contract, table 50104: "Approved Hours only while Sent". On a draft nobody
        // has been asked anything yet - an approval there would be an answer to a question the
        // consultant is still writing.
        // [GIVEN] A draft review
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        // [WHEN] An approval is entered on the draft
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror BCJTestLibrary.SetApprovedHours(Review."Review No.", 'T1', 2);
        // [THEN] Refused
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(0.0, ReviewLine."Approved Hours", 'An approval must not be stored on a draft review');
        // [WHEN] The review is sent and the approval entered
        BCJTestLibrary.SendDraftReview(Review);
        BCJTestLibrary.SetApprovedHours(Review."Review No.", 'T1', 2);
        // [THEN] Accepted
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(2.0, ReviewLine."Approved Hours", 'An approval on a sent review must be stored');
    end;

    [Test]
    procedure ReviewLine_ApprovedHoursAboveHoursToBillIsRejected()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] Once the consultant has asked for fewer hours than were logged, the request -
        // not the logged time - is the ceiling of the approval. A customer who could approve up to
        // the logged hours would be approving hours the consultant chose not to charge.
        // [GIVEN] A line of 3 logged hours sent asking for 2
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        BCJTestLibrary.SetHoursToBill(Review."Review No.", 'T1', 2);
        BCJTestLibrary.SendDraftReview(Review);
        ReviewLine.Get(Review."Review No.", 'T1');
        // [WHEN] 2.5 hours are approved - within the logged hours but above the request
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror ReviewLine.Validate("Approved Hours", 2.5);
        // [THEN] Refused and the stored approval is unchanged
        Assert.ExpectedErrorCode('Dialog');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(0.0, ReviewLine."Approved Hours", 'Approving more than Hours to Bill must be refused even when it is within the logged hours');
        // [WHEN] Exactly the requested hours are approved
        BCJTestLibrary.SetApprovedHours(Review."Review No.", 'T1', 2);
        // [THEN] Accepted
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(2.0, ReviewLine."Approved Hours", 'Approving exactly the Hours to Bill must be accepted');
    end;

    [Test]
    procedure SubmitReview_ApprovedAboveHoursToBillWrittenDirectlyIsRejected()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] Field validation can be bypassed - an API or a direct write stores the value
        // without it. The submit is the last door before hours become Billable, so it checks the
        // approval against what was asked for once more (0 <= Approved <= Hours to Bill). Letting
        // it through would bill hours the consultant chose not to charge.
        // [GIVEN] E1 1 h and E2 2 h sent asking for 2 (E2 keeps 1 in review), 2.5 approved written directly
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 1, "BCJ Billing Status"::Open);
        AddEntry('E2', JobNo, 'T1', D() + 1, 2, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        BCJTestLibrary.SetHoursToBill(Review."Review No.", 'T1', 2);
        BCJTestLibrary.SendDraftReview(Review);
        ReviewLine.Get(Review."Review No.", 'T1');
        ReviewLine."Approved Hours" := 2.5;
        ReviewLine.Modify(false);
        // [WHEN] The review is submitted
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror CustomerReviewMgt.SubmitReview(Review);
        // [THEN] Refused; the review is still out and no hour was decided
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Sent, Review.Status, 'A review with an approval above Hours to Bill must not be answered');
        Assert.AreEqual(0DT, Review."Answered On", 'A refused submit must not stamp an answer time');
        AssertBuckets('E1', 0, 1, 0, 0, 0, 'A refused submit must leave the hours in review');
        AssertBuckets('E2', 1, 1, 0, 0, 0, 'A refused submit must leave the hours in review');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(0.0, ReviewLine."Applied Hours", 'A refused submit must apply nothing');
    end;

    [Test]
    procedure SetHoursToBillPct_FiftyPercentEndToEnd()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] The business case the feature exists for: the consultant logged 10 hours but
        // will only charge half. They set 50% on the draft, send it (the cut 5 hours return to
        // Open, off the newest worklog first), the customer approves 5, and the 5 hours land on
        // the oldest worklog - which ends up 5 Billable + 1 Open, the newer worklog 4 Open.
        // [GIVEN] A draft over 6 h (older) and 4 h (newer)
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('OLD', JobNo, 'T1', D(), 6, "BCJ Billing Status"::Open);
        AddEntry('NEW', JobNo, 'T1', D() + 1, 4, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        // [WHEN] The consultant asks for 50%
        CustomerReviewMgt.SetHoursToBillPct(Review, 50);
        // [THEN] The line asks for 5 hours
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(10.0, ReviewLine."Logged Hours", 'Setting a percentage must not change the reserved hours');
        Assert.AreEqual(5.0, ReviewLine."Hours to Bill", '50% of 10 reserved hours must ask the customer for 5 hours');
        Review.Get(Review."Review No.");
        Review.CalcFields("Hours to Bill");
        Assert.AreEqual(5.0, Review."Hours to Bill", 'The review must total the hours asked for');
        // [WHEN] It is sent, the customer approves the 5 hours and submits
        BCJTestLibrary.SendDraftReview(Review);
        BCJTestLibrary.SetApprovedHours(Review."Review No.", 'T1', 5);
        BCJTestLibrary.SubmitAnswer(Review);
        // [THEN] The older worklog is billable for 5, the rest is Open
        Assert.AreEqual("BCJ Review Status"::Answered, Review.Status, 'A review approved within its Hours to Bill must be answered');
        AssertBuckets('OLD', 1, 0, 5, 0, 0, 'The oldest worklog must carry the approved hours first');
        AssertBuckets('NEW', 4, 0, 0, 0, 0, 'The worklog left with no approved hours must be Open, not written off');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(5.0, ReviewLine."Applied Hours", 'All 5 approved hours must be applied');
        AssertOwnInvariant('After a 50% review');
    end;

    [Test]
    procedure SetHoursToBillPct_RoundsAndTouchesOnlyItsOwnReview()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        OtherReview: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        CustomerNo: Code[20];
        JobNo: Code[20];
        OtherJobNo: Code[20];
    begin
        // [SCENARIO] The customer is shown two decimals, so the percentage result is rounded to
        // 0.01 the ordinary way (0.625 -> 0.63): truncating would shave a fraction off every task
        // in the firm's disfavour. The percentage applies to the one review it was called for -
        // another project's review has its own agreement.
        // [GIVEN] Draft of P1: T1 1.25 h, T2 4 h; and a separate draft of P2 with 2 h
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobNo := CreateProject('P1', CustomerNo);
        OtherJobNo := CreateProject('P2', CustomerNo);
        CreateTask(JobNo, 'T1');
        CreateTask(JobNo, 'T2');
        CreateTask(OtherJobNo, 'T1');
        AddEntry('A1', JobNo, 'T1', D(), 1.25, "BCJ Billing Status"::Open);
        AddEntry('A2', JobNo, 'T2', D(), 4, "BCJ Billing Status"::Open);
        AddEntry('B1', OtherJobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        FilterOwnProjects(TimeEntry);
        CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        GetReviewOfProject(JobNo, Review);
        GetReviewOfProject(OtherJobNo, OtherReview);
        // [WHEN] 50% is set on the P1 review
        CustomerReviewMgt.SetHoursToBillPct(Review, 50);
        // [THEN] T1 asks for 0.63, T2 for 2, the other review is untouched
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(0.63, ReviewLine."Hours to Bill", '50% of 1.25 hours must be rounded to 0.63, the standard way');
        ReviewLine.Get(Review."Review No.", 'T2');
        Assert.AreEqual(2.0, ReviewLine."Hours to Bill", '50% of 4 hours must ask for 2 hours');
        ReviewLine.Get(OtherReview."Review No.", 'T1');
        Assert.AreEqual(2.0, ReviewLine."Hours to Bill", 'Setting a percentage on one review must not change the lines of another review');
    end;

    [Test]
    procedure SetHoursToBillPct_ZeroAndHundredAreAccepted()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] 0% (a goodwill task, charge nothing) and 100% (undo an earlier cut) are both
        // everyday choices on a draft. Nothing is released while it is a draft, so 100% after 0%
        // must restore the request to exactly the reserved hours.
        // [GIVEN] A draft line of 3 reserved hours
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        // [WHEN] 0% is set
        CustomerReviewMgt.SetHoursToBillPct(Review, 0);
        // [THEN] Nothing is asked for
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(0.0, ReviewLine."Hours to Bill", '0% must ask the customer for no hours');
        // [WHEN] 100% is set
        Review.Get(Review."Review No.");
        CustomerReviewMgt.SetHoursToBillPct(Review, 100);
        // [THEN] The full reserved hours are asked for again
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(3.0, ReviewLine."Hours to Bill", '100% must ask for exactly the reserved hours');
        AssertBuckets('E1', 0, 3, 0, 0, 0, 'Changing the percentage on a draft must not move any hour');
    end;

    [Test]
    procedure SetHoursToBillPct_OutOfRangeIsRejected()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] More than 100% would bill hours nobody worked; a negative percentage is
        // meaningless. Either is a typo and must be refused before any line is touched - a
        // half-applied percentage would leave the review asking for a mix of old and new figures.
        // [GIVEN] A draft over two tasks, one of them already lowered
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        CreateTask(JobNo, 'T2');
        AddEntry('E1', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        AddEntry('E2', JobNo, 'T2', D(), 2, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        BCJTestLibrary.SetHoursToBill(Review."Review No.", 'T1', 2.5);
        // [WHEN] 150% is set
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        Review.Get(Review."Review No.");
        asserterror CustomerReviewMgt.SetHoursToBillPct(Review, 150);
        // [THEN] Refused and no line changed
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(2.5, ReviewLine."Hours to Bill", 'A refused percentage above 100 must leave Hours to Bill unchanged');
        ReviewLine.Get(Review."Review No.", 'T2');
        Assert.AreEqual(2.0, ReviewLine."Hours to Bill", 'A refused percentage above 100 must leave every line unchanged');
        // [WHEN] -1% is set
        Review.Get(Review."Review No.");
        asserterror CustomerReviewMgt.SetHoursToBillPct(Review, -1);
        // [THEN] Refused and no line changed
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(2.5, ReviewLine."Hours to Bill", 'A refused negative percentage must leave Hours to Bill unchanged');
        ReviewLine.Get(Review."Review No.", 'T2');
        Assert.AreEqual(2.0, ReviewLine."Hours to Bill", 'A refused negative percentage must leave every line unchanged');
    end;

    [Test]
    procedure SetHoursToBillPct_OnSentReviewIsRejected()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] Contract: "SetHoursToBillPct: Draft only". A sent review is frozen - the
        // customer is looking at its figures, and the hours cut on Send are already Open.
        // [GIVEN] A review over 4 h sent asking for all 4
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 4, "BCJ Billing Status"::Open);
        CreateSentReview(Review);
        // [WHEN] A percentage is set
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror CustomerReviewMgt.SetHoursToBillPct(Review, 50);
        // [THEN] Refused and nothing changed
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(4.0, ReviewLine."Hours to Bill", 'A sent review must keep the Hours to Bill it was sent with');
        AssertBuckets('E1', 0, 4, 0, 0, 0, 'A refused percentage must not move any hour');
    end;

    [Test]
    procedure SetHoursToBillPct_OnAnsweredReviewIsRejected()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] Once the customer has answered, the lines are the record of what was asked
        // and agreed, and the allocation has been made on the strength of it. Changing what was
        // asked afterwards would rewrite the question under the customer's answer.
        // [GIVEN] An answered review
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 4, "BCJ Billing Status"::Open);
        BCJTestLibrary.ReviewSingleEntry(JiraId('E1'), 4, 4, Review);
        // [WHEN] A percentage is set
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror CustomerReviewMgt.SetHoursToBillPct(Review, 50);
        // [THEN] Refused and nothing changed
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(4.0, ReviewLine."Hours to Bill", 'An answered review must keep the Hours to Bill the customer answered');
        Assert.AreEqual(4.0, ReviewLine."Approved Hours", 'An answered review must keep the approval the customer gave');
        AssertBuckets('E1', 0, 0, 4, 0, 0, 'A refused percentage must not change the applied allocation');
    end;

    [Test]
    procedure SetHoursToBillPct_OnCancelledReviewIsRejected()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] A cancelled review has been taken back and its hours released; it will never
        // be answered. Changing what it asks for is pointless and would make the historic record
        // disagree with what was actually prepared.
        // [GIVEN] A cancelled review
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 4, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        CustomerReviewMgt.CancelReview(Review);
        Review.Get(Review."Review No.");
        // [WHEN] A percentage is set
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror CustomerReviewMgt.SetHoursToBillPct(Review, 50);
        // [THEN] Refused and nothing changed
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(4.0, ReviewLine."Hours to Bill", 'A cancelled review must keep the Hours to Bill it had');
        AssertBuckets('E1', 4, 0, 0, 0, 0, 'A refused percentage must not touch the released hours');
    end;

    local procedure AssertTaskSnapshot(ReviewLine: Record "BCJ Customer Review Line"; Logged: Decimal; Billed: Decimal; NotBillable: Decimal; NotBilled: Decimal; LineName: Text)
    begin
        Assert.AreEqual(Logged, ReviewLine."Task Logged Hours", LineName + ': Task Logged Hours must be every hour ever logged on the task, whatever the selection');
        Assert.AreEqual(Billed, ReviewLine."Task Billed Hours", LineName + ': Task Billed Hours must be the Billed plus Billable hours of the task');
        Assert.AreEqual(NotBillable, ReviewLine."Task Not Billable Hours", LineName + ': Task Not Billable Hours must be the written-off hours of the task');
        Assert.AreEqual(NotBilled, ReviewLine."Task Not Billed Hours", LineName + ': Task Not Billed Hours must be the Open plus In Review hours of the task');
    end;

    // ---------------------------------------------------------------------------------
    // Fixtures
    // ---------------------------------------------------------------------------------

    local procedure Initialize()
    begin
        // Run on every test, never guarded by a "done" flag: the runner rolls the database back
        // but not codeunit variables, so a flag would leave a later test with no setup at all.
        Stem := BCJTestLibrary.NewStem();
        BCJTestLibrary.EnsureSetup('https://review.example.com');
    end;

    local procedure D(): Date
    begin
        exit(BCJTestLibrary.BaseDate());
    end;

    local procedure JiraId(Suffix: Text): Text[50]
    begin
        exit(CopyStr(Stem + '-' + Suffix, 1, 50));
    end;

    local procedure CreateCustomer(Suffix: Text) CustomerNo: Code[20]
    begin
        CustomerNo := CopyStr(Stem + Suffix, 1, 20);
        BCJTestLibrary.CreateCustomer(CustomerNo, CopyStr('Customer ' + CustomerNo, 1, 100));
    end;

    local procedure CreateProject(Suffix: Text; CustomerNo: Code[20]) JobNo: Code[20]
    begin
        JobNo := CopyStr(Stem + Suffix, 1, 20);
        BCJTestLibrary.CreateJob(JobNo, CustomerNo, CopyStr('Project ' + JobNo, 1, 100));
    end;

    local procedure CreateTask(JobNo: Code[20]; TaskNo: Code[20])
    begin
        BCJTestLibrary.CreateJobTask(JobNo, TaskNo, CopyStr('Task ' + TaskNo + ' of ' + JobNo, 1, 100), 'IN PROGRESS');
    end;

    local procedure CreateSingleTaskProjectWithOpenEntry(Suffix: Text; Hours: Decimal): Code[20]
    var
        JobNo: Code[20];
    begin
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry(Suffix, JobNo, 'T1', D(), Hours, "BCJ Billing Status"::Open);
        exit(JobNo);
    end;

    local procedure AddEntry(Suffix: Text; JobNo: Code[20]; TaskNo: Code[20]; PostingDate: Date; Hours: Decimal; Status: Enum "BCJ Billing Status")
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        BCJTestLibrary.CreateTimeEntry(TimeEntry, JiraId(Suffix), JobNo, TaskNo, Stem, PostingDate, Hours, Status);
    end;

    local procedure FilterOwnProjects(var TimeEntry: Record "BCJ Project Time Entry")
    begin
        // Everything this test created shares the stem, so real synced Jira data in the sandbox
        // can never enter a selection.
        TimeEntry.Reset();
        TimeEntry.SetFilter("Project No.", Stem + '*');
    end;

    local procedure CreateOneReview(var Review: Record "BCJ Customer Review")
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // A Draft review over every Open hour of this test's projects.
        FilterOwnProjects(TimeEntry);
        BCJTestLibrary.CreateDraftReview(TimeEntry, Review);
    end;

    local procedure CreateSentReview(var Review: Record "BCJ Customer Review")
    begin
        // A review over every Open hour of this test's projects, sent unchanged (Hours to Bill =
        // hours reserved, so Send releases nothing).
        CreateOneReview(Review);
        BCJTestLibrary.SendDraftReview(Review);
    end;

    local procedure GetReviewOfProject(JobNo: Code[20]; var Review: Record "BCJ Customer Review")
    begin
        Review.Reset();
        Review.SetRange("Project No.", JobNo);
        Assert.AreEqual(1, Review.Count(), StrSubstNo('Exactly one review must exist for project %1', JobNo));
        Review.FindFirst();
    end;

    local procedure ApproveAllHoursToBill(ReviewNo: Integer)
    var
        ReviewLine: Record "BCJ Customer Review Line";
    begin
        ReviewLine.SetRange("Review No.", ReviewNo);
        ReviewLine.FindSet();
        repeat
            ReviewLine.Validate("Approved Hours", ReviewLine."Hours to Bill");
            ReviewLine.Modify(true);
        until ReviewLine.Next() = 0;
    end;

    local procedure GetEntry(Suffix: Text; var TimeEntry: Record "BCJ Project Time Entry")
    begin
        TimeEntry.Get(JiraId(Suffix), CopyStr('I-' + JiraId(Suffix), 1, 50));
    end;

    local procedure TaskDescription(JobNo: Code[20]; TaskNo: Code[20]): Text[100]
    var
        JobTask: Record "Job Task";
    begin
        JobTask.Get(JobNo, TaskNo);
        exit(JobTask.Description);
    end;

    // ---------------------------------------------------------------------------------
    // Assertion helpers
    // ---------------------------------------------------------------------------------

    local procedure AssertBuckets(Suffix: Text; OpenHours: Decimal; InReviewHours: Decimal; BillableHours: Decimal; NotBillableHours: Decimal; BilledHours: Decimal; Msg: Text)
    begin
        BCJTestLibrary.AssertBuckets(JiraId(Suffix), OpenHours, InReviewHours, BillableHours, NotBillableHours, BilledHours, Msg);
    end;

    local procedure AssertStatus(Suffix: Text; ExpectedStatus: Enum "BCJ Billing Status"; Msg: Text)
    begin
        BCJTestLibrary.AssertStatus(JiraId(Suffix), ExpectedStatus, Msg);
    end;

    local procedure AssertOwnInvariant(Context: Text)
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        FilterOwnProjects(TimeEntry);
        BCJTestLibrary.AssertInvariant(TimeEntry, Context);
    end;

    local procedure AssertHours(Buffer: Record "BCJ Billing Overview Buffer" temporary; Total: Decimal; OpenHours: Decimal; SentForReview: Decimal; Billable: Decimal; NotBillable: Decimal; Billed: Decimal; Unbilled: Decimal; LineName: Text)
    begin
        Assert.AreEqual(Total, Buffer."Total Hours", LineName + ': Total Hours must equal every logged hour beneath it');
        Assert.AreEqual(OpenHours, Buffer."Open Hours", LineName + ': Open Hours must equal the hours nobody has decided on yet');
        Assert.AreEqual(SentForReview, Buffer."Sent for Review Hours", LineName + ': Sent for Review Hours must equal the hours in review');
        Assert.AreEqual(Billable, Buffer."Billable Hours", LineName + ': Billable Hours must equal the hours approved for invoicing and not yet invoiced');
        Assert.AreEqual(NotBillable, Buffer."Not Billable Hours", LineName + ': Not Billable Hours must equal the hours written off');
        Assert.AreEqual(Billed, Buffer."Billed Hours", LineName + ': Billed Hours must equal the hours already invoiced');
        Assert.AreEqual(Unbilled, Buffer."Unbilled Hours", LineName + ': Unbilled Hours must equal Open + Sent for Review + Billable');
    end;

    local procedure FindLine(var Buffer: Record "BCJ Billing Overview Buffer" temporary; ExpectedLineType: Enum "BCJ Overview Line Type"; CustomerNo: Code[20]; ProjectNo: Code[20]; TaskNo: Code[20])
    begin
        Buffer.Reset();
        Buffer.SetRange("Line Type", ExpectedLineType);
        Buffer.SetRange("Customer No.", CustomerNo);
        if ExpectedLineType <> LineType::Customer then
            Buffer.SetRange("Project No.", ProjectNo);
        if ExpectedLineType = LineType::Task then
            Buffer.SetRange("Project Task No.", TaskNo);
        Assert.AreEqual(1, Buffer.Count(), StrSubstNo('Exactly one %1 line must exist for %2 %3 %4', ExpectedLineType, CustomerNo, ProjectNo, TaskNo));
        Buffer.FindFirst();
    end;

    local procedure ContainsHours(Body: Text; Hours: Decimal): Boolean
    begin
        // The hours figure must be in the body, but its decimal separator depends on the
        // environment language, so both the session format and the invariant one are accepted.
        // Every value checked this way has a decimal part, which no access token can contain.
        exit((StrPos(Body, Format(Hours)) > 0) or (StrPos(Body, Format(Hours, 0, 9)) > 0));
    end;
}
