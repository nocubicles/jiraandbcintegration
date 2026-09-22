codeunit 50152 "BCJ Test Library"
{
    // Shared fixture helpers for the bcjiraintegration test suite.
    // Every fixture uses keys derived from a fresh GUID stem, so tests never collide with
    // real synced Jira data in the sandbox or with each other. Nothing is cached between
    // calls - each test builds its own fixtures and the test runner rolls them back.

    procedure NewStem(): Code[13]
    begin
        // 'T' + 12 hex chars from a fresh GUID: 13 chars, leaves 7 chars of Code[20] for suffixes.
        exit(CopyStr('T' + CopyStr(DelChr(Format(CreateGuid()), '=', '{}-'), 1, 12), 1, 13));
    end;

    procedure BaseDate(): Date
    begin
        exit(DMY2Date(15, 1, 2030));
    end;

    procedure CreateCustomer(CustomerNo: Code[20]; CustomerName: Text[100])
    var
        Customer: Record Customer;
    begin
        if Customer.Get(CustomerNo) then begin
            Customer.Name := CustomerName;
            Customer.Modify(false);
            exit;
        end;
        Customer.Init();
        Customer."No." := CustomerNo;
        Customer.Name := CustomerName;
        Customer.Insert(false);
    end;

    procedure CreateJob(JobNo: Code[20]; BillToCustomerNo: Code[20]; JobDescription: Text[100])
    var
        Job: Record Job;
    begin
        if not Job.Get(JobNo) then begin
            Job.Init();
            Job."No." := JobNo;
            Job.Insert(false);
        end;
        Job.Description := JobDescription;
        // Direct assignment on purpose: validating Bill-to Customer No. pulls in customer
        // posting/contact setup that is irrelevant to the code under test.
        Job."Bill-to Customer No." := BillToCustomerNo;
        Job.Modify(false);
    end;

    procedure CreateJobTask(JobNo: Code[20]; JobTaskNo: Code[20]; TaskDescription: Text[100]; JiraStatus: Code[250])
    var
        JobTask: Record "Job Task";
    begin
        if not JobTask.Get(JobNo, JobTaskNo) then begin
            JobTask.Init();
            JobTask."Job No." := JobNo;
            JobTask."Job Task No." := JobTaskNo;
            JobTask.Insert(false);
        end;
        JobTask.Description := TaskDescription;
        JobTask."BCJ Jira Status" := JiraStatus;
        JobTask.Modify(false);
    end;

    procedure SetJobTaskJiraId(JobNo: Code[20]; JobTaskNo: Code[20]; JiraTaskId: Text[50])
    var
        JobTask: Record "Job Task";
    begin
        // CreateJobTask does not set the Jira issue id - the worklog sync looks the task up by it,
        // so tests that exercise worklogs have to link the two explicitly.
        JobTask.Get(JobNo, JobTaskNo);
        JobTask."BCJ Jira Task Id" := JiraTaskId;
        JobTask.Modify(false);
    end;

    procedure EnsureJobsSetup()
    var
        JobsSetup: Record "Jobs Setup";
    begin
        // The worklog sync reads the Projects setup singleton. A sandbox or a fresh CRONUS may or
        // may not have it, so create it when missing and leave an existing one untouched - its
        // default unit of measure is real configuration a test has no business changing.
        if JobsSetup.Get() then
            exit;
        JobsSetup.Init();
        JobsSetup.Insert(false);
    end;

    procedure CreateTimeEntry(var TimeEntry: Record "BCJ Project Time Entry"; JiraId: Text[50]; JobNo: Code[20]; JobTaskNo: Code[20]; ResourceNo: Code[20]; PostingDate: Date; Hours: Decimal; Status: Enum "BCJ Billing Status")
    begin
        TimeEntry.Init();
        TimeEntry."Jira ID" := JiraId;
        TimeEntry."Jira Issue Id" := CopyStr('I-' + JiraId, 1, MaxStrLen(TimeEntry."Jira Issue Id"));
        TimeEntry."Project No." := JobNo;
        TimeEntry."Project Task No." := JobTaskNo;
        TimeEntry."BC Resource No." := ResourceNo;
        TimeEntry."Posting Date" := PostingDate;
        TimeEntry."Time Spent in Hours" := Hours;
        TimeEntry."Time Spend Seconds" := Round(Hours * 3600, 1);
        TimeEntry.Comment := CopyStr('Worklog ' + JiraId, 1, MaxStrLen(TimeEntry.Comment));
        // Direct assignment: fixtures set the status without triggering flag sync, so tests
        // can control the legacy flags independently.
        TimeEntry."Billing Status" := Status;
        TimeEntry."Is Billable" := false;
        TimeEntry."Is Billed" := false;
        TimeEntry.Insert(false);
    end;

    procedure SetLegacyFlags(var TimeEntry: Record "BCJ Project Time Entry"; IsBillable: Boolean; IsBilled: Boolean)
    begin
        TimeEntry.Get(TimeEntry."Jira ID", TimeEntry."Jira Issue Id");
        TimeEntry."Is Billable" := IsBillable;
        TimeEntry."Is Billed" := IsBilled;
        TimeEntry.Modify(false);
    end;
}
