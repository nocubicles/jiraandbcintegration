codeunit 50104 "BCJ Billing Overview Mgt."
{
    var
        NoCustomerTxt: Label '(No customer)';

    /// <summary>
    /// Rebuilds Buffer as a Customer > Project > Task (> Time Entry) tree of the time entries within the filters of TimeEntryFilter.
    /// </summary>
    procedure BuildOverview(var Buffer: Record "BCJ Billing Overview Buffer" temporary; var TimeEntryFilter: Record "BCJ Project Time Entry"; IncludeTimeEntries: Boolean)
    var
        TempEntryLine: Record "BCJ Billing Overview Buffer" temporary;
        CurrCustomerNo: Code[20];
        CurrProjectNo: Code[20];
        CurrTaskNo: Code[20];
        CustomerLineNo: Integer;
        ProjectLineNo: Integer;
        TaskLineNo: Integer;
        NextLineNo: Integer;
        NewCustomer: Boolean;
        NewProject: Boolean;
    begin
        Buffer.Reset();
        Buffer.DeleteAll();

        CollectTimeEntries(TempEntryLine, TimeEntryFilter, IncludeTimeEntries);

        TempEntryLine.SetCurrentKey("Customer No.", "Project No.", "Project Task No.", "Posting Date", "Jira ID");
        if TempEntryLine.FindSet() then begin
            NewCustomer := true;
            repeat
                NewCustomer := NewCustomer or (TempEntryLine."Customer No." <> CurrCustomerNo);
                NewProject := NewCustomer or (TempEntryLine."Project No." <> CurrProjectNo);
                if NewCustomer then
                    CustomerLineNo := InsertGroupLine(Buffer, NextLineNo, TempEntryLine, "BCJ Overview Line Type"::Customer);
                if NewProject then
                    ProjectLineNo := InsertGroupLine(Buffer, NextLineNo, TempEntryLine, "BCJ Overview Line Type"::Project);
                if NewProject or (TempEntryLine."Project Task No." <> CurrTaskNo) then
                    TaskLineNo := InsertGroupLine(Buffer, NextLineNo, TempEntryLine, "BCJ Overview Line Type"::Task);
                CurrCustomerNo := TempEntryLine."Customer No.";
                CurrProjectNo := TempEntryLine."Project No.";
                CurrTaskNo := TempEntryLine."Project Task No.";
                NewCustomer := false;

                AddHoursToLine(Buffer, CustomerLineNo, TempEntryLine);
                AddHoursToLine(Buffer, ProjectLineNo, TempEntryLine);
                AddHoursToLine(Buffer, TaskLineNo, TempEntryLine);

                if IncludeTimeEntries then begin
                    NextLineNo += 1;
                    Buffer := TempEntryLine;
                    Buffer."Entry No." := NextLineNo;
                    Buffer.Insert();
                end;
            until TempEntryLine.Next() = 0;
        end;

        if Buffer.FindFirst() then;
    end;

    /// <summary>
    /// Narrows TimeEntry to the time entries that belong to the overview line OverviewLine. Existing filters on TimeEntry are kept.
    /// </summary>
    procedure ApplyLineFilter(OverviewLine: Record "BCJ Billing Overview Buffer"; var TimeEntry: Record "BCJ Project Time Entry")
    begin
        case OverviewLine."Line Type" of
            OverviewLine."Line Type"::Customer:
                TimeEntry.SetRange("Bill-to Customer No.", OverviewLine."Customer No.");
            OverviewLine."Line Type"::Project:
                TimeEntry.SetRange("Project No.", OverviewLine."Project No.");
            OverviewLine."Line Type"::Task:
                begin
                    TimeEntry.SetRange("Project No.", OverviewLine."Project No.");
                    TimeEntry.SetRange("Project Task No.", OverviewLine."Project Task No.");
                end;
            OverviewLine."Line Type"::"Time Entry":
                begin
                    TimeEntry.SetRange("Jira ID", OverviewLine."Jira ID");
                    TimeEntry.SetRange("Jira Issue Id", OverviewLine."Jira Issue Id");
                end;
        end;
    end;

    /// <summary>
    /// Marks on TimeEntry every time entry that belongs to any line in SelectedLine and is within the filters of TimeEntryFilter.
    /// On return TimeEntry is reset with MarkedOnly. Returns the number of distinct entries marked.
    /// </summary>
    procedure MarkEntriesForLines(var SelectedLine: Record "BCJ Billing Overview Buffer" temporary; var TimeEntryFilter: Record "BCJ Project Time Entry"; var TimeEntry: Record "BCJ Project Time Entry"): Integer
    var
        LineEntry: Record "BCJ Project Time Entry";
        MarkedCount: Integer;
    begin
        TimeEntry.Reset();
        TimeEntry.ClearMarks();
        if SelectedLine.FindSet() then
            repeat
                LineEntry.Reset();
                LineEntry.CopyFilters(TimeEntryFilter);
                ApplyLineFilter(SelectedLine, LineEntry);
                LineEntry.SetLoadFields("Jira ID", "Jira Issue Id");
                if LineEntry.FindSet() then
                    repeat
                        if TimeEntry.Get(LineEntry."Jira ID", LineEntry."Jira Issue Id") then
                            if not TimeEntry.Mark() then begin
                                TimeEntry.Mark(true);
                                MarkedCount += 1;
                            end;
                    until LineEntry.Next() = 0;
            until SelectedLine.Next() = 0;
        // No Reset here: it would discard the marks just set. Filters were cleared before marking.
        TimeEntry.MarkedOnly(true);
        exit(MarkedCount);
    end;

    /// <summary>
    /// Sets NewStatus on all time entries that belong to OverviewLine and are within the filters of TimeEntryFilter. Returns the number of entries changed.
    /// </summary>
    procedure SetStatusForLine(OverviewLine: Record "BCJ Billing Overview Buffer"; var TimeEntryFilter: Record "BCJ Project Time Entry"; NewStatus: Enum "BCJ Billing Status"): Integer
    var
        TimeEntry: Record "BCJ Project Time Entry";
        BillingMgt: Codeunit "BCJ Billing Mgt.";
    begin
        TimeEntry.CopyFilters(TimeEntryFilter);
        ApplyLineFilter(OverviewLine, TimeEntry);
        exit(BillingMgt.SetBillingStatus(TimeEntry, NewStatus));
    end;

    local procedure CollectTimeEntries(var TempEntryLine: Record "BCJ Billing Overview Buffer" temporary; var TimeEntryFilter: Record "BCJ Project Time Entry"; IncludeTimeEntries: Boolean)
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Job: Record Job;
        CustomerByProject: Dictionary of [Code[20], Code[20]];
        ReviewShares: Dictionary of [Text, Decimal];
        SharedReviewTasks: Dictionary of [Text, Boolean];
        EntryNo: Integer;
    begin
        TimeEntry.CopyFilters(TimeEntryFilter);
        TimeEntry.SetLoadFields("Project No.", "Project Task No.", "BC Resource No.", "Posting Date", "Time Spent in Hours", "Billable Hours", "Billing Status", "Review No.");
        if IncludeTimeEntries then
            TimeEntry.AddLoadFields(Comment);
        if not TimeEntry.FindSet() then
            exit;
        Job.SetLoadFields("Bill-to Customer No.");
        repeat
            if not CustomerByProject.ContainsKey(TimeEntry."Project No.") then
                if Job.Get(TimeEntry."Project No.") then
                    CustomerByProject.Add(TimeEntry."Project No.", Job."Bill-to Customer No.")
                else
                    CustomerByProject.Add(TimeEntry."Project No.", '');

            EntryNo += 1;
            TempEntryLine.Init();
            TempEntryLine."Entry No." := EntryNo;
            TempEntryLine."Line Type" := TempEntryLine."Line Type"::"Time Entry";
            TempEntryLine.Indentation := 3;
            TempEntryLine."Customer No." := CustomerByProject.Get(TimeEntry."Project No.");
            TempEntryLine."Project No." := TimeEntry."Project No.";
            TempEntryLine."Project Task No." := TimeEntry."Project Task No.";
            TempEntryLine."Jira ID" := TimeEntry."Jira ID";
            TempEntryLine."Jira Issue Id" := TimeEntry."Jira Issue Id";
            TempEntryLine."Resource No." := TimeEntry."BC Resource No.";
            TempEntryLine."Posting Date" := TimeEntry."Posting Date";
            TempEntryLine."Billing Status" := TimeEntry."Billing Status";
            TempEntryLine.Description := CopyStr(TimeEntry.Comment, 1, MaxStrLen(TempEntryLine.Description));
            TempEntryLine."Allocated Hours" := TimeEntry."Billable Hours";
            if TimeEntry."Billing Status" = TimeEntry."Billing Status"::"Sent for Review" then
                TempEntryLine."Allocated Hours" := GetReviewShare(TimeEntry, ReviewShares, SharedReviewTasks);
            AddHours(TempEntryLine, TimeEntry."Billing Status", TimeEntry."Time Spent in Hours", TempEntryLine."Allocated Hours");
            TempEntryLine.Insert();
        until TimeEntry.Next() = 0;
    end;

    /// <summary>
    /// Returns the part of a Sent for Review entry's hours that its review asks the customer to pay. The review line's
    /// Hours to Bill is spread over the task's entries in review oldest first, as ApplyAnswer later applies the approval,
    /// and over all of them regardless of the overview's filters. An entry without a review line keeps all its hours.
    /// </summary>
    local procedure GetReviewShare(TimeEntry: Record "BCJ Project Time Entry"; var ReviewShares: Dictionary of [Text, Decimal]; var SharedReviewTasks: Dictionary of [Text, Boolean]): Decimal
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
            ReviewLine.SetLoadFields("Hours to Bill");
            if ReviewLine.Get(TimeEntry."Review No.", TimeEntry."Project Task No.") then begin
                ReviewEntry.SetCurrentKey("Review No.", "Project Task No.", "Posting Date", "Jira ID");
                ReviewEntry.SetRange("Review No.", TimeEntry."Review No.");
                ReviewEntry.SetRange("Project Task No.", TimeEntry."Project Task No.");
                ReviewEntry.SetRange("Billing Status", ReviewEntry."Billing Status"::"Sent for Review");
                // Hours to Bill starts at the logged hours rounded to 0.01, so a line nobody lowered must not
                // leave the rounding difference in Not Billable.
                ReviewEntry.CalcSums("Time Spent in Hours");
                Remaining := ReviewLine."Hours to Bill";
                if Remaining >= Round(ReviewEntry."Time Spent in Hours", 0.01) then
                    Remaining := ReviewEntry."Time Spent in Hours";
                ReviewEntry.SetLoadFields("Time Spent in Hours");
                if ReviewEntry.FindSet() then
                    repeat
                        Share := Remaining;
                        if Share > ReviewEntry."Time Spent in Hours" then
                            Share := ReviewEntry."Time Spent in Hours";
                        if Share < 0 then
                            Share := 0;
                        Remaining -= Share;
                        ReviewShares.Set(EntryKey(ReviewEntry), Share);
                    until ReviewEntry.Next() = 0;
            end;
        end;
        if ReviewShares.Get(EntryKey(TimeEntry), Share) then
            exit(Share);
        exit(TimeEntry."Time Spent in Hours");
    end;

    local procedure EntryKey(TimeEntry: Record "BCJ Project Time Entry"): Text
    begin
        exit(TimeEntry."Jira ID" + '|' + TimeEntry."Jira Issue Id");
    end;

    local procedure InsertGroupLine(var Buffer: Record "BCJ Billing Overview Buffer" temporary; var NextLineNo: Integer; EntryLine: Record "BCJ Billing Overview Buffer" temporary; LineType: Enum "BCJ Overview Line Type"): Integer
    var
        Customer: Record Customer;
        Job: Record Job;
        JobTask: Record "Job Task";
    begin
        Customer.SetLoadFields(Name);
        Job.SetLoadFields(Description);
        JobTask.SetLoadFields(Description, "BCJ Jira Status");
        NextLineNo += 1;
        Buffer.Init();
        Buffer."Entry No." := NextLineNo;
        Buffer."Line Type" := LineType;
        Buffer."Customer No." := EntryLine."Customer No.";
        case LineType of
            LineType::Customer:
                begin
                    Buffer.Indentation := 0;
                    Buffer.Description := NoCustomerTxt;
                    if EntryLine."Customer No." <> '' then
                        if Customer.Get(EntryLine."Customer No.") then
                            Buffer.Description := Customer.Name
                        else
                            Buffer.Description := EntryLine."Customer No.";
                end;
            LineType::Project:
                begin
                    Buffer.Indentation := 1;
                    Buffer."Project No." := EntryLine."Project No.";
                    if Job.Get(EntryLine."Project No.") then
                        Buffer.Description := Job.Description;
                end;
            LineType::Task:
                begin
                    Buffer.Indentation := 2;
                    Buffer."Project No." := EntryLine."Project No.";
                    Buffer."Project Task No." := EntryLine."Project Task No.";
                    if JobTask.Get(EntryLine."Project No.", EntryLine."Project Task No.") then begin
                        Buffer.Description := JobTask.Description;
                        Buffer."Jira Status" := JobTask."BCJ Jira Status";
                    end;
                end;
        end;
        Buffer.Insert();
        exit(Buffer."Entry No.");
    end;

    local procedure AddHoursToLine(var Buffer: Record "BCJ Billing Overview Buffer" temporary; LineNo: Integer; EntryLine: Record "BCJ Billing Overview Buffer" temporary)
    begin
        Buffer.Get(LineNo);
        AddHours(Buffer, EntryLine."Billing Status", EntryLine."Total Hours", EntryLine."Allocated Hours");
        Buffer.Modify();
    end;

    /// <summary>
    /// Adds one entry's hours to the buckets of Line. LoggedHours is what Jira logged; AllocatedHours is the
    /// entry's Billable Hours, or for a Sent for Review entry its share of the review's Hours to Bill. For Sent for Review,
    /// Billable and Billed entries only the allocated part counts in that bucket
    /// and the rest is Not Billable, so the five buckets always add up to Total Hours.
    /// </summary>
    local procedure AddHours(var Line: Record "BCJ Billing Overview Buffer" temporary; Status: Enum "BCJ Billing Status"; LoggedHours: Decimal; AllocatedHours: Decimal)
    begin
        if AllocatedHours > LoggedHours then
            AllocatedHours := LoggedHours;
        if AllocatedHours < 0 then
            AllocatedHours := 0;
        Line."Total Hours" += LoggedHours;
        case Status of
            Status::Open:
                Line."Open Hours" += LoggedHours;
            Status::"Sent for Review":
                begin
                    Line."Sent for Review Hours" += AllocatedHours;
                    Line."Not Billable Hours" += LoggedHours - AllocatedHours;
                end;
            Status::Billable:
                begin
                    Line."Billable Hours" += AllocatedHours;
                    Line."Not Billable Hours" += LoggedHours - AllocatedHours;
                end;
            Status::"Not Billable":
                Line."Not Billable Hours" += LoggedHours;
            Status::Billed:
                begin
                    Line."Billed Hours" += AllocatedHours;
                    Line."Not Billable Hours" += LoggedHours - AllocatedHours;
                end;
        end;
        Line."Unbilled Hours" := Line."Open Hours" + Line."Sent for Review Hours" + Line."Billable Hours";
    end;
}
