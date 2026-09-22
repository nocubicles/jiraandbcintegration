codeunit 50154 "BCJ Customer Review Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    // Customer time review: the consultant sends a project's open hours to the customer, the
    // customer approves a number of hours per task, and the approved hours are allocated back
    // onto the individual worklog entries. Money changes hands on the result, so every number
    // asserted here is a business decision recorded in tasks/customer-review-contract.md, not an
    // implementation detail.
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
    // CreateReviews
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
        // [SCENARIO] The customer is asked to approve a project, not a worklog: one mail per
        // project, and inside it one row per task - a customer cannot judge individual Jira
        // worklogs but does recognise the task they ordered. The hours shown per task must be
        // the sum of the hours actually sent, and each entry sent must be parked in
        // "Sent for Review" so it can no longer be invoiced or re-sent while the customer decides.
        // [GIVEN] One project with two tasks and three open entries
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobNo := CreateProject('P1', CustomerNo);
        CreateTask(JobNo, 'T1');
        CreateTask(JobNo, 'T2');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('E2', JobNo, 'T1', D() + 1, 1, "BCJ Billing Status"::Open);
        AddEntry('E3', JobNo, 'T2', D(), 3, "BCJ Billing Status"::Open);
        // [WHEN] The whole project is sent for review
        FilterOwnProjects(TimeEntry);
        Created := CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        // [THEN] Exactly one review, one line per task, hours summed per task
        Assert.AreEqual(1, Created, 'Open entries of one project must produce exactly one review, not one per task or per entry');
        Assert.AreEqual(1, TempReview.Count(), 'The returned temporary buffer must hold one header per review created');
        TempReview.FindFirst();
        Review.Get(TempReview."Review No.");
        Assert.AreEqual("BCJ Review Status"::Sent, Review.Status, 'A newly created review must be Sent, waiting for the customer');
        Assert.AreEqual(JobNo, Review."Project No.", 'The review must belong to the project its entries came from');
        Assert.AreEqual(CustomerNo, Review."Customer No.", 'The review must snapshot the project Bill-to customer, so a later change of Bill-to does not rewrite history');
        ReviewLine.SetRange("Review No.", Review."Review No.");
        Assert.AreEqual(2, ReviewLine.Count(), 'A review must have exactly one line per task that had entries sent');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(3.0, ReviewLine."Logged Hours", 'Task T1 must show the sum of the hours of both entries sent for it');
        Assert.AreEqual(2, ReviewLine."Entry Count", 'Task T1 must record that two entries were sent');
        Assert.AreEqual(TaskDescription(JobNo, 'T1'), ReviewLine."Task Description", 'The line must carry the task description the customer recognises');
        ReviewLine.Get(Review."Review No.", 'T2');
        Assert.AreEqual(3.0, ReviewLine."Logged Hours", 'Task T2 must show the hours of the single entry sent for it');
        Assert.AreEqual(1, ReviewLine."Entry Count", 'Task T2 must record that one entry was sent');
        // [THEN] Every entry sent is parked in the review with its full hours still allocated
        AssertEntry('E1', "BCJ Billing Status"::"Sent for Review", 2, Review."Review No.", 'Entry E1 must be parked in the review with its logged hours still fully allocated');
        AssertEntry('E2', "BCJ Billing Status"::"Sent for Review", 1, Review."Review No.", 'Entry E2 must be parked in the review with its logged hours still fully allocated');
        AssertEntry('E3', "BCJ Billing Status"::"Sent for Review", 3, Review."Review No.", 'Entry E3 must be parked in the review with its logged hours still fully allocated');
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
        // [SCENARIO] A consultant selects a whole customer in the overview and sends it. Each
        // project is a separate agreement with its own budget, so it gets its own review and its
        // own mail - one combined mail would make the customer approve hours across projects that
        // may be invoiced separately and at different rates.
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
        // [WHEN] Both projects are sent in one call
        FilterOwnProjects(TimeEntry);
        Created := CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        // [THEN] Two reviews, one per project, each holding only its own entries
        Assert.AreEqual(2, Created, 'A selection spanning two projects must produce one review per project');
        Assert.AreEqual(2, TempReview.Count(), 'The returned temporary buffer must hold both review headers');
        GetReviewOfProject(JobA, ReviewA);
        GetReviewOfProject(JobB, ReviewB);
        Assert.AreNotEqual(ReviewA."Review No.", ReviewB."Review No.", 'The two projects must get two distinct reviews');
        AssertEntry('A1', "BCJ Billing Status"::"Sent for Review", 2, ReviewA."Review No.", 'Entry A1 must belong to the review of its own project');
        AssertEntry('A2', "BCJ Billing Status"::"Sent for Review", 1, ReviewA."Review No.", 'Entry A2 must belong to the review of its own project');
        AssertEntry('B1', "BCJ Billing Status"::"Sent for Review", 4, ReviewB."Review No.", 'Entry B1 must belong to the review of its own project');
    end;

    [Test]
    procedure CreateReviews_TakesOnlyOpenEntries()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
        Created: Integer;
    begin
        // [SCENARIO] Only undecided (Open) hours are the customer's business. Hours already
        // decided as Billable or Not Billable, and above all hours already invoiced (Billed),
        // must never be re-opened for approval - the customer would be asked to approve an
        // invoice that has already been sent. Such entries inside the selection are ignored
        // rather than rejected, because selecting a whole task or project is the normal way to work.
        // [GIVEN] One task holding one Open entry and one entry in each decided status
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('OPEN', JobNo, 'T1', D(), 1, "BCJ Billing Status"::Open);
        AddEntry('BILLABLE', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Billable);
        AddEntry('BILLED', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Billed);
        AddEntry('NOTBILL', JobNo, 'T1', D(), 4, "BCJ Billing Status"::"Not Billable");
        // [WHEN] The whole task is sent
        FilterOwnProjects(TimeEntry);
        Created := CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        // [THEN] Only the Open hour is on the review; the decided entries are untouched
        Assert.AreEqual(1, Created, 'A selection with at least one Open entry must create the review for that project');
        TempReview.FindFirst();
        Review.Get(TempReview."Review No.");
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(1.0, ReviewLine."Logged Hours", 'Only the hours of Open entries may be put in front of the customer');
        Assert.AreEqual(1, ReviewLine."Entry Count", 'Only the Open entry may be counted as sent');
        AssertEntry('OPEN', "BCJ Billing Status"::"Sent for Review", 1, Review."Review No.", 'The Open entry must be the one parked in the review');
        AssertEntry('BILLABLE', "BCJ Billing Status"::Billable, 2, 0, 'An already Billable entry must stay decided and outside the review');
        AssertEntry('BILLED', "BCJ Billing Status"::Billed, 3, 0, 'An already invoiced entry must never be sent for approval again');
        AssertEntry('NOTBILL', "BCJ Billing Status"::"Not Billable", 4, 0, 'An explicitly Not Billable entry must stay decided and outside the review');
    end;

    [Test]
    procedure CreateReviews_WithoutOpenEntriesErrorsAndCreatesNothing()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] Sending a selection that holds nothing to approve must tell the consultant
        // so, not silently create an empty review that the customer then receives a mail about.
        // [GIVEN] A project whose entries are all already decided
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('B1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Billable);
        AddEntry('B2', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Billed);
        // [WHEN] It is sent for review
        FilterOwnProjects(TimeEntry);
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        // [THEN] A plain error, no review, and the entries untouched
        Assert.ExpectedErrorCode('Dialog');
        Review.SetRange("Project No.", JobNo);
        Assert.IsTrue(Review.IsEmpty(), 'A selection with nothing to approve must leave no review behind');
        AssertEntry('B1', "BCJ Billing Status"::Billable, 2, 0, 'A failed send must leave the Billable entry exactly as it was');
        AssertEntry('B2', "BCJ Billing Status"::Billed, 3, 0, 'A failed send must leave the Billed entry exactly as it was');
    end;

    [Test]
    procedure CreateReviews_BlankReviewBaseUrlErrorsBeforeAnyWrite()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] Without a review base URL the mail would carry a link the customer cannot
        // open, while the hours would already sit in "Sent for Review" - invisible to invoicing
        // and unanswerable by the customer. The setup is therefore checked before anything is
        // written, so a missing URL costs nothing but a re-run.
        // [GIVEN] Open entries and no review base URL configured
        Initialize();
        BCJTestLibrary.EnsureSetup('');
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        // [WHEN] The project is sent for review
        FilterOwnProjects(TimeEntry);
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        // [THEN] A field check fails and nothing at all was created or moved
        Assert.ExpectedErrorCode('TestField');
        Review.SetRange("Project No.", JobNo);
        Assert.IsTrue(Review.IsEmpty(), 'A missing review base URL must leave no review behind');
        AssertEntry('E1', "BCJ Billing Status"::Open, 2, 0, 'The entry must still be Open and unreviewed after the setup check failed');
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
        // [WHEN] Both are sent in one call
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
        // selection, a task row already contained in it - the tree makes that easy to do by
        // accident. The overlap must collapse: an entry reached twice is still one entry, sent
        // once, on one review line, counted once. Double counting would show the customer the
        // same hours twice and double what they approve.
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
        Assert.AreEqual(2, ReviewLine."Entry Count", 'The overlapping task must count each of its two entries once');
        ReviewLine.Get(ReviewA."Review No.", 'T2');
        Assert.AreEqual(3.0, ReviewLine."Logged Hours", 'The task reached only through the customer row must still be sent');
        ReviewLine.Get(ReviewB."Review No.", 'T1');
        Assert.AreEqual(4.0, ReviewLine."Logged Hours", 'The second project of the selected customer must be sent too');
        AssertEntry('A1', "BCJ Billing Status"::"Sent for Review", 2, ReviewA."Review No.", 'Entry A1 must be sent exactly once, on the review of its own project');
        AssertEntry('B1', "BCJ Billing Status"::"Sent for Review", 4, ReviewB."Review No.", 'Entry B1 must be sent exactly once, on the review of its own project');
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
        // [SCENARIO] Reviews are sent per billing period. An open entry outside the period the
        // consultant filtered on belongs to the next invoice and must stay out of this review -
        // otherwise the customer approves hours that were never meant to be in the period, and
        // the next review has nothing left to show.
        // [GIVEN] Two open entries on the same task, five days apart
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('IN', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('OUT', JobNo, 'T1', D() + 5, 3, "BCJ Billing Status"::Open);
        // [WHEN] Only the first period is sent
        FilterOwnProjects(TimeEntry);
        TimeEntry.SetRange("Posting Date", D(), D() + 1);
        CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        // [THEN] The review holds the filtered entry only; the later entry is still Open
        TempReview.FindFirst();
        Review.Get(TempReview."Review No.");
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(2.0, ReviewLine."Logged Hours", 'Only hours inside the posting date filter may be sent for approval');
        Assert.AreEqual(1, ReviewLine."Entry Count", 'Only the entry inside the posting date filter may be counted as sent');
        AssertEntry('IN', "BCJ Billing Status"::"Sent for Review", 2, Review."Review No.", 'The entry inside the filter must be parked in the review');
        AssertEntry('OUT', "BCJ Billing Status"::Open, 3, 0, 'An open entry outside the posting date filter must stay Open and unreviewed');
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
    procedure SendReviews_WithoutRecipientSkipsMailAndKeepsReview()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        Sent: Integer;
    begin
        // [SCENARIO] A project with no contact and no customer e-mail is a data gap, not a reason
        // to abandon the review: the consultant can still send the link by hand from the review
        // card. So the review is created and stays Sent, the mail is skipped, and nothing is
        // stamped as sent - a false "sent on" timestamp would hide the gap forever.
        // [GIVEN] A project whose customer has no e-mail and no bill-to contact
        Initialize();
        CreateSingleTaskProjectWithOpenEntry('E1', 2);
        FilterOwnProjects(TimeEntry);
        CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        TempReview.FindFirst();
        Review.Get(TempReview."Review No.");
        Assert.AreEqual('', ReviewMail.GetRecipientEmail(Review), 'With neither contact nor customer e-mail there must be no recipient at all');
        // [WHEN] The reviews are sent
        Sent := CustomerReviewMgt.SendReviews(TempReview);
        // [THEN] No mail counted, no stamps, review still waiting for the customer
        Assert.AreEqual(0, Sent, 'A review without a recipient must count as not sent');
        Review.Get(TempReview."Review No.");
        Assert.AreEqual("BCJ Review Status"::Sent, Review.Status, 'A review whose mail could not be sent must still exist and still be waiting for an answer');
        Assert.AreEqual('', Review."Sent To E-Mail", 'No recipient may be stamped when no mail was sent');
        Assert.AreEqual(0DT, Review."E-Mail Sent On", 'No sent-on timestamp may be stamped when no mail was sent');
        AssertEntry('E1', "BCJ Billing Status"::"Sent for Review", 2, Review."Review No.", 'The entries must stay parked in the review even when the mail could not be sent');
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
    // Submit and apply
    // ---------------------------------------------------------------------------------

    [Test]
    procedure SubmitReview_FullApprovalMakesEveryEntryBillable()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] The customer approves everything. Every hour sent then becomes invoiceable
        // exactly as logged - the answer is applied immediately, because a consultant who has to
        // re-open each review to apply it will eventually not bother, and the hours rot.
        // [GIVEN] A review over two tasks and three entries
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        CreateTask(JobNo, 'T2');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('E2', JobNo, 'T1', D() + 1, 1, "BCJ Billing Status"::Open);
        AddEntry('E3', JobNo, 'T2', D(), 3, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        // [WHEN] Every line is approved in full and the review is submitted
        ApproveAllLogged(Review."Review No.");
        CustomerReviewMgt.SubmitReview(Review);
        // [THEN] The review is answered and every entry is billable for its full hours
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Answered, Review.Status, 'A submitted review must be Answered');
        Assert.AreNotEqual(0DT, Review."Answered On", 'A submitted review must record when the customer answered');
        AssertEntry('E1', "BCJ Billing Status"::Billable, 2, Review."Review No.", 'A fully approved entry must become Billable for all of its hours');
        AssertEntry('E2', "BCJ Billing Status"::Billable, 1, Review."Review No.", 'A fully approved entry must become Billable for all of its hours');
        AssertEntry('E3', "BCJ Billing Status"::Billable, 3, Review."Review No.", 'A fully approved entry must become Billable for all of its hours');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(3.0, ReviewLine."Applied Hours", 'Applied Hours must equal the approved hours when every approved hour found an entry');
        ReviewLine.Get(Review."Review No.", 'T2');
        Assert.AreEqual(3.0, ReviewLine."Applied Hours", 'Applied Hours must equal the approved hours when every approved hour found an entry');
    end;

    [Test]
    procedure SubmitReview_ZeroApprovalMakesEveryEntryNotBillable()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] The customer rejects a task outright. The hours were still worked and must
        // stay on the project as a record, but nothing may reach an invoice: status Not Billable
        // with a zero allocation. Leaving them Open would put them back in the next review.
        // [GIVEN] A review over one task with two entries
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('E2', JobNo, 'T1', D() + 1, 1, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        // [WHEN] The line is approved for zero hours and submitted
        SetApproved(Review."Review No.", 'T1', 0);
        CustomerReviewMgt.SubmitReview(Review);
        // [THEN] Both entries are Not Billable with nothing allocated
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Answered, Review.Status, 'A submitted review must be Answered even when nothing was approved');
        AssertEntry('E1', "BCJ Billing Status"::"Not Billable", 0, Review."Review No.", 'An entry on a task approved for zero hours must be Not Billable with no hours allocated');
        AssertEntry('E2', "BCJ Billing Status"::"Not Billable", 0, Review."Review No.", 'An entry on a task approved for zero hours must be Not Billable with no hours allocated');
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
        // [SCENARIO] The customer approves fewer hours than were logged. The approval is per task,
        // so someone has to decide which worklog carries the cut: oldest first, because the
        // earliest hours are the ones the customer has had the longest and is least likely to
        // dispute, and because a deterministic order makes the result reproducible and auditable.
        // [GIVEN] A task with 1 hour on day D and 3 hours on day D+1, of which 2.5 are approved
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('OLD', JobNo, 'T1', D(), 1, "BCJ Billing Status"::Open);
        AddEntry('NEW', JobNo, 'T1', D() + 1, 3, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        // [WHEN] 2.5 hours are approved and the review is submitted
        SetApproved(Review."Review No.", 'T1', 2.5);
        CustomerReviewMgt.SubmitReview(Review);
        // [THEN] The older entry is filled first, the newer takes the remainder
        Review.Get(Review."Review No.");
        AssertEntry('OLD', "BCJ Billing Status"::Billable, 1, Review."Review No.", 'The oldest entry must be filled first and keep all of its hour');
        AssertEntry('NEW', "BCJ Billing Status"::Billable, 1.5, Review."Review No.", 'The newer entry must carry the cut and keep only the approved remainder');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(2.5, ReviewLine."Applied Hours", 'All approved hours must be applied when the entries can absorb them');
    end;

    [Test]
    procedure SubmitReview_PartialApprovalZeroesTheEntryLeftWithNothing()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] When the approved hours run out before the entries do, the entries left over
        // are decided, not undecided: nothing was approved for them, so they are Not Billable with
        // a zero allocation. Leaving them Billable with zero hours would put a zero line on an
        // invoice; leaving them Open would send them to the customer a second time.
        // [GIVEN] A task with 2 hours on day D and 1 hour on day D+1, of which exactly 2 are approved
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('OLD', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('NEW', JobNo, 'T1', D() + 1, 1, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        // [WHEN] 2 hours are approved and the review is submitted
        SetApproved(Review."Review No.", 'T1', 2);
        CustomerReviewMgt.SubmitReview(Review);
        // [THEN] The older entry keeps its hours, the newer is explicitly not billable
        Review.Get(Review."Review No.");
        AssertEntry('OLD', "BCJ Billing Status"::Billable, 2, Review."Review No.", 'The oldest entry must absorb the approved hours in full');
        AssertEntry('NEW', "BCJ Billing Status"::"Not Billable", 0, Review."Review No.", 'An entry left with no approved hours must be Not Billable, never Billable for zero hours');
    end;

    [Test]
    procedure SubmitReview_SamePostingDateAllocatesInJiraIdOrder()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] Two worklogs on the same day are the common case, so posting date alone does
        // not determine the order. The Jira ID breaks the tie, which makes the allocation
        // deterministic: the same answer applied twice must always cut the same worklog, or two
        // runs of the same review produce two different invoices.
        // [GIVEN] Two 3-hour entries on the same day, of which only 3 hours are approved
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('A', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        AddEntry('B', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        // [WHEN] 3 hours are approved and the review is submitted
        SetApproved(Review."Review No.", 'T1', 3);
        CustomerReviewMgt.SubmitReview(Review);
        // [THEN] The lower Jira ID is served first and the other is left with nothing
        Review.Get(Review."Review No.");
        AssertEntry('A', "BCJ Billing Status"::Billable, 3, Review."Review No.", 'On equal posting dates the lower Jira ID must be allocated first');
        AssertEntry('B', "BCJ Billing Status"::"Not Billable", 0, Review."Review No.", 'On equal posting dates the higher Jira ID must be the one left without approved hours');
    end;

    [Test]
    procedure SubmitReview_SecondSubmitIsRejected()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] The customer's browser can be reloaded and the API can be called twice. A
        // second submit must not apply the answer again: the entries are no longer in review, so a
        // re-run would find nothing and could silently zero the allocation that was already made.
        // [GIVEN] A review that has been submitted once
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        SetApproved(Review."Review No.", 'T1', 2);
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
        AssertEntry('E1', "BCJ Billing Status"::Billable, 2, Review."Review No.", 'A refused second submit must leave the applied allocation untouched');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(2.0, ReviewLine."Applied Hours", 'A refused second submit must not change what was already applied');
    end;

    [Test]
    procedure SubmitReview_AfterCancelIsRejected()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] The consultant cancels a review and the hours go back to Open for another
        // decision. A customer who still has the old link open must not be able to submit it
        // afterwards - that would re-decide hours the consultant has meanwhile taken back.
        // [GIVEN] A cancelled review
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        SetApproved(Review."Review No.", 'T1', 2);
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
        AssertEntry('E1', "BCJ Billing Status"::Open, 2, 0, 'A late submit on a cancelled review must not re-decide the released entry');
    end;

    [Test]
    procedure ReviewLine_ApprovedHoursOutsideRangeIsRejected()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] The approved hours come from a public web form. Approving more than was
        // logged would invent hours nobody worked and let the allocation exceed what exists;
        // approving a negative number is meaningless. Both are refused at the field, before
        // anything is stored, because the API writes the line directly.
        // [GIVEN] A review line with 3 logged hours
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        ReviewLine.Get(Review."Review No.", 'T1');
        // [WHEN] More hours than logged are approved
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror ReviewLine.Validate("Approved Hours", 4);
        // [THEN] Refused and the stored value is unchanged
        Assert.ExpectedErrorCode('Dialog');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(0.0, ReviewLine."Approved Hours", 'Approving more hours than were logged must leave the stored approval unchanged');
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
        // customer agreed to and what was billed on the strength of it. The API stays open to the
        // customer's browser, so the table itself refuses the write: editing an answered line
        // would leave the review saying something different from what the entries carry.
        // [GIVEN] A review that has been answered
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        SetApproved(Review."Review No.", 'T1', 3);
        CustomerReviewMgt.SubmitReview(Review);
        // [WHEN] The customer tries to change the approved hours afterwards
        ReviewLine.Get(Review."Review No.", 'T1');
        ReviewLine.Validate("Approved Hours", 1);
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror ReviewLine.Modify(true);
        // [THEN] Refused and the answered line is unchanged
        Assert.ExpectedErrorCode('TestField');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(3.0, ReviewLine."Approved Hours", 'An answered review line must keep the hours the customer actually approved');
        AssertEntry('E1', "BCJ Billing Status"::Billable, 3, Review."Review No.", 'A refused line edit must not change what was allocated to the entries');
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
        // the customer is still holding the review. The customer's answer then refers to hours
        // that no longer exist. Applying what remains and recording the shortfall in Applied Hours
        // is right: erroring would trap the review forever, and inventing the missing hours would
        // bill work the consultant has withdrawn.
        // [GIVEN] A review over 2 + 3 hours, of which the 3-hour entry is deleted afterwards
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('KEPT', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('GONE', JobNo, 'T1', D() + 1, 3, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(5.0, ReviewLine."Logged Hours", 'Fixture: the review line must have been sent with both entries');
        GetEntry('GONE', TimeEntry);
        TimeEntry.Delete(false);
        // [WHEN] The customer approves all 5 hours and submits
        SetApproved(Review."Review No.", 'T1', 5);
        CustomerReviewMgt.SubmitReview(Review);
        // [THEN] The surviving entry is billable in full, and the shortfall is visible, not an error
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Answered, Review.Status, 'A review whose entries partly disappeared must still be answerable');
        AssertEntry('KEPT', "BCJ Billing Status"::Billable, 2, Review."Review No.", 'The surviving entry must take as much of the approval as it can carry');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(2.0, ReviewLine."Applied Hours", 'Applied Hours must show what could actually be allocated, not what was approved');
        Assert.AreEqual(5.0, ReviewLine."Approved Hours", 'What the customer approved must be kept as the customer stated it');
    end;

    [Test]
    procedure SubmitReview_AfterEntryHoursReducedCapsAllocation()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        TimeEntry: Record "BCJ Project Time Entry";
        JobNo: Code[20];
    begin
        // [SCENARIO] A consultant can correct a worklog in Jira while the review is out, and the
        // sync brings the smaller number into BC. The customer then approves 4 hours against an
        // entry that now only holds 1.5. An entry may never be billable for more hours than it
        // logs, so the allocation is capped at the entry - the customer's approval is a ceiling,
        // not a quantity to be invented.
        // [GIVEN] A review over one 4-hour entry that is re-synced down to 1.5 hours
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 4, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        GetEntry('E1', TimeEntry);
        TimeEntry.Validate("Time Spent in Hours", 1.5);
        TimeEntry.Modify(true);
        // [WHEN] The customer approves the 4 hours they were originally shown
        SetApproved(Review."Review No.", 'T1', 4);
        CustomerReviewMgt.SubmitReview(Review);
        // [THEN] Only the hours that still exist are allocated
        Review.Get(Review."Review No.");
        AssertEntry('E1', "BCJ Billing Status"::Billable, 1.5, Review."Review No.", 'An entry must never be billable for more hours than it now logs');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(1.5, ReviewLine."Applied Hours", 'Applied Hours must show the capped allocation, not the approval');
    end;

    // ---------------------------------------------------------------------------------
    // Cancel and reopen
    // ---------------------------------------------------------------------------------

    [Test]
    procedure CancelReview_ReturnsEntriesToOpen()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] A review sent to the wrong customer, or superseded by a phone call, has to be
        // taken back. The hours must return to exactly the state they were in before it was sent -
        // Open, no review, full allocation - or they are stranded in "Sent for Review" where no
        // invoicing run and no later review will ever pick them up again.
        // [GIVEN] A review holding two entries
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('E2', JobNo, 'T1', D() + 1, 3, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        // [WHEN] The review is cancelled
        CustomerReviewMgt.CancelReview(Review);
        // [THEN] The entries are Open again with their hours intact, and the review records the cancellation
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Cancelled, Review.Status, 'A cancelled review must be Cancelled');
        Assert.AreNotEqual(0DT, Review."Cancelled On", 'A cancelled review must record when it was cancelled');
        AssertEntry('E1', "BCJ Billing Status"::Open, 2, 0, 'A released entry must be Open again, unlinked from the review, with its full hours allocated');
        AssertEntry('E2', "BCJ Billing Status"::Open, 3, 0, 'A released entry must be Open again, unlinked from the review, with its full hours allocated');
    end;

    [Test]
    procedure CancelReview_LeavesBilledEntriesUntouched()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] An entry can be invoiced by another route while the review is out - the
        // legacy page still sets Is Billed. Cancelling the review must not drag an invoiced hour
        // back to Open: the invoice exists, and re-opening it would let the same hour be billed a
        // second time. Only what is still sitting in the review is released.
        // [GIVEN] A review whose second entry has meanwhile been invoiced
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('INREVIEW', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('BILLED', JobNo, 'T1', D() + 1, 3, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        SetEntryStatus('BILLED', "BCJ Billing Status"::Billed);
        // [WHEN] The review is cancelled
        CustomerReviewMgt.CancelReview(Review);
        // [THEN] Only the entry still in review is released
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Cancelled, Review.Status, 'A review must still cancel when some of its entries have moved on');
        AssertEntry('INREVIEW', "BCJ Billing Status"::Open, 2, 0, 'The entry still in review must be released back to Open');
        AssertEntry('BILLED', "BCJ Billing Status"::Billed, 3, Review."Review No.", 'An entry invoiced while the review was out must stay Billed and keep its review link');
    end;

    [Test]
    procedure CancelReview_AfterAnsweredIsRejected()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] Cancelling releases hours back to Open. Doing that after the customer has
        // answered would throw away their decision and re-open hours that are already billable -
        // the way back from an answered review is Reopen, which keeps the answer.
        // [GIVEN] An answered review
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        SetApproved(Review."Review No.", 'T1', 2);
        CustomerReviewMgt.SubmitReview(Review);
        // [WHEN] The consultant tries to cancel it
        Review.Get(Review."Review No.");
        // Commit so the fixtures survive the rollback that asserterror performs - the runner still rolls the whole codeunit back, so nothing persists.
        Commit();
        asserterror CustomerReviewMgt.CancelReview(Review);
        // [THEN] Refused, and the answer stands
        Assert.ExpectedErrorCode('TestField');
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Answered, Review.Status, 'An answered review must stay Answered when a cancel is refused');
        AssertEntry('E1', "BCJ Billing Status"::Billable, 2, Review."Review No.", 'A refused cancel must not release an entry the customer already approved');
    end;

    [Test]
    procedure ReopenReview_RestoresEntriesAndKeepsApprovedHours()
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        JobNo: Code[20];
    begin
        // [SCENARIO] The customer answers, then phones to say they meant something else. Reopen
        // puts the hours back in review and undoes the allocation, but keeps what they approved
        // and wrote - the consultant needs to see the original answer to discuss it, and typing it
        // in again would lose the customer's own words. Submitting again must then apply cleanly,
        // not on top of the first allocation.
        // [GIVEN] An answered review where 4 of 5 hours were approved
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('OLD', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('NEW', JobNo, 'T1', D() + 1, 3, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        SetApproved(Review."Review No.", 'T1', 4);
        CustomerReviewMgt.SubmitReview(Review);
        AssertEntry('OLD', "BCJ Billing Status"::Billable, 2, Review."Review No.", 'Fixture: the first answer must have been applied oldest first');
        AssertEntry('NEW', "BCJ Billing Status"::Billable, 2, Review."Review No.", 'Fixture: the first answer must have been applied oldest first');
        // [WHEN] The review is reopened
        Review.Get(Review."Review No.");
        CustomerReviewMgt.ReopenReview(Review);
        // [THEN] The hours are back in review with their full allocation, the answer is kept
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Sent, Review.Status, 'A reopened review must be Sent again, waiting for a new answer');
        Assert.AreEqual(0DT, Review."Answered On", 'A reopened review must no longer claim to have been answered');
        AssertEntry('OLD', "BCJ Billing Status"::"Sent for Review", 2, Review."Review No.", 'A reopened entry must be back in review with its full logged hours allocated');
        AssertEntry('NEW', "BCJ Billing Status"::"Sent for Review", 3, Review."Review No.", 'A reopened entry must be back in review with its full logged hours allocated');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(0.0, ReviewLine."Applied Hours", 'A reopened line must show nothing as applied, because the allocation was undone');
        Assert.AreEqual(4.0, ReviewLine."Approved Hours", 'A reopened line must keep what the customer approved, so it can be discussed and adjusted');
        // [WHEN] It is submitted again unchanged
        Review.Get(Review."Review No.");
        CustomerReviewMgt.SubmitReview(Review);
        // [THEN] The same allocation is produced again, not doubled
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Answered, Review.Status, 'A reopened review must be answerable again');
        AssertEntry('OLD', "BCJ Billing Status"::Billable, 2, Review."Review No.", 'Re-applying the same answer must give the same allocation as the first time');
        AssertEntry('NEW', "BCJ Billing Status"::Billable, 2, Review."Review No.", 'Re-applying the same answer must give the same allocation as the first time');
        ReviewLine.Get(Review."Review No.", 'T1');
        Assert.AreEqual(4.0, ReviewLine."Applied Hours", 'Re-applying the same answer must apply the approved hours once, not twice');
    end;

    [Test]
    procedure ReopenReview_OnSentReviewIsRejected()
    var
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] Reopen exists to undo an applied answer. On a review the customer has not
        // answered yet there is nothing to undo, and running it would clear approved hours and
        // stamps for no reason. The consultant who wants those hours back uses Cancel.
        // [GIVEN] A review that is still out with the customer
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
        Assert.ExpectedErrorCode('TestField');
        Review.Get(Review."Review No.");
        Assert.AreEqual("BCJ Review Status"::Sent, Review.Status, 'A review still waiting for an answer must stay Sent when a reopen is refused');
        AssertEntry('E1', "BCJ Billing Status"::"Sent for Review", 2, Review."Review No.", 'A refused reopen must leave the entries in review exactly as they were');
    end;

    // ---------------------------------------------------------------------------------
    // Interaction with the existing status handling
    // ---------------------------------------------------------------------------------

    [Test]
    procedure SetBillingStatus_SkipsEntriesSentForReview()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
        Changed: Integer;
        InReview: Integer;
    begin
        // [SCENARIO] "Mark as Billable" over a project must not overrule a review that is out with
        // the customer: deciding those hours behind the customer's back would make the answer,
        // when it arrives, contradict what was already invoiced. They are skipped silently and are
        // not counted as changed, and CountEntriesInReview is what tells the consultant why the
        // number they got back is smaller than the number of lines they selected.
        // [GIVEN] A project with an Open entry, an already Billable entry and an entry out for review
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        CreateTask(JobNo, 'T2');
        AddEntry('OPEN', JobNo, 'T1', D(), 1, "BCJ Billing Status"::Open);
        AddEntry('BILLABLE', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Billable);
        AddEntry('INREVIEW', JobNo, 'T2', D(), 3, "BCJ Billing Status"::Open);
        FilterOwnProjects(TimeEntry);
        TimeEntry.SetRange("Project Task No.", 'T2');
        CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        TempReview.FindFirst();
        Review.Get(TempReview."Review No.");
        // [WHEN] The whole project is marked Billable
        FilterOwnProjects(TimeEntry);
        Changed := BillingMgt.SetBillingStatus(TimeEntry, "BCJ Billing Status"::Billable);
        // [THEN] The entry in review is neither changed nor counted, and is reported separately
        Assert.AreEqual(1, Changed, 'Only the Open entry may be changed and counted: the Billable one already had the status and the one in review must be skipped');
        AssertEntry('OPEN', "BCJ Billing Status"::Billable, 1, 0, 'An Open entry outside any review must take the new status');
        AssertEntry('BILLABLE', "BCJ Billing Status"::Billable, 2, 0, 'An already Billable entry must keep its status');
        AssertEntry('INREVIEW', "BCJ Billing Status"::"Sent for Review", 3, Review."Review No.", 'An entry out for customer review must not be re-decided behind the customer back');
        FilterOwnProjects(TimeEntry);
        InReview := BillingMgt.CountEntriesInReview(TimeEntry);
        Assert.AreEqual(1, InReview, 'CountEntriesInReview must report the entries that were skipped because they are out for review');
    end;

    [Test]
    procedure SyncStatusFromLegacyFlags_LeavesSentForReviewEntriesUntouched()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
        JobNo: Code[20];
    begin
        // [SCENARIO] The legacy Jira Time Entries page can still set Is Billed with a plain
        // ModifyAll, and the sync normally promotes such an entry to Billed whatever status it
        // has. An entry out for customer review is the one exception: promoting it would decide
        // hours the customer is still looking at and would leave the review pointing at entries
        // that are no longer in it.
        // [GIVEN] An entry out for review whose legacy Is Billed flag gets set
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        CreateOneReview(Review);
        GetEntry('E1', TimeEntry);
        BCJTestLibrary.SetLegacyFlags(TimeEntry, false, true);
        // [WHEN] The legacy flag sync runs
        BillingMgt.SyncStatusFromLegacyFlags();
        // [THEN] The entry is still out for review, with its review link and allocation intact
        AssertEntry('E1', "BCJ Billing Status"::"Sent for Review", 2, Review."Review No.", 'A legacy Is Billed flag must not pull an entry out of an open customer review');
    end;

    [Test]
    procedure TimeEntry_InsertDefaultsBillableHoursToLoggedHours()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Stored: Record "BCJ Project Time Entry";
        JobNo: Code[20];
    begin
        // [SCENARIO] Billable Hours carries what the customer agreed to pay for, and every other
        // number in the overview is computed from it. A freshly synced worklog has not been
        // reviewed, so it is fully billable until someone says otherwise - a zero here would make
        // new hours vanish from the billable totals the day they are synced. A value already set
        // by the caller is a deliberate allocation and must be kept.
        // [GIVEN] A project and task
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        // [WHEN] An entry is inserted with validation and no allocation of its own
        TimeEntry.Init();
        TimeEntry."Jira ID" := JiraId('E1');
        TimeEntry."Jira Issue Id" := CopyStr('I-' + JiraId('E1'), 1, 50);
        TimeEntry."Project No." := JobNo;
        TimeEntry."Project Task No." := 'T1';
        TimeEntry."Posting Date" := D();
        TimeEntry."Time Spent in Hours" := 2.5;
        TimeEntry."Billing Status" := "BCJ Billing Status"::Open;
        TimeEntry.Insert(true);
        // [THEN] The whole logged time is billable
        Stored.Get(JiraId('E1'), CopyStr('I-' + JiraId('E1'), 1, 50));
        Assert.AreEqual(2.5, Stored."Billable Hours", 'A newly synced worklog must be fully billable until a review says otherwise');
        // [WHEN] An entry is inserted that already carries an allocation
        TimeEntry.Init();
        TimeEntry."Jira ID" := JiraId('E2');
        TimeEntry."Jira Issue Id" := CopyStr('I-' + JiraId('E2'), 1, 50);
        TimeEntry."Project No." := JobNo;
        TimeEntry."Project Task No." := 'T1';
        TimeEntry."Posting Date" := D();
        TimeEntry."Time Spent in Hours" := 4;
        TimeEntry."Billable Hours" := 1;
        TimeEntry."Billing Status" := "BCJ Billing Status"::Open;
        TimeEntry.Insert(true);
        // [THEN] The allocation the caller set is kept
        Stored.Get(JiraId('E2'), CopyStr('I-' + JiraId('E2'), 1, 50));
        Assert.AreEqual(1.0, Stored."Billable Hours", 'An allocation supplied by the caller must survive the insert, not be overwritten by the logged hours');
    end;

    [Test]
    procedure TimeEntry_ValidateLoggedHoursUpdatesBillableHours()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        JobNo: Code[20];
    begin
        // [SCENARIO] The sync rewrites logged hours when a consultant corrects a worklog in Jira.
        // On an undecided entry the allocation simply follows, since nobody has decided anything
        // yet. On a decided entry the agreed allocation must be left alone - unless it now exceeds
        // the hours that exist, which would let an entry be billable for more than it logs.
        // [GIVEN] An Open entry of 2 hours, a Billable entry fully allocated, and a Billable entry
        // allocated below its logged hours
        Initialize();
        JobNo := CreateProject('P1', CreateCustomer('C'));
        CreateTask(JobNo, 'T1');
        AddEntry('OPEN', JobNo, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('FULL', JobNo, 'T1', D(), 4, "BCJ Billing Status"::Billable);
        AddEntry('PART', JobNo, 'T1', D(), 4, "BCJ Billing Status"::Billable);
        SetBillableHours('PART', 1);
        // [WHEN] The logged hours of the Open entry are corrected upwards
        GetEntry('OPEN', TimeEntry);
        TimeEntry.Validate("Time Spent in Hours", 5);
        TimeEntry.Modify(true);
        // [THEN] The allocation follows the new logged hours
        Assert.AreEqual(5.0, GetBillableHours('OPEN'), 'On an undecided entry the billable hours must follow the corrected logged hours');
        // [WHEN] The logged hours of a fully allocated Billable entry are corrected downwards
        GetEntry('FULL', TimeEntry);
        TimeEntry.Validate("Time Spent in Hours", 1.5);
        TimeEntry.Modify(true);
        // [THEN] The allocation is clamped to what is left
        Assert.AreEqual(1.5, GetBillableHours('FULL'), 'A decided entry must never stay billable for more hours than it now logs');
        // [WHEN] The logged hours of a partly allocated Billable entry are corrected downwards but stay above the allocation
        GetEntry('PART', TimeEntry);
        TimeEntry.Validate("Time Spent in Hours", 3);
        TimeEntry.Modify(true);
        // [THEN] The agreed allocation is left alone
        Assert.AreEqual(1.0, GetBillableHours('PART'), 'A correction that still covers the agreed allocation must not change what was agreed');
    end;

    // ---------------------------------------------------------------------------------
    // Overview hours
    // ---------------------------------------------------------------------------------

    [Test]
    procedure Overview_BillableEntrySplitsAllocatedAndUnallocatedHours()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        CustomerNo: Code[20];
        JobNo: Code[20];
    begin
        // [SCENARIO] After a review, a Billable entry carries two different numbers: the hours the
        // customer agreed to pay for and the hours worked. The overview must show both sides -
        // the agreed hours as billable, the rest as not billable - so the difference between what
        // was worked and what will be invoiced is visible instead of silently disappearing.
        // [GIVEN] A billable entry of 3 logged hours with 1.5 hours agreed
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobNo := CreateProject('P1', CustomerNo);
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Billable);
        SetBillableHours('E1', 1.5);
        // [WHEN] The overview is built
        FilterOwnProjects(TimeEntryFilter);
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, true);
        // [THEN] Total 3, billable 1.5, the remaining 1.5 not billable, unbilled 1.5
        FindLine(Buffer, LineType::Task, CustomerNo, JobNo, 'T1');
        AssertHours(Buffer, 3, 0, 0, 1.5, 1.5, 0, 1.5, 'Task with a partly agreed billable entry');
        FindLine(Buffer, LineType::Project, CustomerNo, JobNo, '');
        AssertHours(Buffer, 3, 0, 0, 1.5, 1.5, 0, 1.5, 'Project with a partly agreed billable entry');
    end;

    [Test]
    procedure Overview_BilledEntrySplitsBilledAndNotBilledHours()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        CustomerNo: Code[20];
        JobNo: Code[20];
    begin
        // [SCENARIO] Once invoiced, only the hours that were actually invoiced are Billed. The
        // hours the customer struck off were worked and never charged, so they belong under Not
        // Billable, and nothing of this entry is still waiting to be invoiced - a billed entry
        // must add nothing to Unbilled, or the same hours would be chased twice.
        // [GIVEN] A billed entry of 3 logged hours of which 1 was invoiced
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobNo := CreateProject('P1', CustomerNo);
        CreateTask(JobNo, 'T1');
        AddEntry('E1', JobNo, 'T1', D(), 3, "BCJ Billing Status"::Billed);
        SetBillableHours('E1', 1);
        // [WHEN] The overview is built
        FilterOwnProjects(TimeEntryFilter);
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, true);
        // [THEN] Total 3, billed 1, not billable 2, nothing unbilled
        FindLine(Buffer, LineType::Task, CustomerNo, JobNo, 'T1');
        AssertHours(Buffer, 3, 0, 0, 0, 2, 1, 0, 'Task with a partly invoiced billed entry');
        FindLine(Buffer, LineType::Project, CustomerNo, JobNo, '');
        AssertHours(Buffer, 3, 0, 0, 0, 2, 1, 0, 'Project with a partly invoiced billed entry');
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
        // [SCENARIO] Hours out with the customer are undecided but not forgotten: they get their
        // own bucket so the consultant can see what is waiting on an answer, and they still count
        // as unbilled, because they are money the firm expects to invoice once the answer comes.
        // Dropping them out of Unbilled would make the work in progress look smaller than it is.
        // [GIVEN] An open entry of 4 hours that is sent for customer review
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
        AssertHours(Buffer, 4, 0, 4, 0, 0, 0, 4, 'Task whose hours are out for customer review');
        FindLine(Buffer, LineType::Customer, CustomerNo, '', '');
        AssertHours(Buffer, 4, 0, 4, 0, 0, 0, 4, 'Customer whose hours are out for customer review');
    end;

    [Test]
    procedure Overview_BucketsSumToTotalOnEveryLevel()
    var
        Buffer: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        CustomerNo: Code[20];
        JobA: Code[20];
        JobB: Code[20];
        LineName: Text;
    begin
        // [SCENARIO] The five buckets are how the overview is read: every logged hour is in
        // exactly one of them, on every row of the tree. If they stop adding up to the total, the
        // page is lying about where the work in progress sits - and nobody can tell which number
        // is wrong. This is the invariant the bucket maths exists to protect.
        // [GIVEN] One customer, two projects and all five states at once
        Initialize();
        CustomerNo := CreateCustomer('C');
        JobA := CreateProject('P1', CustomerNo);
        JobB := CreateProject('P2', CustomerNo);
        CreateTask(JobA, 'T1');
        CreateTask(JobA, 'T2');
        CreateTask(JobB, 'T1');
        AddEntry('OPEN', JobA, 'T1', D(), 2, "BCJ Billing Status"::Open);
        AddEntry('BILLABLE', JobA, 'T1', D(), 4, "BCJ Billing Status"::Billable);
        SetBillableHours('BILLABLE', 2.5);
        AddEntry('BILLED', JobA, 'T2', D(), 3, "BCJ Billing Status"::Billed);
        SetBillableHours('BILLED', 1);
        AddEntry('NOTBILL', JobB, 'T1', D(), 1.5, "BCJ Billing Status"::"Not Billable");
        AddEntry('INREVIEW', JobB, 'T1', D(), 5, "BCJ Billing Status"::Open);
        FilterOwnProjects(TimeEntry);
        TimeEntry.SetRange("Jira ID", JiraId('INREVIEW'));
        CustomerReviewMgt.CreateReviews(TimeEntry, TempReview);
        // [WHEN] The overview is built over the whole customer
        FilterOwnProjects(TimeEntryFilter);
        OverviewMgt.BuildOverview(Buffer, TimeEntryFilter, true);
        // [THEN] The customer row shows every state, and no row anywhere breaks the invariant
        FindLine(Buffer, LineType::Customer, CustomerNo, '', '');
        AssertHours(Buffer, 15.5, 2, 5, 2.5, 5, 1, 9.5, 'Customer with entries in all five states');
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
        TempReview: Record "BCJ Customer Review" temporary;
    begin
        FilterOwnProjects(TimeEntry);
        Assert.AreEqual(1, CustomerReviewMgt.CreateReviews(TimeEntry, TempReview), 'Fixture: the open entries of this test must produce exactly one review');
        TempReview.FindFirst();
        Review.Get(TempReview."Review No.");
    end;

    local procedure GetReviewOfProject(JobNo: Code[20]; var Review: Record "BCJ Customer Review")
    begin
        Review.Reset();
        Review.SetRange("Project No.", JobNo);
        Assert.AreEqual(1, Review.Count(), StrSubstNo('Exactly one review must exist for project %1', JobNo));
        Review.FindFirst();
    end;

    local procedure SetApproved(ReviewNo: Integer; TaskNo: Code[20]; Hours: Decimal)
    var
        ReviewLine: Record "BCJ Customer Review Line";
    begin
        ReviewLine.Get(ReviewNo, TaskNo);
        ReviewLine.Validate("Approved Hours", Hours);
        ReviewLine.Modify(true);
    end;

    local procedure ApproveAllLogged(ReviewNo: Integer)
    var
        ReviewLine: Record "BCJ Customer Review Line";
    begin
        ReviewLine.SetRange("Review No.", ReviewNo);
        ReviewLine.FindSet();
        repeat
            ReviewLine.Validate("Approved Hours", ReviewLine."Logged Hours");
            ReviewLine.Modify(true);
        until ReviewLine.Next() = 0;
    end;

    local procedure GetEntry(Suffix: Text; var TimeEntry: Record "BCJ Project Time Entry")
    begin
        TimeEntry.Get(JiraId(Suffix), CopyStr('I-' + JiraId(Suffix), 1, 50));
    end;

    local procedure SetEntryStatus(Suffix: Text; Status: Enum "BCJ Billing Status")
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        GetEntry(Suffix, TimeEntry);
        TimeEntry.Validate("Billing Status", Status);
        TimeEntry.Modify(true);
    end;

    local procedure SetBillableHours(Suffix: Text; Hours: Decimal)
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        // Direct assignment: the fixture is standing in for an allocation a review already made,
        // without running the review itself.
        GetEntry(Suffix, TimeEntry);
        TimeEntry."Billable Hours" := Hours;
        TimeEntry.Modify(false);
    end;

    local procedure GetBillableHours(Suffix: Text): Decimal
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        GetEntry(Suffix, TimeEntry);
        exit(TimeEntry."Billable Hours");
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

    local procedure AssertEntry(Suffix: Text; ExpectedStatus: Enum "BCJ Billing Status"; ExpectedBillableHours: Decimal; ExpectedReviewNo: Integer; Msg: Text)
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        GetEntry(Suffix, TimeEntry);
        Assert.AreEqual(ExpectedStatus, TimeEntry."Billing Status", Msg + ' (billing status)');
        Assert.AreEqual(ExpectedBillableHours, TimeEntry."Billable Hours", Msg + ' (billable hours)');
        Assert.AreEqual(ExpectedReviewNo, TimeEntry."Review No.", Msg + ' (review no.)');
    end;

    local procedure AssertHours(Buffer: Record "BCJ Billing Overview Buffer" temporary; Total: Decimal; OpenHours: Decimal; SentForReview: Decimal; Billable: Decimal; NotBillable: Decimal; Billed: Decimal; Unbilled: Decimal; LineName: Text)
    begin
        Assert.AreEqual(Total, Buffer."Total Hours", LineName + ': Total Hours must equal every logged hour beneath it');
        Assert.AreEqual(OpenHours, Buffer."Open Hours", LineName + ': Open Hours must equal the hours nobody has decided on yet');
        Assert.AreEqual(SentForReview, Buffer."Sent for Review Hours", LineName + ': Sent for Review Hours must equal the hours waiting on a customer answer');
        Assert.AreEqual(Billable, Buffer."Billable Hours", LineName + ': Billable Hours must equal the hours agreed for invoicing and not yet invoiced');
        Assert.AreEqual(NotBillable, Buffer."Not Billable Hours", LineName + ': Not Billable Hours must equal the hours that will never be charged');
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
