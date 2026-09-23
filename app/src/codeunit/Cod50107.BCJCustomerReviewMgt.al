codeunit 50107 "BCJ Customer Review Mgt."
{
    var
        NothingToSendErr: Label 'The selected lines contain no open time entries to send for customer review.';
        ApprovedHoursOutOfRangeErr: Label 'The approved hours must be between 0 and %1.', Comment = '%1 = logged hours on the line';

    /// <summary>
    /// Creates one review per Project No. from the Open time entries within the filters and marks of TimeEntry.
    /// Entries in any other status are ignored. Fills TempReview with a copy of each created review and returns the number created.
    /// Errors before writing anything when the review base URL is not configured or when no Open entry is in range.
    /// </summary>
    procedure CreateReviews(var TimeEntry: Record "BCJ Project Time Entry"; var TempReview: Record "BCJ Customer Review" temporary): Integer
    var
        TempOpenEntry: Record "BCJ Project Time Entry" temporary;
        ReviewMail: Codeunit "BCJ Review Mail";
        CreatedCount: Integer;
    begin
        ReviewMail.CheckSetup();

        // First pass: collect the Open entries without touching the caller's filters or marks.
        if TimeEntry.FindSet() then
            repeat
                if TimeEntry."Billing Status" = TimeEntry."Billing Status"::Open then begin
                    TempOpenEntry := TimeEntry;
                    TempOpenEntry.Insert();
                end;
            until TimeEntry.Next() = 0;
        if TempOpenEntry.IsEmpty() then
            Error(NothingToSendErr);

        // Second pass: one review per project, one line per task.
        TempOpenEntry.SetCurrentKey("Project No.", "Project Task No.", "Posting Date");
        TempOpenEntry.FindSet();
        repeat
            TempOpenEntry.SetRange("Project No.", TempOpenEntry."Project No.");
            CreateReviewForProject(TempOpenEntry, TempReview);
            CreatedCount += 1;
            TempOpenEntry.FindLast();
            TempOpenEntry.SetRange("Project No.");
        until TempOpenEntry.Next() = 0;
        exit(CreatedCount);
    end;

    local procedure CreateReviewForProject(var TempOpenEntry: Record "BCJ Project Time Entry" temporary; var TempReview: Record "BCJ Customer Review" temporary)
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        TimeEntry: Record "BCJ Project Time Entry";
        Job: Record Job;
        JobTask: Record "Job Task";
    begin
        Review.Init();
        Review."Project No." := TempOpenEntry."Project No.";
        Job.SetLoadFields("Bill-to Customer No.");
        if Job.Get(TempOpenEntry."Project No.") then
            Review."Customer No." := Job."Bill-to Customer No.";
        Review.Status := Review.Status::Sent;
        Review."Access Token" := NewAccessToken();
        Review.Insert(true);

        TempOpenEntry.FindSet();
        repeat
            if not ReviewLine.Get(Review."Review No.", TempOpenEntry."Project Task No.") then begin
                ReviewLine.Init();
                ReviewLine."Review No." := Review."Review No.";
                ReviewLine."Project Task No." := TempOpenEntry."Project Task No.";
                JobTask.SetLoadFields(Description);
                if JobTask.Get(TempOpenEntry."Project No.", TempOpenEntry."Project Task No.") then
                    ReviewLine."Task Description" := JobTask.Description;
                ReviewLine.Insert(true);
            end;
            ReviewLine."Logged Hours" += TempOpenEntry."Time Spent in Hours";
            ReviewLine."Entry Count" += 1;
            ReviewLine.Modify(false);

            TimeEntry.Get(TempOpenEntry."Jira ID", TempOpenEntry."Jira Issue Id");
            TimeEntry.Validate("Billing Status", TimeEntry."Billing Status"::"Sent for Review");
            TimeEntry."Review No." := Review."Review No.";
            TimeEntry.Modify(true);
        until TempOpenEntry.Next() = 0;

        // Jira logs minutes, so summed hours carry many decimals. The customer sees and answers two decimals,
        // and the approved hours are validated against this value, so round it once here.
        ReviewLine.Reset();
        ReviewLine.SetRange("Review No.", Review."Review No.");
        if ReviewLine.FindSet(true) then
            repeat
                ReviewLine."Logged Hours" := Round(ReviewLine."Logged Hours", 0.01);
                ReviewLine.Modify(false);
            until ReviewLine.Next() = 0;

        TempReview := Review;
        TempReview.Insert();
    end;

    local procedure NewAccessToken(): Text[50]
    var
        Review: Record "BCJ Customer Review";
        Token: Text[50];
    begin
        repeat
            Token := CopyStr(DelChr(Format(CreateGuid()), '=', '{}-'), 1, MaxStrLen(Token));
            Review.SetRange("Access Token", Token);
        until Review.IsEmpty();
        exit(Token);
    end;

    /// <summary>
    /// Sends the review e-mail for every review in TempReview. Returns the number of e-mails sent.
    /// Reviews without a recipient are skipped; a failed send never raises an error.
    /// </summary>
    procedure SendReviews(var TempReview: Record "BCJ Customer Review" temporary): Integer
    var
        Review: Record "BCJ Customer Review";
        ReviewMail: Codeunit "BCJ Review Mail";
        SentCount: Integer;
    begin
        if TempReview.FindSet() then
            repeat
                if Review.Get(TempReview."Review No.") then
                    if ReviewMail.SendReviewEmail(Review) then
                        SentCount += 1;
            until TempReview.Next() = 0;
        exit(SentCount);
    end;

    /// <summary>
    /// Records the customer's answer: sets the review to Answered and applies the approved hours to the time entries.
    /// Only a review that is Sent can be submitted.
    /// </summary>
    procedure SubmitReview(var Review: Record "BCJ Customer Review")
    var
        ReviewLine: Record "BCJ Customer Review Line";
    begin
        Review.TestField(Status, Review.Status::Sent);
        // Defence in depth: the API writes lines directly, so re-check the range before deciding anything.
        ReviewLine.SetRange("Review No.", Review."Review No.");
        if ReviewLine.FindSet() then
            repeat
                if (ReviewLine."Approved Hours" < 0) or (ReviewLine."Approved Hours" > ReviewLine."Logged Hours") then
                    Error(ApprovedHoursOutOfRangeErr, ReviewLine."Logged Hours");
            until ReviewLine.Next() = 0;
        Review.Status := Review.Status::Answered;
        Review."Answered On" := CurrentDateTime();
        Review.Modify(true);
        ApplyAnswer(Review);
    end;

    /// <summary>
    /// Allocates the approved hours of each line onto that task's entries that are Sent for Review, oldest first.
    /// Entries that receive hours become Billable, the rest Not Billable. Approved hours that find no entry are dropped
    /// and the gap is visible as Applied Hours below Approved Hours.
    /// </summary>
    procedure ApplyAnswer(var Review: Record "BCJ Customer Review")
    var
        ReviewLine: Record "BCJ Customer Review Line";
        TimeEntry: Record "BCJ Project Time Entry";
        Remaining: Decimal;
        Give: Decimal;
    begin
        Review.TestField(Status, Review.Status::Answered);
        ReviewLine.SetRange("Review No.", Review."Review No.");
        if not ReviewLine.FindSet() then
            exit;
        repeat
            Remaining := ReviewLine."Approved Hours";
            TimeEntry.Reset();
            TimeEntry.SetCurrentKey("Review No.", "Project Task No.", "Posting Date", "Jira ID");
            TimeEntry.SetRange("Review No.", Review."Review No.");
            TimeEntry.SetRange("Project Task No.", ReviewLine."Project Task No.");
            TimeEntry.SetRange("Billing Status", TimeEntry."Billing Status"::"Sent for Review");
            if TimeEntry.FindSet(true) then
                repeat
                    Give := Remaining;
                    if Give > TimeEntry."Time Spent in Hours" then
                        Give := TimeEntry."Time Spent in Hours";
                    if Give < 0 then
                        Give := 0;
                    Remaining -= Give;
                    TimeEntry."Billable Hours" := Give;
                    if Give > 0 then
                        TimeEntry.Validate("Billing Status", TimeEntry."Billing Status"::Billable)
                    else
                        TimeEntry.Validate("Billing Status", TimeEntry."Billing Status"::"Not Billable");
                    TimeEntry.Modify(true);
                until TimeEntry.Next() = 0;
            ReviewLine."Applied Hours" := ReviewLine."Approved Hours" - Remaining;
            ReviewLine.Modify(false);
        until ReviewLine.Next() = 0;
    end;

    /// <summary>
    /// Cancels a review that is still waiting for an answer. Its entries that are still Sent for Review go back to Open.
    /// </summary>
    procedure CancelReview(var Review: Record "BCJ Customer Review")
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        Review.TestField(Status, Review.Status::Sent);
        TimeEntry.SetRange("Review No.", Review."Review No.");
        TimeEntry.SetRange("Billing Status", TimeEntry."Billing Status"::"Sent for Review");
        if TimeEntry.FindSet(true) then
            repeat
                TimeEntry.Validate("Billing Status", TimeEntry."Billing Status"::Open);
                TimeEntry."Billable Hours" := TimeEntry."Time Spent in Hours";
                TimeEntry."Review No." := 0;
                TimeEntry.Modify(true);
            until TimeEntry.Next() = 0;
        Review.Status := Review.Status::Cancelled;
        Review."Cancelled On" := CurrentDateTime();
        Review.Modify(true);
    end;

    /// <summary>
    /// Reopens an answered review so the customer can adjust the answer. Undoes the allocation on entries that are
    /// Billable or Not Billable (entries already Billed are left alone) and keeps the approved hours and comments.
    /// </summary>
    procedure ReopenReview(var Review: Record "BCJ Customer Review")
    var
        ReviewLine: Record "BCJ Customer Review Line";
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        Review.TestField(Status, Review.Status::Answered);
        TimeEntry.SetRange("Review No.", Review."Review No.");
        TimeEntry.SetFilter("Billing Status", '%1|%2', TimeEntry."Billing Status"::Billable, TimeEntry."Billing Status"::"Not Billable");
        if TimeEntry.FindSet(true) then
            repeat
                TimeEntry.Validate("Billing Status", TimeEntry."Billing Status"::"Sent for Review");
                TimeEntry."Billable Hours" := TimeEntry."Time Spent in Hours";
                TimeEntry.Modify(true);
            until TimeEntry.Next() = 0;
        ReviewLine.SetRange("Review No.", Review."Review No.");
        if ReviewLine.FindSet(true) then
            repeat
                ReviewLine."Applied Hours" := 0;
                ReviewLine.Modify(false);
            until ReviewLine.Next() = 0;
        Review.Status := Review.Status::Sent;
        Review."Answered On" := 0DT;
        Review.Modify(true);
    end;

    /// <summary>
    /// Finds the review with the given access token. Returns false when the token is blank or unknown.
    /// </summary>
    procedure FindByToken(AccessToken: Text; var Review: Record "BCJ Customer Review"): Boolean
    begin
        if AccessToken = '' then
            exit(false);
        Review.Reset();
        Review.SetRange("Access Token", CopyStr(AccessToken, 1, MaxStrLen(Review."Access Token")));
        exit(Review.FindFirst());
    end;

    /// <summary>
    /// Fills TempReview with the reviews still waiting for an answer (Status Sent) that the time entries within the
    /// filters of TimeEntry belong to, each once, and returns how many there are. TempReview is emptied first.
    /// Entries without a review and reviews that are answered or cancelled are ignored.
    /// Only filters are honoured, not marks: pass a filtered record, not a MarkedOnly selection.
    /// </summary>
    procedure GetOpenReviews(var TimeEntry: Record "BCJ Project Time Entry"; var TempReview: Record "BCJ Customer Review" temporary): Integer
    var
        EntryInFilter: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
        TempSeenReview: Record "BCJ Customer Review" temporary;
    begin
        TempReview.Reset();
        TempReview.DeleteAll(false);
        // Work on a copy so the caller's record keeps its position; the caller's filters still apply.
        EntryInFilter.CopyFilters(TimeEntry);
        EntryInFilter.SetFilter("Review No.", '<>0');
        EntryInFilter.SetLoadFields("Review No.");
        if EntryInFilter.FindSet() then
            repeat
                // Each review is read once, whether it turns out open or not.
                if not TempSeenReview.Get(EntryInFilter."Review No.") then begin
                    TempSeenReview."Review No." := EntryInFilter."Review No.";
                    TempSeenReview.Insert(false);
                    if Review.Get(EntryInFilter."Review No.") then
                        if Review.Status = Review.Status::Sent then begin
                            TempReview := Review;
                            TempReview.Insert(false);
                        end;
                end;
            until EntryInFilter.Next() = 0;
        exit(TempReview.Count());
    end;
}
