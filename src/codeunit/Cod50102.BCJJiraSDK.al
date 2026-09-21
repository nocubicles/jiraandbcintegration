codeunit 50102 "BCJ Jira SDK"
{
    local procedure GetJiraClientV3(): HttpClient var
        JiraSetup: Record "BCJ Jira Integration Setup";
        JiraHttpClient: HttpClient;
        AuthString: Text;
        Base64Convert: Codeunit "Base64 Convert";
    begin
        if JiraSetup.Get()then begin
            JiraSetup.TestField("Jira API-Key");
            JiraSetup.TestField("Jira Env Name");
            JiraSetup.TestField("Jira User E-mail");
            JiraHttpClient.SetBaseAddress(JiraSetup."Jira Env Name" + '/rest/api/3/');
            AuthString:=Base64Convert.ToBase64(StrSubstNo('%1:%2', JiraSetup."Jira User E-mail", JiraSetup."Jira API-Key"));
            AuthString:=StrSubstNo('Basic %1', AuthString);
            JiraHttpClient.DefaultRequestHeaders.Add('Authorization', AuthString);
            JiraHttpClient.DefaultRequestHeaders.Add('Accept', 'application/json');
            exit(JiraHttpClient);
        end;
    end;
    procedure TestJiraConnection()
    var
        JiraHttpClient: HttpClient;
        ResponseMessage: HttpResponseMessage;
        ErrorMessage: Text;
    begin
        JiraHttpClient:=GetJiraClientV3();
        if JiraHttpClient.Get('myself', ResponseMessage)then begin
            if ResponseMessage.IsSuccessStatusCode then Message('Connection Success')
            else
            begin
                if ResponseMessage.Content.ReadAs(ErrorMessage)then Error(Format(ResponseMessage.HttpStatusCode) + '|' + ErrorMessage);
            end;
        end;
    end;
    procedure FullSyncAllJiraTimeEntries()
    var
        JiraSetup: Record "BCJ Jira Integration Setup";
        SyncStartDateTime: DateTime;
        Progress: Dialog;
        DialogText: Label 'Syncing Business Central with Jira...';
    begin
        if JiraSetup.Get()then begin
            Progress.Open(DialogText);
            JiraSetup.TestField("Sync Start Date");
            SyncStartDateTime:=System.CreateDateTime(JiraSetup."Sync Start Date", 0T);
            SyncTimeEntriesDeletedSince(GetUtcDateTime(SyncStartDateTime));
            JiraSetup.Validate("Worklog deleted last sync", GetUtcDateTime(CurrentDateTime));
            SyncTimeEntriesUpdatedSince(GetUtcDateTime(SyncStartDateTime));
            JiraSetup.Validate("Worklog changed last sync", GetUtcDateTime(CurrentDateTime));
            JiraSetup.Modify(true);
            Progress.Close();
        end;
    end;
    procedure SyncChangedAndDeletedEntries()
    var
        JiraSetup: Record "BCJ Jira Integration Setup";
        SyncStartTimestamp: BigInteger;
        Progress: Dialog;
        DialogText: Label 'Syncing Business Central with Jira...';
    begin
        if JiraSetup.Get()then begin
            Progress.Open(DialogText);
            if JiraSetup."Worklog deleted last sync" = 0 then SyncStartTimestamp:=GetUtcDateTime(System.CreateDateTime(JiraSetup."Sync Start Date", 0T))
            else
                SyncStartTimestamp:=JiraSetup."Worklog deleted last sync";
            SyncTimeEntriesDeletedSince(SyncStartTimestamp);
            JiraSetup.Validate("Worklog deleted last sync", GetUtcDateTime(CurrentDateTime));
            if JiraSetup."Worklog changed last sync" = 0 then SyncStartTimestamp:=GetUtcDateTime(System.CreateDateTime(JiraSetup."Sync Start Date", 0T))
            else
                SyncStartTimestamp:=JiraSetup."Worklog changed last sync";
            SyncTimeEntriesUpdatedSince(SyncStartTimestamp);
            JiraSetup.Validate("Worklog changed last sync", GetUtcDateTime(CurrentDateTime));
            JiraSetup.Modify(true);
            Progress.Close();
        end;
    end;
    local procedure SyncTimeEntriesUpdatedSince(UnixTimestamp: BigInteger)
    var
        JiraHttpClient: HttpClient;
        ResponseMessage: HttpResponseMessage;
        JsonObject: JsonObject;
        JsonArray: JsonArray;
        JsonToken: JsonToken;
        JSONString: Text;
        Worklog: JsonToken;
        worklogId: JsonToken;
        ChangedWorklogIds: JsonArray;
        ErrorMessage: Text;
    begin
        JiraHttpClient:=GetJiraClientV3();
        if JiraHttpClient.Get(StrSubstNo('worklog/updated?since=%1', Format(UnixTimestamp)), ResponseMessage)then begin
            if ResponseMessage.IsSuccessStatusCode then begin
                if ResponseMessage.Content.ReadAs(JSONString)then begin
                    if JsonObject.ReadFrom(JSONString)then begin
                        if JsonObject.Get('values', JsonToken)then begin
                            JsonArray:=JsonToken.AsArray();
                            if JsonArray.Count > 0 then begin
                                foreach Worklog in JsonArray do begin
                                    if Worklog.AsObject().Get('worklogId', worklogId)then ChangedWorklogIds.Add(worklogId.AsValue().AsText());
                                end;
                                SyncWorklogDetails(ChangedWorklogIds);
                            end;
                        end;
                    end;
                end;
            end
            else
            begin
                if ResponseMessage.Content.ReadAs(ErrorMessage)then Error(Format(ResponseMessage.HttpStatusCode) + '|' + ErrorMessage);
            end end;
    end;
    local procedure SyncTimeEntriesDeletedSince(UnixTimestamp: BigInteger)
    var
        JiraHttpClient: HttpClient;
        ResponseMessage: HttpResponseMessage;
        JsonObject: JsonObject;
        JsonArray: JsonArray;
        JsonToken: JsonToken;
        JSONString: Text;
        Worklog: JsonToken;
        worklogId: JsonToken;
        ChangedWorklogIds: JsonArray;
        ErrorMessage: Text;
        ProcessQueue: Codeunit "BCJ Process Jira Queue";
        JiraIntegrationSetup: Record "BCJ Jira Integration Setup";
    begin
        JiraHttpClient:=GetJiraClientV3();
        if JiraHttpClient.Get(StrSubstNo('worklog/deleted?since=%1', Format(UnixTimestamp)), ResponseMessage)then begin
            if ResponseMessage.IsSuccessStatusCode then begin
                if ResponseMessage.Content.ReadAs(JSONString)then begin
                    if JsonObject.ReadFrom(JSONString)then begin
                        if JsonObject.Get('values', JsonToken)then begin
                            JsonArray:=JsonToken.AsArray();
                            if JsonArray.Count > 0 then begin
                                foreach Worklog in JsonArray do begin
                                    if Worklog.AsObject().Get('worklogId', worklogId)then ProcessQueue.RemoveDeletedTimeEntry(worklogId.AsValue().AsText());
                                end;
                            end;
                        end;
                    end;
                end;
            end
            else
            begin
                if ResponseMessage.Content.ReadAs(ErrorMessage)then Error(Format(ResponseMessage.HttpStatusCode) + '|' + ErrorMessage);
            end end;
    end;
    local procedure SyncWorklogDetails(WorklogIDs: JsonArray)
    var
        JiraHttpClient: HttpClient;
        WorkDetailObjectRequest: JsonObject;
        WorkDetails: JsonArray;
        IssueDetailContent: HttpContent;
        JSONString: Text;
        ResponseMessage: HttpResponseMessage;
        IssueResponeArray: JsonArray;
        Worklog: JsonObject;
        WorklogJsonToken: JsonToken;
        IssueIdToken: JsonToken;
        ErrorMessage: text;
        ContentHeaders: HttpHeaders;
        TimeEntryId: text;
        ResourceName: text;
        PostingDate: text;
        TimeSpentSeconds: text;
        Comment: Text;
        IssueId: Text;
        JsonToken: JsonToken;
        CommentObject: JsonObject;
        CommentContent: JsonArray;
        BCProcessJiraQueue: Codeunit "BCJ Process Jira Queue";
    begin
        JiraHttpClient:=GetJiraClientV3();
        WorkDetailObjectRequest.Add('ids', WorklogIDs);
        if WorkDetailObjectRequest.WriteTo(JSONString)then begin
            IssueDetailContent.WriteFrom(JSONString);
            IssueDetailContent.GetHeaders(ContentHeaders);
            if ContentHeaders.Contains('Content-Type')then ContentHeaders.Remove('Content-Type');
            ContentHeaders.Add('Content-Type', 'application/json;charset=UTF-8');
            IssueDetailContent.GetHeaders(ContentHeaders);
            if JiraHttpClient.Post('worklog/list', IssueDetailContent, ResponseMessage)then begin
                if ResponseMessage.IsSuccessStatusCode()then begin
                    if ResponseMessage.Content.ReadAs(JSONString)then begin
                        if WorkDetails.ReadFrom(JSONString)then begin
                            if WorkDetails.count > 0 then begin
                                foreach WorklogJsonToken in WorkDetails do begin
                                    Clear(IssueId);
                                    Clear(TimeEntryId);
                                    Clear(ResourceName);
                                    Clear(PostingDate);
                                    Clear(TimeSpentSeconds);
                                    Clear(Comment);
                                    Worklog:=WorklogJsonToken.AsObject();
                                    if Worklog.Get('issueId', IssueIdToken)then begin
                                        IssueId:=IssueIdToken.AsValue().AsText();
                                        SyncProjectAndTaskFromJira(IssueId);
                                    end;
                                    if Worklog.Get('id', JsonToken)then TimeEntryId:=JsonToken.AsValue().AsText();
                                    if Worklog.Get('author', JsonToken)then if JsonToken.AsObject().Get('displayName', JsonToken)then ResourceName:=JsonToken.AsValue().AsText();
                                    if Worklog.Get('started', JsonToken)then PostingDate:=JsonToken.AsValue().AsText();
                                    if Worklog.Get('timeSpentSeconds', JsonToken)then TimeSpentSeconds:=JsonToken.AsValue().AsText();
                                    if Worklog.Get('comment', JsonToken)then begin
                                        if JsonToken.AsObject().Get('content', JsonToken)then if JsonToken.AsArray().Get(0, JsonToken)then if JsonToken.AsObject().Get('content', JsonToken)then if JsonToken.AsArray().Get(0, JsonToken)then if JsonToken.AsObject().Get('text', JsonToken)then Comment:=JsonToken.AsValue().AsText();
                                    end;
                                    if TimeSpentSeconds <> '' then begin
                                        BCProcessJiraQueue.SyncJobTimeEntry(TimeEntryId, IssueId, ResourceName, PostingDate, TimeSpentSeconds, Comment);
                                    end;
                                end;
                            end;
                        end;
                    end;
                end
                else
                begin
                    if ResponseMessage.Content.ReadAs(ErrorMessage)then Error(Format(ResponseMessage.HttpStatusCode) + ' ' + ResponseMessage.ReasonPhrase + '|' + ErrorMessage);
                end end;
        end;
    end;
    procedure UpdateExistingProjectIssueStatuses()
    var
        JobTask: Record "Job Task";
        Progress: Dialog;
        DialogText: Label 'Syncing Business Central with Jira...';
    begin
        Progress.Open(DialogText);
        JobTask.SetFilter("BCJ Jira Task Id", '<>%1', '');
        if JobTask.FindSet(false)then repeat SyncProjectAndTaskFromJira(JobTask."BCJ Jira Task Id");
            until JobTask.Next() = 0;
        Progress.Close();
    end;
    local procedure SyncProjectAndTaskFromJira(IssueId: Text)
    var
        JiraHttpClient: HttpClient;
        ResponseMessage: HttpResponseMessage;
        ErrorMessage: Text;
        JsonString: Text;
        IssueObject: JsonObject;
        ProcessJiraQueue: Codeunit "BCJ Process Jira Queue";
        ProjectNo: Code[20];
        ProjectDescription: text;
        ProjectTaskNo: Code[20];
        ProjectTaskDescription: Text;
        JsonToken: JsonToken;
        ProjectObject: JsonObject;
        FieldsObject: JsonObject;
        Status: Code[250];
    begin
        JiraHttpClient:=GetJiraClientV3();
        if JiraHttpClient.Get(StrSubstNo('issue/%1', IssueId), ResponseMessage)then begin
            if ResponseMessage.IsSuccessStatusCode then begin
                if ResponseMessage.Content.ReadAs(JSONString)then begin
                    if IssueObject.ReadFrom(JSONString)then begin
                        if IssueObject.Get('fields', JsonToken)then begin
                            FieldsObject:=JsonToken.AsObject();
                            if FieldsObject.Get('project', JsonToken)then begin
                                ProjectObject:=JsonToken.AsObject();
                                if ProjectObject.Get('key', JsonToken)then ProjectNo:=JsonToken.AsValue().AsCode();
                                if ProjectObject.Get('name', JsonToken)then ProjectDescription:=JsonToken.AsValue().AsText();
                            end;
                            if FieldsObject.Get('status', JsonToken)then if JsonToken.AsObject().Get('name', JsonToken)then Status:=JsonToken.AsValue().AsCode();
                        end;
                        if IssueObject.Get('key', JsonToken)then ProjectTaskNo:=JsonToken.AsValue().AsCode();
                        if FieldsObject.Get('summary', JsonToken)then ProjectTaskDescription:=JsonToken.AsValue().AsText();
                    end;
                    if(ProjectTaskNo <> '') and (ProjectNo <> '')then begin
                        if ProcessJiraQueue.SyncJob(ProjectNo, ProjectDescription)then ProcessJiraQueue.SyncJobTask(ProjectNo, ProjectTaskNo, ProjectTaskDescription, IssueId, Status)end;
                end;
            end
            else
            begin
                if ResponseMessage.Content.ReadAs(ErrorMessage)then Error(Format(ResponseMessage.HttpStatusCode) + '|' + ErrorMessage);
            end end end;
    procedure GetUtcDateTime(EndDateTime: DateTime)UnixTimeStamp: BigInteger;
    var
        StartDateTime: DateTime;
        Duration: Duration;
    begin
        StartDateTime:=System.CreateDateTime(19700101D, 0T);
        Duration:=EndDateTime - StartDateTime;
        UnixTimeStamp:=(Duration / 1);
    end;
}
