table 50100 "BCJ Project Time Entry"
{
    DataClassification = ToBeClassified;

    fields
    {
        field(1; "Jira ID"; Text[50])
        {
            DataClassification = ToBeClassified;
            Caption = 'Jira ID';
        }
        field(3; "Project No."; Code[20])
        {
            Caption = 'Project No.';
            TableRelation = Job."No.";
        }
        field(4; "Project Task No."; Code[20])
        {
            Caption = 'Project Task No.';
            TableRelation = "Job Task"."Job Task No.";
        }
        field(5; "BC Resource No."; Code[20])
        {
            Caption = 'Resource No.';
            TableRelation = Resource."No.";
        }
        field(6; "Posting Date"; Date)
        {
            Caption = 'Posting Date';
        }
        field(7; "Time Spend Seconds"; Integer)
        {
            Caption = 'Time Spent in Seconds';
        }
        field(8; "Time Spent in Hours"; Decimal)
        {
            Caption = 'Time Spent in Hours';
        }
        field(9; "Jira Issue Id"; Text[50])
        {
            Caption = 'Jira Issue Id';
        }
        field(10; Comment; Text[2024])
        {
            Caption = 'Comment';
        }
        field(11; "Transfer To Job Journal"; Boolean)
        {
            Caption = 'Is transfered to Job Journal';
        }
        field(12; "Skip transfer to Job Journal"; Boolean)
        {
            Caption = 'Skip this line from transferring to job journals';
        }
    }

    keys
    {
        key(Key1; "Jira ID", "Jira Issue Id")
        {
            Clustered = true;
        }
    }
}