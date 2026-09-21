table 50100 "BCJ Project Time Entry"
{
    DataClassification = ToBeClassified;

    fields
    {
        field(1; "Jira ID"; Text[50])
        {
            DataClassification = ToBeClassified;
            Caption = 'Jira ID';
            Editable = false;
        }
        field(3; "Project No."; Code[20])
        {
            Caption = 'Project No.';
            TableRelation = Job."No.";
            Editable = false;
        }
        field(4; "Project Task No."; Code[20])
        {
            Caption = 'Project Task No.';
            TableRelation = "Job Task"."Job Task No.";
            Editable = false;
        }
        field(5; "BC Resource No."; Code[20])
        {
            Caption = 'Resource No.';
            TableRelation = Resource."No.";
            Editable = false;
        }
        field(6; "Posting Date"; Date)
        {
            Caption = 'Posting Date';
            Editable = false;
        }
        field(7; "Time Spend Seconds"; Integer)
        {
            Caption = 'Time Spent in Seconds';
            Editable = false;
        }
        field(8; "Time Spent in Hours"; Decimal)
        {
            Caption = 'Time Spent in Hours';
            Editable = false;
        }
        field(9; "Jira Issue Id"; Text[50])
        {
            Caption = 'Jira Issue Id';
            Editable = false;
        }
        field(10; Comment; Text[2024])
        {
            Caption = 'Comment';
            Editable = false;
        }
        field(11; "Transfer To Job Journal"; Boolean)
        {
            Caption = 'Is transfered to Job Journal';
        }
        field(12; "Skip transfer to Job Journal"; Boolean)
        {
            Caption = 'Skip this line from transferring to job journals';
        }
        field(13; "Is Billed"; Boolean)
        {
            Caption = 'Is Billed';
        }
        field(14; "Project Description"; Text[100])
        {
            FieldClass = FlowField;
            Editable = false;
            Caption = 'Project Description';
            CalcFormula = lookup(Job.Description where("No."=field("Project No.")));
        }
        field(15; "Task Description"; Text[100])
        {
            FieldClass = FlowField;
            Editable = false;
            Caption = 'Task Description';
            CalcFormula = lookup("Job Task".Description where("Job No."=field("Project No."), "Job Task No."=field("Project Task No.")));
        }
        field(16; "Is Billable"; Boolean)
        {
            Caption = 'Is Billable';
        }
        field(17; Status; Code[250])
        {
            Caption = 'Issue Status in Jira';
            Editable = false;
            FieldClass = FlowField;
            CalcFormula = lookup("Job Task"."BCJ Jira Status" where("Job No."=field("Project No."), "Job Task No."=field("Project Task No.")));
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
