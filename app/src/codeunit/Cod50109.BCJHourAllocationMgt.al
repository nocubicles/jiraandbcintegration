codeunit 50109 "BCJ Hour Allocation Mgt."
{
    // The only writer of "BCJ Time Entry Allocation" rows and of the bucket cache on "BCJ Project Time Entry".
    // Contract: tasks/hour-allocation-contract.md.
    Permissions = tabledata "BCJ Time Entry Allocation" = RIMD,
                  tabledata "BCJ Project Time Entry" = RM;

    var
        SentForReviewNotAllowedErr: Label 'Hours are put into review only by a customer review. Use Send for Customer Review instead.';

    /// <summary>
    /// Sets the bucket cache, Unbilled Hours, the derived Billing Status and the legacy flags of TimeEntry from its
    /// allocation rows. Open Hours is the logged hours minus everything allocated. Does not modify the record.
    /// </summary>
    procedure RecalcEntry(var TimeEntry: Record "BCJ Project Time Entry")
    var
        Allocation: Record "BCJ Time Entry Allocation";
        NewStatus: Enum "BCJ Billing Status";
    begin
        Allocation.SetRange("Jira ID", TimeEntry."Jira ID");
        Allocation.SetRange("Jira Issue Id", TimeEntry."Jira Issue Id");
        Allocation.CalcSums("In Review Hours", "Billable Hours", "Billed Hours", "Not Billable Hours");
        TimeEntry."In Review Hours" := Allocation."In Review Hours";
        TimeEntry."Billable Hours" := Allocation."Billable Hours";
        TimeEntry."Billed Hours" := Allocation."Billed Hours";
        TimeEntry."Not Billable Hours" := Allocation."Not Billable Hours";
        TimeEntry."Open Hours" := TimeEntry."Time Spent in Hours" - Allocation."In Review Hours" - Allocation."Billable Hours" - Allocation."Billed Hours" - Allocation."Not Billable Hours";
        // Jira logs seconds, so sums carry long decimals: never leave a sliver of an hour Open.
        if Abs(TimeEntry."Open Hours") < 0.005 then
            TimeEntry."Open Hours" := 0;
        TimeEntry."Unbilled Hours" := TimeEntry."Open Hours" + TimeEntry."In Review Hours" + TimeEntry."Billable Hours";

        // The status says what the worklog needs next.
        case true of
            TimeEntry."In Review Hours" > 0:
                NewStatus := NewStatus::"Sent for Review";
            TimeEntry."Open Hours" > 0:
                NewStatus := NewStatus::Open;
            TimeEntry."Billable Hours" > 0:
                NewStatus := NewStatus::Billable;
            TimeEntry."Billed Hours" > 0:
                NewStatus := NewStatus::Billed;
            TimeEntry."Not Billable Hours" > 0:
                NewStatus := NewStatus::"Not Billable";
            else
                NewStatus := NewStatus::Open;
        end;
        TimeEntry.Validate("Billing Status", NewStatus);
    end;

    /// <summary>
    /// Moves all Open hours of TimeEntry into its allocation row for ReviewNo and modifies the entry. Returns the hours moved.
    /// </summary>
    procedure ReserveOpenHours(var TimeEntry: Record "BCJ Project Time Entry"; ReviewNo: Integer): Decimal
    var
        Allocation: Record "BCJ Time Entry Allocation";
        OpenHours: Decimal;
    begin
        // Lock the worklog so two sessions cannot reserve the same hours.
        TimeEntry.ReadIsolation := IsolationLevel::UpdLock;
        TimeEntry.Get(TimeEntry."Jira ID", TimeEntry."Jira Issue Id");
        RecalcEntry(TimeEntry);
        OpenHours := TimeEntry."Open Hours";
        if OpenHours <= 0 then
            exit(0);
        GetOrInitRow(TimeEntry, ReviewNo, Allocation);
        Allocation."In Review Hours" += OpenHours;
        Allocation."Reserved Hours" += OpenHours;
        SaveRow(Allocation);
        TimeEntry."Review No." := ReviewNo;
        RecalcEntry(TimeEntry);
        TimeEntry.Modify(false);
        exit(OpenHours);
    end;

    /// <summary>
    /// Keeps up to KeepHours of the hours in review of ReviewNo on ProjectTaskNo, oldest first; the rest returns to Open.
    /// Returns the hours kept.
    /// </summary>
    procedure ReleaseExcess(ReviewNo: Integer; ProjectTaskNo: Code[20]; KeepHours: Decimal): Decimal
    var
        Allocation: Record "BCJ Time Entry Allocation";
        Touched: List of [Text];
        Remaining: Decimal;
        Keep: Decimal;
        Kept: Decimal;
    begin
        Remaining := ApplyRoundingRule(KeepHours, InReviewOnTask(ReviewNo, ProjectTaskNo));
        FilterReviewTask(Allocation, ReviewNo, ProjectTaskNo);
        if Allocation.FindSet(true) then
            repeat
                Keep := MinHours(Remaining, Allocation."In Review Hours");
                Remaining -= Keep;
                Kept += Keep;
                if Keep <> Allocation."In Review Hours" then begin
                    Allocation."In Review Hours" := Keep;
                    Allocation.Modify(false);
                    AddTouched(Touched, Allocation);
                end;
            until Allocation.Next() = 0;
        RecalcTouched(Touched);
        exit(Kept);
    end;

    /// <summary>
    /// Moves the hours in review of ReviewNo on ProjectTaskNo to Billable oldest first, up to ApprovedHours; hours of the
    /// review already Billed count as approved. Every hour left in review returns to Open. Returns the hours approved,
    /// Billed hours included (more than ApprovedHours when more was already invoiced).
    /// </summary>
    procedure ApproveReviewHours(ReviewNo: Integer; ProjectTaskNo: Code[20]; ApprovedHours: Decimal): Decimal
    var
        Allocation: Record "BCJ Time Entry Allocation";
        Touched: List of [Text];
        Remaining: Decimal;
        Give: Decimal;
        Applied: Decimal;
    begin
        FilterReviewTask(Allocation, ReviewNo, ProjectTaskNo);
        Allocation.CalcSums("Billed Hours");
        // Hours already invoiced stay invoiced: they count as applied even when a reopened answer approves less,
        // so Applied Hours above Approved Hours shows that a credit note is due.
        Applied := Allocation."Billed Hours";
        Remaining := ApplyRoundingRule(ApprovedHours - Applied, InReviewOnTask(ReviewNo, ProjectTaskNo));
        if Allocation.FindSet(true) then
            repeat
                if Allocation."In Review Hours" <> 0 then begin
                    Give := MinHours(Remaining, Allocation."In Review Hours");
                    Remaining -= Give;
                    Applied += Give;
                    Allocation."Billable Hours" += Give;
                    Allocation."In Review Hours" := 0;
                    Allocation.Modify(false);
                    AddTouched(Touched, Allocation);
                end;
            until Allocation.Next() = 0;
        RecalcTouched(Touched);
        exit(Applied);
    end;

    /// <summary>
    /// Returns every hour in review of ReviewNo to Open. Billable and Billed hours are untouched.
    /// </summary>
    procedure ReleaseReview(ReviewNo: Integer)
    var
        Allocation: Record "BCJ Time Entry Allocation";
        Touched: List of [Text];
    begin
        Allocation.SetRange("Review No.", ReviewNo);
        Allocation.SetFilter("In Review Hours", '<>0');
        if Allocation.FindSet(true) then
            repeat
                Allocation."In Review Hours" := 0;
                Allocation.Modify(false);
                AddTouched(Touched, Allocation);
            until Allocation.Next() = 0;
        RecalcTouched(Touched);
    end;

    /// <summary>
    /// For reopening an answered review: moves its Billable hours on ProjectTaskNo back to In Review, then takes Open hours
    /// of its worklogs oldest first (never more than each row reserved) until In Review + Billed reaches TargetHours.
    /// Returns the In Review + Billed reached.
    /// </summary>
    procedure ReReserveReview(ReviewNo: Integer; ProjectTaskNo: Code[20]; TargetHours: Decimal): Decimal
    var
        Allocation: Record "BCJ Time Entry Allocation";
        TimeEntry: Record "BCJ Project Time Entry";
        Touched: List of [Text];
        Reached: Decimal;
        Room: Decimal;
        Take: Decimal;
    begin
        FilterReviewTask(Allocation, ReviewNo, ProjectTaskNo);
        if Allocation.FindSet(true) then
            repeat
                if Allocation."Billable Hours" <> 0 then begin
                    Allocation."In Review Hours" += Allocation."Billable Hours";
                    Allocation."Billable Hours" := 0;
                    Allocation.Modify(false);
                    AddTouched(Touched, Allocation);
                end;
                Reached += Allocation."In Review Hours" + Allocation."Billed Hours";
            until Allocation.Next() = 0;
        RecalcTouched(Touched);

        if Allocation.FindSet(true) then
            repeat
                if Reached >= TargetHours then
                    exit(Reached);
                Room := Allocation."Reserved Hours" - Allocation."In Review Hours" - Allocation."Billable Hours" - Allocation."Billed Hours" - Allocation."Not Billable Hours";
                if TimeEntry.Get(Allocation."Jira ID", Allocation."Jira Issue Id") then begin
                    RecalcEntry(TimeEntry);
                    Take := MinHours(MinHours(Room, TimeEntry."Open Hours"), TargetHours - Reached);
                    if Take > 0 then begin
                        Allocation."In Review Hours" += Take;
                        Allocation.Modify(false);
                        Reached += Take;
                        RecalcEntry(TimeEntry);
                        TimeEntry.Modify(false);
                    end;
                end;
            until Allocation.Next() = 0;
        exit(Reached);
    end;

    /// <summary>
    /// Fits the allocation of TimeEntry to its (changed) logged hours. Growth becomes Open. When more is allocated than
    /// logged, cuts manual Not Billable, then In Review on Draft reviews, then In Review on Sent reviews, then manual
    /// Billable, then review Billable newest review first. Billed hours are never cut, so Open may end up negative.
    /// Recalculates TimeEntry without modifying it.
    /// </summary>
    procedure TrimToLoggedHours(var TimeEntry: Record "BCJ Project Time Entry")
    var
        Allocation: Record "BCJ Time Entry Allocation";
        Excess: Decimal;
        Step: Integer;
    begin
        FilterEntry(Allocation, TimeEntry);
        Allocation.SetFilter("Posting Date", '<>%1', TimeEntry."Posting Date");
        if not Allocation.IsEmpty() then
            Allocation.ModifyAll("Posting Date", TimeEntry."Posting Date", false);
        Allocation.SetRange("Posting Date");

        Allocation.CalcSums("In Review Hours", "Billable Hours", "Billed Hours", "Not Billable Hours");
        Excess := Allocation."In Review Hours" + Allocation."Billable Hours" + Allocation."Billed Hours" + Allocation."Not Billable Hours" - TimeEntry."Time Spent in Hours";
        for Step := 1 to 5 do
            if Excess > 0 then
                Excess := CutStep(TimeEntry, Step, Excess);
        RecalcEntry(TimeEntry);
    end;

    /// <summary>
    /// Performs one overview decision on the manual row of TimeEntry and modifies it. Returns whether any hours moved.
    /// Billable / Not Billable take the Open hours; Billed bills every Billable hour; Open un-bills Billed hours back to
    /// Billable, or, when nothing is billed, returns manual Billable and Not Billable hours to Open.
    /// Hours in review and hours approved in a review are never taken by Billable, Not Billable or Open.
    /// </summary>
    procedure ApplyManualDecision(var TimeEntry: Record "BCJ Project Time Entry"; NewStatus: Enum "BCJ Billing Status"): Boolean
    var
        Allocation: Record "BCJ Time Entry Allocation";
        Changed: Boolean;
    begin
        CheckManualDecision(NewStatus);
        RecalcEntry(TimeEntry);
        case NewStatus of
            NewStatus::Billable, NewStatus::"Not Billable":
                if TimeEntry."Open Hours" > 0 then begin
                    GetOrInitRow(TimeEntry, 0, Allocation);
                    if NewStatus = NewStatus::Billable then
                        Allocation."Billable Hours" += TimeEntry."Open Hours"
                    else
                        Allocation."Not Billable Hours" += TimeEntry."Open Hours";
                    SaveRow(Allocation);
                    Changed := true;
                end;
            NewStatus::Billed:
                begin
                    FilterEntry(Allocation, TimeEntry);
                    Allocation.SetFilter("Billable Hours", '<>0');
                    if Allocation.FindSet(true) then
                        repeat
                            Allocation."Billed Hours" += Allocation."Billable Hours";
                            Allocation."Billable Hours" := 0;
                            Allocation.Modify(false);
                            Changed := true;
                        until Allocation.Next() = 0;
                end;
            NewStatus::Open:
                if TimeEntry."Billed Hours" <> 0 then begin
                    // One step back: an invoice undone leaves the hours approved.
                    FilterEntry(Allocation, TimeEntry);
                    Allocation.SetFilter("Billed Hours", '<>0');
                    if Allocation.FindSet(true) then
                        repeat
                            Allocation."Billable Hours" += Allocation."Billed Hours";
                            Allocation."Billed Hours" := 0;
                            Allocation.Modify(false);
                            Changed := true;
                        until Allocation.Next() = 0;
                end else
                    if Allocation.Get(TimeEntry."Jira ID", TimeEntry."Jira Issue Id", 0) then
                        if (Allocation."Billable Hours" <> 0) or (Allocation."Not Billable Hours" <> 0) then begin
                            Allocation."Billable Hours" := 0;
                            Allocation."Not Billable Hours" := 0;
                            SaveRow(Allocation);
                            Changed := true;
                        end;
        end;
        if Changed then begin
            RecalcEntry(TimeEntry);
            TimeEntry.Modify(false);
        end;
        exit(Changed);
    end;

    /// <summary>
    /// Errors when NewStatus cannot be set by an overview decision (hours go into review only through a customer review).
    /// </summary>
    procedure CheckManualDecision(NewStatus: Enum "BCJ Billing Status")
    begin
        if NewStatus = NewStatus::"Sent for Review" then
            Error(SentForReviewNotAllowedErr);
    end;

    /// <summary>
    /// Deletes the allocation rows of a worklog that is being deleted.
    /// </summary>
    procedure DeleteEntryRows(TimeEntry: Record "BCJ Project Time Entry")
    var
        Allocation: Record "BCJ Time Entry Allocation";
    begin
        FilterEntry(Allocation, TimeEntry);
        if not Allocation.IsEmpty() then
            Allocation.DeleteAll(false);
    end;

    /// <summary>
    /// Deletes the rows of ReviewNo that hold no hours (after a draft is released, before the review is deleted).
    /// </summary>
    procedure DeleteEmptyReviewRows(ReviewNo: Integer)
    var
        Allocation: Record "BCJ Time Entry Allocation";
    begin
        Allocation.SetRange("Review No.", ReviewNo);
        Allocation.SetRange("In Review Hours", 0);
        Allocation.SetRange("Billable Hours", 0);
        Allocation.SetRange("Billed Hours", 0);
        Allocation.SetRange("Not Billable Hours", 0);
        if not Allocation.IsEmpty() then
            Allocation.DeleteAll(false);
    end;

    /// <summary>
    /// Returns the number of worklogs of ProjectTaskNo that ReviewNo has reserved hours of.
    /// </summary>
    procedure CountReviewWorklogs(ReviewNo: Integer; ProjectTaskNo: Code[20]): Integer
    var
        Allocation: Record "BCJ Time Entry Allocation";
    begin
        FilterReviewTask(Allocation, ReviewNo, ProjectTaskNo);
        Allocation.SetFilter("Reserved Hours", '<>0');
        exit(Allocation.Count());
    end;

    /// <summary>
    /// Returns the hours in review of ReviewNo on ProjectTaskNo.
    /// </summary>
    procedure InReviewOnTask(ReviewNo: Integer; ProjectTaskNo: Code[20]): Decimal
    var
        Allocation: Record "BCJ Time Entry Allocation";
    begin
        FilterReviewTask(Allocation, ReviewNo, ProjectTaskNo);
        Allocation.CalcSums("In Review Hours");
        exit(Allocation."In Review Hours");
    end;

    /// <summary>
    /// One-time move from the per-worklog status model: builds allocation rows and the bucket cache from the old
    /// Billing Status, Billable Hours and Review No. Worklogs already in the new model are skipped, so it can run again.
    /// </summary>
    procedure MigrateLegacyEntries()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        EntryToModify: Record "BCJ Project Time Entry";
        Allocation: Record "BCJ Time Entry Allocation";
        Review: Record "BCJ Customer Review";
        ReviewShares: Dictionary of [Text, Decimal];
        SharedReviewTasks: Dictionary of [Text, Boolean];
        Logged: Decimal;
        Agreed: Decimal;
        Share: Decimal;
    begin
        if not TimeEntry.FindSet() then
            exit;
        repeat
            if IsLegacy(TimeEntry) then begin
                // Page 50100 of 1.1 only ticked the legacy flags; they became a status when the overview was opened.
                // Apply them first, as that sync did, so billing done there is not lost.
                if TimeEntry."Is Billed" and (TimeEntry."Billing Status" <> TimeEntry."Billing Status"::"Sent for Review") then
                    TimeEntry."Billing Status" := TimeEntry."Billing Status"::Billed
                else
                    if TimeEntry."Is Billable" and (TimeEntry."Billing Status" = TimeEntry."Billing Status"::Open) then
                        TimeEntry."Billing Status" := TimeEntry."Billing Status"::Billable;
                EntryToModify := TimeEntry;
                Logged := TimeEntry."Time Spent in Hours";
                Agreed := TimeEntry."Billable Hours";
                if Agreed > Logged then
                    Agreed := Logged;
                if Agreed < 0 then
                    Agreed := 0;
                case TimeEntry."Billing Status" of
                    TimeEntry."Billing Status"::"Sent for Review":
                        // Hours out with a customer stay in review up to the entry's oldest-first share of Hours to Bill.
                        if Review.Get(TimeEntry."Review No.") and (Review.Status = Review.Status::Sent) then begin
                            Share := LegacyReviewShare(TimeEntry, ReviewShares, SharedReviewTasks);
                            if Share >= 0 then begin
                                GetOrInitRow(TimeEntry, TimeEntry."Review No.", Allocation);
                                Allocation."Reserved Hours" := Logged;
                                Allocation."In Review Hours" := Share;
                                SaveRow(Allocation);
                            end;
                        end;
                    TimeEntry."Billing Status"::Billable, TimeEntry."Billing Status"::Billed, TimeEntry."Billing Status"::"Not Billable":
                        begin
                            GetOrInitRow(TimeEntry, TimeEntry."Review No.", Allocation);
                            if TimeEntry."Review No." <> 0 then
                                Allocation."Reserved Hours" := Logged;
                            case TimeEntry."Billing Status" of
                                TimeEntry."Billing Status"::Billable:
                                    Allocation."Billable Hours" := Agreed;
                                TimeEntry."Billing Status"::Billed:
                                    Allocation."Billed Hours" := Agreed;
                                TimeEntry."Billing Status"::"Not Billable":
                                    // What a customer did not approve returns to Open; a write-off made by hand stays.
                                    if TimeEntry."Review No." = 0 then
                                        Allocation."Not Billable Hours" := Logged;
                            end;
                            SaveRow(Allocation);
                        end;
                end;
                RecalcEntry(EntryToModify);
                EntryToModify.Modify(false);
            end;
        until TimeEntry.Next() = 0;
    end;

    local procedure IsLegacy(TimeEntry: Record "BCJ Project Time Entry"): Boolean
    var
        Allocation: Record "BCJ Time Entry Allocation";
    begin
        if (TimeEntry."Open Hours" <> 0) or (TimeEntry."In Review Hours" <> 0) or (TimeEntry."Unbilled Hours" <> 0) or
           (TimeEntry."Billed Hours" <> 0) or (TimeEntry."Not Billable Hours" <> 0)
        then
            exit(false);
        FilterEntry(Allocation, TimeEntry);
        exit(Allocation.IsEmpty());
    end;

    /// <summary>
    /// Returns the legacy entry's oldest-first share of its review line's Hours to Bill over the task's legacy entries
    /// in that review, or -1 when the review has no line for the task.
    /// </summary>
    local procedure LegacyReviewShare(TimeEntry: Record "BCJ Project Time Entry"; var ReviewShares: Dictionary of [Text, Decimal]; var SharedReviewTasks: Dictionary of [Text, Boolean]): Decimal
    var
        ReviewLine: Record "BCJ Customer Review Line";
        ReviewEntry: Record "BCJ Project Time Entry";
        ReviewTaskKey: Text;
        Remaining: Decimal;
        Share: Decimal;
    begin
        ReviewTaskKey := Format(TimeEntry."Review No.") + '|' + TimeEntry."Project Task No.";
        if not SharedReviewTasks.ContainsKey(ReviewTaskKey) then begin
            SharedReviewTasks.Add(ReviewTaskKey, true);
            if ReviewLine.Get(TimeEntry."Review No.", TimeEntry."Project Task No.") then begin
                ReviewEntry.SetCurrentKey("Review No.", "Project Task No.", "Posting Date", "Jira ID");
                ReviewEntry.SetRange("Review No.", TimeEntry."Review No.");
                ReviewEntry.SetRange("Project Task No.", TimeEntry."Project Task No.");
                ReviewEntry.SetRange("Billing Status", ReviewEntry."Billing Status"::"Sent for Review");
                ReviewEntry.CalcSums("Time Spent in Hours");
                Remaining := ApplyRoundingRule(ReviewLine."Hours to Bill", ReviewEntry."Time Spent in Hours");
                if ReviewEntry.FindSet() then
                    repeat
                        Share := MinHours(Remaining, ReviewEntry."Time Spent in Hours");
                        Remaining -= Share;
                        ReviewShares.Set(EntryKey(ReviewEntry."Jira ID", ReviewEntry."Jira Issue Id"), Share);
                    until ReviewEntry.Next() = 0;
            end;
        end;
        if ReviewShares.Get(EntryKey(TimeEntry."Jira ID", TimeEntry."Jira Issue Id"), Share) then
            exit(Share);
        exit(-1);
    end;

    local procedure CutStep(var TimeEntry: Record "BCJ Project Time Entry"; Step: Integer; Excess: Decimal): Decimal
    var
        Allocation: Record "BCJ Time Entry Allocation";
        Review: Record "BCJ Customer Review";
        Cut: Decimal;
    begin
        FilterEntry(Allocation, TimeEntry);
        // Newest review first within every step.
        Allocation.Ascending(false);
        if Allocation.FindSet(true) then
            repeat
                Cut := 0;
                case Step of
                    1:
                        if Allocation."Review No." = 0 then begin
                            Cut := MinHours(Excess, Allocation."Not Billable Hours");
                            Allocation."Not Billable Hours" -= Cut;
                        end;
                    2, 3:
                        if (Allocation."Review No." <> 0) and (Allocation."In Review Hours" > 0) then
                            if Review.Get(Allocation."Review No.") then
                                if (Review.Status = Review.Status::Draft) = (Step = 2) then begin
                                    Cut := MinHours(Excess, Allocation."In Review Hours");
                                    Allocation."In Review Hours" -= Cut;
                                end;
                    4:
                        if Allocation."Review No." = 0 then begin
                            Cut := MinHours(Excess, Allocation."Billable Hours");
                            Allocation."Billable Hours" -= Cut;
                        end;
                    5:
                        if Allocation."Review No." <> 0 then begin
                            Cut := MinHours(Excess, Allocation."Billable Hours");
                            Allocation."Billable Hours" -= Cut;
                        end;
                end;
                if Cut > 0 then begin
                    Excess -= Cut;
                    SaveRow(Allocation);
                end;
            until (Allocation.Next() = 0) or (Excess <= 0);
        exit(Excess);
    end;

    /// <summary>
    /// Hours to Bill is rounded to 0.01 from the hours in review, so asking for the rounded total means asking for all of it.
    /// </summary>
    local procedure ApplyRoundingRule(Hours: Decimal; TotalInReview: Decimal): Decimal
    begin
        if Hours >= Round(TotalInReview, 0.01) then
            exit(TotalInReview);
        exit(Hours);
    end;

    local procedure MinHours(A: Decimal; B: Decimal): Decimal
    var
        Result: Decimal;
    begin
        Result := A;
        if B < Result then
            Result := B;
        if Result < 0 then
            Result := 0;
        exit(Result);
    end;

    local procedure FilterEntry(var Allocation: Record "BCJ Time Entry Allocation"; TimeEntry: Record "BCJ Project Time Entry")
    begin
        Allocation.Reset();
        Allocation.SetRange("Jira ID", TimeEntry."Jira ID");
        Allocation.SetRange("Jira Issue Id", TimeEntry."Jira Issue Id");
    end;

    local procedure FilterReviewTask(var Allocation: Record "BCJ Time Entry Allocation"; ReviewNo: Integer; ProjectTaskNo: Code[20])
    begin
        Allocation.Reset();
        // Oldest first: posting date, then Jira ID (then the rest of the primary key).
        Allocation.SetCurrentKey("Review No.", "Project Task No.", "Posting Date", "Jira ID");
        Allocation.SetRange("Review No.", ReviewNo);
        Allocation.SetRange("Project Task No.", ProjectTaskNo);
    end;

    local procedure GetOrInitRow(TimeEntry: Record "BCJ Project Time Entry"; ReviewNo: Integer; var Allocation: Record "BCJ Time Entry Allocation")
    begin
        if Allocation.Get(TimeEntry."Jira ID", TimeEntry."Jira Issue Id", ReviewNo) then
            exit;
        Allocation.Init();
        Allocation."Jira ID" := TimeEntry."Jira ID";
        Allocation."Jira Issue Id" := TimeEntry."Jira Issue Id";
        Allocation."Review No." := ReviewNo;
        Allocation."Project No." := TimeEntry."Project No.";
        Allocation."Project Task No." := TimeEntry."Project Task No.";
        Allocation."Posting Date" := TimeEntry."Posting Date";
    end;

    /// <summary>
    /// Inserts or modifies the row. A manual row that holds nothing is deleted; review rows are kept for provenance.
    /// </summary>
    local procedure SaveRow(var Allocation: Record "BCJ Time Entry Allocation")
    var
        Existing: Record "BCJ Time Entry Allocation";
        IsEmptyRow: Boolean;
    begin
        IsEmptyRow := (Allocation."In Review Hours" = 0) and (Allocation."Billable Hours" = 0) and
                      (Allocation."Billed Hours" = 0) and (Allocation."Not Billable Hours" = 0);
        if Existing.Get(Allocation."Jira ID", Allocation."Jira Issue Id", Allocation."Review No.") then begin
            if IsEmptyRow and (Allocation."Review No." = 0) then
                Existing.Delete(false)
            else
                Allocation.Modify(false);
        end else
            if not (IsEmptyRow and (Allocation."Review No." = 0)) then
                Allocation.Insert(false);
    end;

    local procedure EntryKey(JiraId: Text; JiraIssueId: Text): Text
    begin
        exit(JiraId + '|' + JiraIssueId);
    end;

    local procedure AddTouched(var Touched: List of [Text]; Allocation: Record "BCJ Time Entry Allocation")
    var
        EntryId: Text;
    begin
        EntryId := EntryKey(Allocation."Jira ID", Allocation."Jira Issue Id");
        if not Touched.Contains(EntryId) then
            Touched.Add(EntryId);
    end;

    local procedure RecalcTouched(Touched: List of [Text])
    var
        TimeEntry: Record "BCJ Project Time Entry";
        EntryId: Text;
        Parts: List of [Text];
    begin
        foreach EntryId in Touched do begin
            Parts := EntryId.Split('|');
            if TimeEntry.Get(Parts.Get(1), Parts.Get(2)) then begin
                RecalcEntry(TimeEntry);
                TimeEntry.Modify(false);
            end;
        end;
    end;
}
