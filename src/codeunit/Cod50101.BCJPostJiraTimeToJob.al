codeunit 50101 "BCJ Post Jira Time To Job"
{
    trigger OnRun()
    begin

    end;

    procedure ProcessUnpostedJiraTimeEntries()
    var
        BCAndJiraTimeEntry: Record "BCJ Project Time Entry";
        BCAndJiraTimeEntryAggregate: Record "BCJ Project Time Entry";
    begin
        BCAndJiraTimeEntry.SetRange("Transfer To Job Journal", false);
        BCAndJiraTimeEntry.SetRange("Skip transfer to Job Journal", false);
        if BCAndJiraTimeEntry.FindSet(true) then
            repeat
                BCAndJiraTimeEntryAggregate.CopyFilters(BCAndJiraTimeEntry);
                BCAndJiraTimeEntryAggregate.SetRange("Project No.", BCAndJiraTimeEntry."Project No.");
                BCAndJiraTimeEntryAggregate.SetRange("Project Task No.", BCAndJiraTimeEntry."Project Task No.");
                BCAndJiraTimeEntryAggregate.SetRange("BC Resource No.", BCAndJiraTimeEntry."BC Resource No.");
                BCAndJiraTimeEntryAggregate.CalcSums("Time Spent in Hours");
                if CreateJobJournalEntry(BCAndJiraTimeEntry."Project No.", BCAndJiraTimeEntry."Project Task No.", BCAndJiraTimeEntry."BC Resource No.", BCAndJiraTimeEntryAggregate."Time Spent in Hours", BCAndJiraTimeEntry."Posting Date") then begin
                    BCAndJiraTimeEntryAggregate.ModifyAll("Transfer To Job Journal", true);
                end;
            until BCAndJiraTimeEntry.Next() = 0;
        Message('Journal entries created');
    end;

    local procedure CreateJobJournalEntry(JobNo: Code[20]; JobTaskNo: Code[20]; ResourceCode: Code[20]; QuantityInHour: Decimal; PostingDate: Date): Boolean
    var
        JobJournalLine: Record "Job Journal Line";
        JobsSetup: Record "Jobs Setup";
    begin
        JobsSetup.SetLoadFields("BCJ Job Journal Batch", "BCJ Job Journal Templ.");
        if JobsSetup.Get() then begin
            JobsSetup.TestField("BCJ Job Journal Templ.");
            JobsSetup.TestField("BCJ Job Journal Batch");
            JobJournalLine.Init();
            JobJournalLine.Validate("Line Type", JobJournalLine."Line Type"::Billable);
            JobJournalLine.Validate("Journal Template Name", JobsSetup."BCJ Job Journal Templ.");
            JobJournalLine.Validate("Journal Batch Name", JobsSetup."BCJ Job Journal Batch");
            JobJournalLine.Validate("Line No.", GetNextLineNo(JobsSetup."BCJ Job Journal Templ.", JobsSetup."BCJ Job Journal Batch"));
            JobJournalLine.Validate("Posting Date", PostingDate);
            JobJournalLine.Validate("Job No.", JobNo);
            JobJournalLine.Validate("Job Task No.", JobTaskNo);
            JobJournalLine.Validate(Type, JobJournalLine.Type::Resource);
            JobJournalLine.Validate("No.", ResourceCode);
            JobJournalLine.Validate(Quantity, QuantityInHour);
            exit(JobJournalLine.Insert(true));
        end;
    end;

    local procedure GetNextLineNo(JournalTemplate: Code[20]; JournalBatch: Code[20]): Integer
    var
        JobJournalLine: Record "Job Journal Line";
    begin
        JobJournalLine.SetRange("Journal Template Name", JournalTemplate);
        JobJournalLine.SetRange("Journal Batch Name", JournalBatch);
        JobJournalLine.SetLoadFields("Line No.");
        if JobJournalLine.FindLast() then
            exit(JobJournalLine."Line No." + 10000)
        else
            exit(10000);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Job Create-Invoice", 'OnBeforeInsertSalesLine', '', false, false)]
    local procedure ChangeSalesLineDescription(JobPlanningLine: Record "Job Planning Line"; var SalesLine: Record "Sales Line")
    var
        JobTask: Record "Job Task";
    begin
        JobTask.SetLoadFields(Description);
        if JobTask.Get(JobPlanningLine."Job No.", JobPlanningLine."Job Task No.") then
            SalesLine.Validate(Description, JobTask.Description);
    end;
}