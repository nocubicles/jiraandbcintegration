codeunit 50100 "BCJ Process Jira Queue"
{
    // trigger OnRun()
    // begin
    //     SyncIssuesAndTimeEntries();
    // end;
    // procedure SyncIssuesAndTimeEntries()
    // var
    //     Progress: Dialog;
    //     ProgessMessage: Label 'Syncing......';
    // begin
    //     if GuiAllowed then
    //         Progress.Open(ProgessMessage);
    //     ProcessMessagesFromQueue('syncprojectandtask');
    //     ProcessMessagesFromQueue('syncprojecttimeentries');
    //     Progress.Close();
    //     if GuiAllowed then
    //         Message('Sync Done');
    // end;
    // procedure ProcessMessagesFromQueue(Queue: Text)
    // begin
    //     if Process(Queue) then begin
    //         ProcessMessagesFromQueue(Queue);
    //     end;
    // end;
    // procedure DoFullSyncAllIssuesAndWorkEntries(Queue: Text)
    // var
    //     AzureStorageQueueSdk: Codeunit AzureStorageQueuesSdk;
    //     Base64Convert: Codeunit "Base64 Convert";
    // begin
    //     if AzureStorageQueueSdk.PostMessageToQueue(Queue, Base64Convert.ToBase64('yesplease')) then begin
    //         Message('Full Sync Scheduled');
    //     end;
    // end;
    // local procedure Process(Queue: Text): Boolean
    // var
    //     AzureStorageQueueSdk: Codeunit AzureStorageQueuesSdk;
    //     MessageBody: Text;
    //     MessageId: Text;
    //     MessageText: Text;
    //     MessageTextList: list of [text];
    //     MessagePopreceipt: Text;
    //     Base64Convert: Codeunit "Base64 Convert";
    // begin
    //     MessageBody := AzureStorageQueueSdk.GetNextMessageFromQueue(Queue);
    //     if MessageBody = '' then
    //         exit(false);
    //     MessageId := AzureStorageQueueSdk.GetMessageIdFromXmlText(MessageBody);
    //     MessageText := AzureStorageQueueSdk.GetMessageTextFromXmlText(MessageBody);
    //     MessageText := Base64Convert.FromBase64(MessageText);
    //     MessagePopreceipt := AzureStorageQueueSdk.GetMessagePopReceiptFromXmlText(MessageBody);
    //     if (MessageId <> '') AND (MessageText <> '') then begin
    //         MessageTextList := MessageText.Split(';');
    //         if Queue = 'syncprojectandtask' then
    //             if SyncJob(MessageTextList.Get(1), MessageTextList.Get(2)) and SyncJobTask(MessageTextList.Get(1), MessageTextList.Get(3), MessageTextList.Get(4), MessageTextList.Get(5)) then begin
    //                 //important here to check if delete is succesful and then commit. Otherwise we end in loop where messages are reappearing
    //                 if AzureStorageQueueSdk.DeleteMessageFromQueue(Queue, MessageId, MessagePopreceipt) then
    //                     Commit();
    //                 exit(true);
    //             end;
    //         if Queue = 'syncprojecttimeentries' then
    //             if SyncJobTimeEntry(MessageTextList.Get(1), MessageTextList.Get(2), MessageTextList.Get(3), MessageTextList.Get(4), MessageTextList.Get(5), MessageTextList.Get(6)) then begin
    //                 //important here to check if delete is succesful and then commit. Otherwise we end in loop where messages are reappearing
    //                 if AzureStorageQueueSdk.DeleteMessageFromQueue(Queue, MessageId, MessagePopreceipt) then
    //                     Commit();
    //                 exit(true);
    //             end;
    //     end;
    // end;
    procedure SyncJobTimeEntry(TimeEntryId: Text; JiraIssueId: Text; ResourceName: Text; PostingDate: Text; TimeSpentSeconds: Text; Comment: Text): Boolean var
        ProjectTimeEntry: Record "BCJ Project Time Entry";
        JobTask: Record "Job Task";
        PostingDateTime: DateTime;
        PostingDateDate: date;
        TimeSpentSecondsInt: Integer;
    begin
        JobTask.SetRange("BCJ Jira Task Id", JiraIssueId);
        if JobTask.FindFirst()then begin
            if ProjectTimeEntry.Get(TimeEntryId, JiraIssueId)then begin
                if Evaluate(PostingDateTime, PostingDate)then begin
                    PostingDateDate:=DT2Date(PostingDateTime);
                    ProjectTimeEntry.Validate("Posting Date", PostingDateDate);
                end;
                // A value Jira did not send must not shrink the worklog to 0 and cut the hours allocated to it.
                if Evaluate(TimeSpentSecondsInt, TimeSpentSeconds)then begin
                    ProjectTimeEntry.Validate("Time Spend Seconds", TimeSpentSecondsInt);
                    ProjectTimeEntry.Validate("Time Spent in Hours", TimeSpentSecondsInt / 3600);
                end;
                ProjectTimeEntry.Validate("BC Resource No.", SyncAndGetResourceCode(ResourceName));
                ProjectTimeEntry.Validate(Comment, CopyStr(Comment, 1, MaxStrLen(ProjectTimeEntry.Comment)));
                exit(ProjectTimeEntry.Modify(true));
            end
            else
            begin
                ProjectTimeEntry.Init();
                ProjectTimeEntry.Validate("Project No.", JobTask."Job No.");
                ProjectTimeEntry.Validate("Project Task No.", JobTask."Job Task No.");
                ProjectTimeEntry.Validate("Jira ID", TimeEntryId);
                ProjectTimeEntry.Validate("Jira Issue Id", JiraIssueId);
                if Evaluate(PostingDateTime, PostingDate)then begin
                    PostingDateDate:=DT2Date(PostingDateTime);
                    ProjectTimeEntry.Validate("Posting Date", PostingDateDate);
                end;
                if Evaluate(TimeSpentSecondsInt, TimeSpentSeconds)then ProjectTimeEntry.Validate("Time Spend Seconds", TimeSpentSecondsInt);
                ProjectTimeEntry.Validate("Time Spent in Hours", TimeSpentSecondsInt / 3600);
                ProjectTimeEntry.Validate("BC Resource No.", SyncAndGetResourceCode(ResourceName));
                ProjectTimeEntry.Validate(Comment, CopyStr(Comment, 1, MaxStrLen(ProjectTimeEntry.Comment)));
                exit(ProjectTimeEntry.Insert(true));
            end;
        end;
    end;
    local procedure SyncAndGetResourceCode(ResourceName: Text): Code[20]var
        Resource: Record Resource;
        ResourceNo: Code[20];
        ProjectSetup: Record "Jobs Setup";
    begin
        if ProjectSetup.Get()then begin
            ResourceNo:=CopyStr(ResourceName, 1, MaxStrLen(Resource."No."));
            if not Resource.Get(ResourceNo)then begin
                Resource.Init();
                Resource.Validate("No.", ResourceNo);
                Resource.Validate(Name, CopyStr(ResourceName, 1, MaxStrLen(Resource.Name)));
                Resource.Validate(Type, Resource.Type::Person);
                if ProjectSetup."BCJ Default Unit Of Measure" <> '' then Resource.Validate("Base Unit of Measure", ProjectSetup."BCJ Default Unit Of Measure");
                if Resource.Insert(true)then exit(Resource."No.");
            end;
            if Resource.Get(ResourceNo)then exit(Resource."No.");
        end;
    end;
    procedure SyncJobTask(JobNo: Code[20]; JobTaskNo: Code[20]; JobTaskDescription: Text; IssueId: Text; Status: Code[250]): Boolean var
        Job: Record Job;
        JobTask: Record "Job Task";
    begin
        if not JobTask.Get(JobNo, JobTaskNo)then begin
            JobTask.Init();
            JobTask.Validate("Job No.", JobNo);
            JobTask."Job Task No.":=JobTaskNo;
            JobTask.Validate("BCJ Jira Task Id", CopyStr(IssueId, 1, MaxStrLen(JobTask."BCJ Jira Task Id")));
            JobTask.Validate(Description, CopyStr(JobTaskDescription, 1, MaxStrLen(JobTask.Description)));
            JobTask.Validate("BCJ Jira Status", Status);
            if Job.Get(JobNo)then JobTask."Job Posting Group":=Job."Job Posting Group";
            exit(JobTask.Insert(false));
        end;
        if JobTask.Get(JobNo, JobTaskNo)then begin
            JobTask.Validate(Description, CopyStr(JobTaskDescription, 1, MaxStrLen(JobTask.Description)));
            JobTask.Validate("BCJ Jira Task Id", CopyStr(IssueId, 1, MaxStrLen(JobTask."BCJ Jira Task Id")));
            JobTask.Validate("BCJ Jira Status", Status);
            exit(JobTask.Modify(false));
        end;
    end;
    procedure SyncJob(JobNo: Text[20]; JobDescription: text): Boolean var
        Job: Record Job;
        Customer: Record Customer;
        CustProjectList: list of[text];
    begin
        if not Job.Get(JobNo)then begin
            Job.Init();
            job.Validate("No.", JobNo);
            job.Validate(Description, CopyStr(JobDescription, 1, MaxStrLen(job.Description)));
            exit(Job.Insert(true));
        end;
        if Job.Get(JobNo)then exit(true);
    end;
    procedure RemoveDeletedTimeEntry(TimeEntryId: text)
    var
        ProjectTimeEntry: Record "BCJ Project Time Entry";
    begin
        ProjectTimeEntry.SetRange("Jira ID", TimeEntryId);
        // With the trigger, so the worklog's hour allocation goes with it.
        ProjectTimeEntry.DeleteAll(true);
    end;
}
