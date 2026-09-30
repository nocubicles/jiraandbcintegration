codeunit 50107 "BCJ Customer Review Mgt."
{
    var
        NothingToSendErr: Label 'The selected lines contain no open hours to send for customer review.';
        ApprovedHoursOutOfRangeErr: Label 'The approved hours must be between 0 and %1.', Comment = '%1 = hours to bill on the line';
        PctOutOfRangeErr: Label 'The percentage must be between 0 and 100.';
        NothingLeftToSendErr: Label 'Every task of this review has 0 hours to bill. Cancel the review instead.';
        ReopenNotPossibleErr: Label 'Task %1 cannot be reopened: only %2 of its %3 hours to bill are still available. Cancel the draft review holding them or mark the written-off hours Open first.', Comment = '%1 = project task no., %2 = hours available, %3 = hours to bill';
        CannotCancelErr: Label 'Only a draft review or a review waiting for an answer can be cancelled.';

    /// <summary>
    /// Reserves the Open hours of the time entries within the filters and marks of TimeEntry in a Draft review per project,
    /// one line per task. Hours are added to the project's existing Draft instead of creating a second one. Fills TempReview
    /// with each review created or extended and returns how many. Errors before writing anything when the review base URL
    /// is not configured or when no Open hours are selected.
    /// </summary>
    procedure CreateReviews(var TimeEntry: Record "BCJ Project Time Entry"; var TempReview: Record "BCJ Customer Review" temporary): Integer
    var
        TempOpenEntry: Record "BCJ Project Time Entry" temporary;
        ReviewMail: Codeunit "BCJ Review Mail";
        CreatedCount: Integer;
    begin
        ReviewMail.CheckSetup();

        // First pass: collect the entries with Open hours without touching the caller's filters or marks.
        if TimeEntry.FindSet() then
            repeat
                if TimeEntry."Open Hours" > 0 then begin
                    TempOpenEntry := TimeEntry;
                    TempOpenEntry.Insert();
                end;
            until TimeEntry.Next() = 0;
        if TempOpenEntry.IsEmpty() then
            Error(NothingToSendErr);

        // Second pass: one draft per project, one line per task.
        TempOpenEntry.SetCurrentKey("Project No.", "Project Task No.", "Posting Date");
        TempOpenEntry.FindSet();
        repeat
            TempOpenEntry.SetRange("Project No.", TempOpenEntry."Project No.");
            if ReserveInDraft(TempOpenEntry, TempReview) then
                CreatedCount += 1;
            TempOpenEntry.FindLast();
            TempOpenEntry.SetRange("Project No.");
        until TempOpenEntry.Next() = 0;
        exit(CreatedCount);
    end;

    local procedure ReserveInDraft(var TempOpenEntry: Record "BCJ Project Time Entry" temporary; var TempReview: Record "BCJ Customer Review" temporary): Boolean
    var
        Review: Record "BCJ Customer Review";
        ReviewLine: Record "BCJ Customer Review Line";
        TimeEntry: Record "BCJ Project Time Entry";
        JobTask: Record "Job Task";
        HourAllocationMgt: Codeunit "BCJ Hour Allocation Mgt.";
        Added: Decimal;
        NewLogged: Decimal;
    begin
        FindOrCreateDraft(TempOpenEntry."Project No.", Review);

        TempOpenEntry.FindSet();
        repeat
            TimeEntry.Get(TempOpenEntry."Jira ID", TempOpenEntry."Jira Issue Id");
            if HourAllocationMgt.ReserveOpenHours(TimeEntry, Review."Review No.") > 0 then begin
                if not ReviewLine.Get(Review."Review No.", TempOpenEntry."Project Task No.") then begin
                    ReviewLine.Init();
                    ReviewLine."Review No." := Review."Review No.";
                    ReviewLine."Project Task No." := TempOpenEntry."Project Task No.";
                    JobTask.SetLoadFields(Description);
                    if JobTask.Get(TempOpenEntry."Project No.", TempOpenEntry."Project Task No.") then
                        ReviewLine."Task Description" := JobTask.Description;
                    ReviewLine.Insert(false);
                end;
            end;
        until TempOpenEntry.Next() = 0;

        // Jira logs seconds, so summed hours carry many decimals; the customer sees two. Hours to Bill starts at
        // everything in review and grows with hours added to the draft; the user lowers it before sending.
        ReviewLine.Reset();
        ReviewLine.SetRange("Review No.", Review."Review No.");
        if ReviewLine.FindSet(true) then
            repeat
                NewLogged := Round(HourAllocationMgt.InReviewOnTask(Review."Review No.", ReviewLine."Project Task No."), 0.01);
                ReviewLine."Entry Count" := HourAllocationMgt.CountReviewWorklogs(Review."Review No.", ReviewLine."Project Task No.");
                Added := NewLogged - ReviewLine."Logged Hours";
                ReviewLine."Logged Hours" := NewLogged;
                ReviewLine."Hours to Bill" += Added;
                if ReviewLine."Hours to Bill" > ReviewLine."Logged Hours" then
                    ReviewLine."Hours to Bill" := ReviewLine."Logged Hours";
                if ReviewLine."Hours to Bill" < 0 then
                    ReviewLine."Hours to Bill" := 0;
                SetTaskSnapshot(ReviewLine, Review."Project No.");
                ReviewLine.Modify(false);
            until ReviewLine.Next() = 0;

        if TempReview.Get(Review."Review No.") then
            exit(false);
        TempReview := Review;
        TempReview.Insert();
        exit(true);
    end;

    local procedure FindOrCreateDraft(ProjectNo: Code[20]; var Review: Record "BCJ Customer Review")
    var
        Job: Record Job;
    begin
        Review.Reset();
        // Serialise draft creation so two sessions cannot each create a draft for the same project.
        Review.LockTable();
        Review.SetCurrentKey("Project No.", Status);
        Review.SetRange("Project No.", ProjectNo);
        Review.SetRange(Status, Review.Status::Draft);
        if Review.FindFirst() then
            exit;
        Review.Reset();
        Review.Init();
        Review."Project No." := ProjectNo;
        Job.SetLoadFields("Bill-to Customer No.");
        if Job.Get(ProjectNo) then
            Review."Customer No." := Job."Bill-to Customer No.";
        Review.Status := Review.Status::Draft;
        Review."Access Token" := NewAccessToken();
        Review.Insert(true);
    end;

    /// <summary>
    /// Captures the task's whole history on the line, over every worklog of the project task (this review included):
    /// billed = Billed and Billable hours, not billable = written-off hours, not billed = the rest (Open and in review).
    /// </summary>
    local procedure SetTaskSnapshot(var ReviewLine: Record "BCJ Customer Review Line"; ProjectNo: Code[20])
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        TimeEntry.SetRange("Project No.", ProjectNo);
        TimeEntry.SetRange("Project Task No.", ReviewLine."Project Task No.");
        TimeEntry.CalcSums("Time Spent in Hours", "Billable Hours", "Billed Hours", "Not Billable Hours");
        // Round each figure first and derive Not Billed, so the four always add up exactly.
        ReviewLine."Task Logged Hours" := Round(TimeEntry."Time Spent in Hours", 0.01);
        ReviewLine."Task Billed Hours" := Round(TimeEntry."Billable Hours" + TimeEntry."Billed Hours", 0.01);
        ReviewLine."Task Not Billable Hours" := Round(TimeEntry."Not Billable Hours", 0.01);
        ReviewLine."Task Not Billed Hours" := ReviewLine."Task Logged Hours" - ReviewLine."Task Billed Hours" - ReviewLine."Task Not Billable Hours";
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
    /// Sends a Draft review: per task the hours cut from Hours to Bill return to Open (the oldest hours stay in review),
    /// tasks with nothing to bill are dropped, the review becomes Sent and is e-mailed. Returns whether an e-mail was sent;
    /// without a recipient the review is still Sent and its link can be shared by hand.
    /// </summary>
    procedure SendReview(var Review: Record "BCJ Customer Review"): Boolean
    var
        ReviewLine: Record "BCJ Customer Review Line";
        HourAllocationMgt: Codeunit "BCJ Hour Allocation Mgt.";
        ReviewMail: Codeunit "BCJ Review Mail";
    begin
        Review.TestField(Status, Review.Status::Draft);
        ReviewLine.SetRange("Review No.", Review."Review No.");
        if ReviewLine.FindSet(true) then
            repeat
                // The Jira sync may have shortened worklogs since the draft was made.
                ReviewLine."Logged Hours" := Round(HourAllocationMgt.InReviewOnTask(Review."Review No.", ReviewLine."Project Task No."), 0.01);
                if ReviewLine."Hours to Bill" > ReviewLine."Logged Hours" then
                    ReviewLine."Hours to Bill" := ReviewLine."Logged Hours";
                HourAllocationMgt.ReleaseExcess(Review."Review No.", ReviewLine."Project Task No.", ReviewLine."Hours to Bill");
                if ReviewLine."Hours to Bill" = 0 then
                    ReviewLine.Delete(false)
                else begin
                    SetTaskSnapshot(ReviewLine, Review."Project No.");
                    ReviewLine.Modify(false);
                end;
            until ReviewLine.Next() = 0;
        if ReviewLine.IsEmpty() then
            Error(NothingLeftToSendErr);
        Review.Status := Review.Status::Sent;
        Review."Sent On" := CurrentDateTime();
        Review.Modify(true);
        exit(ReviewMail.SendReviewEmail(Review));
    end;

    /// <summary>
    /// Sends every Draft review in TempReview and e-mails the ones already Sent again. Returns the number of e-mails sent.
    /// Reviews without a recipient are not e-mailed; a failed send never raises an error.
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
                    case Review.Status of
                        Review.Status::Draft:
                            if SendReview(Review) then
                                SentCount += 1;
                        Review.Status::Sent:
                            if ReviewMail.SendReviewEmail(Review) then
                                SentCount += 1;
                    end;
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
                if (ReviewLine."Approved Hours" < 0) or (ReviewLine."Approved Hours" > ReviewLine."Hours to Bill") then
                    Error(ApprovedHoursOutOfRangeErr, ReviewLine."Hours to Bill");
            until ReviewLine.Next() = 0;
        Review.Status := Review.Status::Answered;
        Review."Answered On" := CurrentDateTime();
        Review.Modify(true);
        ApplyAnswer(Review);
    end;

    /// <summary>
    /// Applies the approved hours of each line to the task's hours in this review, oldest first: approved hours become
    /// Billable and every hour not approved returns to Open. Applied Hours shows what could be applied.
    /// </summary>
    procedure ApplyAnswer(var Review: Record "BCJ Customer Review")
    var
        ReviewLine: Record "BCJ Customer Review Line";
        HourAllocationMgt: Codeunit "BCJ Hour Allocation Mgt.";
    begin
        Review.TestField(Status, Review.Status::Answered);
        ReviewLine.SetRange("Review No.", Review."Review No.");
        if ReviewLine.FindSet() then
            repeat
                ReviewLine."Applied Hours" := HourAllocationMgt.ApproveReviewHours(Review."Review No.", ReviewLine."Project Task No.", ReviewLine."Approved Hours");
                ReviewLine.Modify(false);
            until ReviewLine.Next() = 0;
        // Hours still in review on a task without a line cannot be approved: return them to Open too.
        HourAllocationMgt.ReleaseReview(Review."Review No.");
    end;

    /// <summary>
    /// Cancels a Draft review or one waiting for an answer. Its hours in review return to Open.
    /// </summary>
    procedure CancelReview(var Review: Record "BCJ Customer Review")
    var
        HourAllocationMgt: Codeunit "BCJ Hour Allocation Mgt.";
    begin
        if not (Review.Status in [Review.Status::Draft, Review.Status::Sent]) then
            Error(CannotCancelErr);
        HourAllocationMgt.ReleaseReview(Review."Review No.");
        Review.Status := Review.Status::Cancelled;
        Review."Cancelled On" := CurrentDateTime();
        Review.Modify(true);
    end;

    /// <summary>
    /// Reopens an answered review so the customer can adjust the answer: its approved hours go back into review and are
    /// topped up from its worklogs' Open hours to each task's Hours to Bill. Billed hours stay billed. Errors, changing
    /// nothing, when a task cannot get its hours back. Approved hours and comments are kept.
    /// </summary>
    procedure ReopenReview(var Review: Record "BCJ Customer Review")
    var
        ReviewLine: Record "BCJ Customer Review Line";
        HourAllocationMgt: Codeunit "BCJ Hour Allocation Mgt.";
        Reached: Decimal;
    begin
        Review.TestField(Status, Review.Status::Answered);
        ReviewLine.SetRange("Review No.", Review."Review No.");
        if ReviewLine.FindSet(true) then
            repeat
                Reached := HourAllocationMgt.ReReserveReview(Review."Review No.", ReviewLine."Project Task No.", ReviewLine."Hours to Bill");
                // Hours to Bill is rounded to 0.01, so allow for the rounding.
                if Reached < ReviewLine."Hours to Bill" - 0.005 then
                    Error(ReopenNotPossibleErr, ReviewLine."Project Task No.", Round(Reached, 0.01), ReviewLine."Hours to Bill");
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
    /// Fills TempReview with the Draft and Sent reviews that hold hours of the time entries within the filters of
    /// TimeEntry, each once, and returns how many there are. TempReview is emptied first.
    /// Only filters are honoured, not marks: pass a filtered record, not a MarkedOnly selection.
    /// </summary>
    procedure GetOpenReviews(var TimeEntry: Record "BCJ Project Time Entry"; var TempReview: Record "BCJ Customer Review" temporary): Integer
    var
        EntryInFilter: Record "BCJ Project Time Entry";
        Allocation: Record "BCJ Time Entry Allocation";
        Review: Record "BCJ Customer Review";
        TempSeenReview: Record "BCJ Customer Review" temporary;
    begin
        TempReview.Reset();
        TempReview.DeleteAll(false);
        // Work on a copy so the caller's record keeps its position; the caller's filters still apply.
        EntryInFilter.CopyFilters(TimeEntry);
        EntryInFilter.SetFilter("In Review Hours", '<>0');
        EntryInFilter.SetLoadFields("Jira ID", "Jira Issue Id");
        if EntryInFilter.FindSet() then
            repeat
                Allocation.SetRange("Jira ID", EntryInFilter."Jira ID");
                Allocation.SetRange("Jira Issue Id", EntryInFilter."Jira Issue Id");
                Allocation.SetFilter("In Review Hours", '<>0');
                if Allocation.FindSet() then
                    repeat
                        // Each review is read once, whether it turns out open or not.
                        if not TempSeenReview.Get(Allocation."Review No.") then begin
                            TempSeenReview."Review No." := Allocation."Review No.";
                            TempSeenReview.Insert(false);
                            if Review.Get(Allocation."Review No.") then
                                if Review.Status in [Review.Status::Draft, Review.Status::Sent] then begin
                                    TempReview := Review;
                                    TempReview.Insert(false);
                                end;
                        end;
                    until Allocation.Next() = 0;
            until EntryInFilter.Next() = 0;
        exit(TempReview.Count());
    end;

    /// <summary>
    /// Sets Hours to Bill on every line of a Draft review to Pct percent of the line's hours in review, rounded to 0.01.
    /// Pct must be between 0 and 100.
    /// </summary>
    procedure SetHoursToBillPct(var Review: Record "BCJ Customer Review"; Pct: Decimal)
    var
        ReviewLine: Record "BCJ Customer Review Line";
    begin
        Review.TestField(Status, Review.Status::Draft);
        if (Pct < 0) or (Pct > 100) then
            Error(PctOutOfRangeErr);
        ReviewLine.SetRange("Review No.", Review."Review No.");
        if ReviewLine.FindSet(true) then
            repeat
                ReviewLine.Validate("Hours to Bill", Round(ReviewLine."Logged Hours" * Pct / 100, 0.01));
                ReviewLine.Modify(true);
            until ReviewLine.Next() = 0;
    end;
}
