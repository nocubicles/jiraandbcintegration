table 50101 "BCJ Jira Integration Setup"
{
    DataClassification = ToBeClassified;
    Caption = 'Jira Integration Setup';

    fields
    {
        field(1; PK; Integer)
        {
            DataClassification = ToBeClassified;
        }
        field(2; "Jira Env Name"; Text[250])
        {
            DataClassification = ToBeClassified;
            Caption = 'Name of the Jira Environment';
        }
        field(3; "Jira User E-mail"; Text[80])
        {
            DataClassification = CustomerContent;
            Caption = 'Jira User E-Mail';
        }
        field(4; "Jira API-Key"; Text[250])
        {
            DataClassification = CustomerContent;
            Caption = 'Jira API Key';
        }
        field(5; "Sync Start Date"; Date)
        {
            DataClassification = CustomerContent;
            Caption = 'Start date for time log entries sync';
        }
        field(6; "Worklog changed last sync"; BigInteger)
        {
            DataClassification = CustomerContent;
            Caption = 'Last Synced Timestamp for changed Work Log Entries';
        }
        field(7; "Worklog deleted last sync"; BigInteger)
        {
            DataClassification = CustomerContent;
            Caption = 'Last Synced Timestamp for deleted Work Log Entries';
        }
        field(8; "Review Base URL"; Text[250])
        {
            DataClassification = CustomerContent;
            Caption = 'Customer Review Base URL';
        }
    }
    keys
    {
        key(Key1; PK)
        {
            Clustered = true;
        }
    }
    procedure TestConnection()
    var
        JiraSDK: Codeunit "BCJ Jira SDK";
    begin
        JiraSDK.TestJiraConnection();
    end;
    procedure DoFullSync()
    var
        JiraSDK: Codeunit "BCJ Jira SDK";
    begin
        JiraSDK.FullSyncAllJiraTimeEntries();
    end;
    procedure SyncChangedAndDeletedEntries()
    var
        JiraSDK: Codeunit "BCJ Jira SDK";
    begin
        JiraSDK.SyncChangedAndDeletedEntries();
    end;
    procedure UpdateIssueData()
    var
        JiraSDK: Codeunit "BCJ Jira SDK";
    begin
        JiraSDK.UpdateExistingProjectIssueStatuses();
    end;
}
