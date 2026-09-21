tableextension 50100 "BCJ Job Task" extends "Job Task"
{
    fields
    {
        field(50100; "BCJ Jira Task Id"; Text[50])
        {
            Caption = 'Jira Issue Id';
            DataClassification = CustomerContent;
        }
        field(50101; "BCJ Jira Status"; Code[250])
        {
            Caption = 'Status In Jira';
        }
    }
    keys
    {
        key(JiraTaskId; "BCJ Jira Task Id")
        {
        }
    }
}
