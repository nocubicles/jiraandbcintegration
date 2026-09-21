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
        EntryNo: Integer;
    begin
        TimeEntry.CopyFilters(TimeEntryFilter);
        TimeEntry.SetLoadFields("Project No.", "Project Task No.", "BC Resource No.", "Posting Date", "Time Spent in Hours", "Billing Status");
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
            AddHours(TempEntryLine, TimeEntry."Billing Status", TimeEntry."Time Spent in Hours");
            TempEntryLine.Insert();
        until TimeEntry.Next() = 0;
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
        AddHours(Buffer, EntryLine."Billing Status", EntryLine."Total Hours");
        Buffer.Modify();
    end;

    local procedure AddHours(var Line: Record "BCJ Billing Overview Buffer" temporary; Status: Enum "BCJ Billing Status"; Hours: Decimal)
    begin
        Line."Total Hours" += Hours;
        case Status of
            Status::Open:
                Line."Open Hours" += Hours;
            Status::Billable:
                Line."Billable Hours" += Hours;
            Status::"Not Billable":
                Line."Not Billable Hours" += Hours;
            Status::Billed:
                Line."Billed Hours" += Hours;
        end;
        Line."Unbilled Hours" := Line."Open Hours" + Line."Billable Hours";
    end;
}
