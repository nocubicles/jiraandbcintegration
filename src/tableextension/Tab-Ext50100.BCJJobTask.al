tableextension 50100 "BCJ Job Task" extends "Job Task"
{
    fields
    {
        field(50100; "BCJ Jira Task Id"; Text[50])
        {
            Caption = 'Jira Issue Id';
            DataClassification = CustomerContent;
        }
    }

    keys
    {
        key(JiraTaskId; "BCJ Jira Task Id") { }
    }
}