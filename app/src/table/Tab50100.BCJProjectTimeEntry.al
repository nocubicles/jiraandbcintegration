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

            trigger OnValidate()
            begin
                // Undecided entries stay fully billable; decided ones keep their allocation but never exceed the logged hours.
                if "Billing Status" in ["Billing Status"::Open, "Billing Status"::"Sent for Review"] then
                    "Billable Hours" := "Time Spent in Hours"
                else
                    if "Billable Hours" > "Time Spent in Hours" then
                        "Billable Hours" := "Time Spent in Hours";
            end;
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
        field(18; "Billing Status"; Enum "BCJ Billing Status")
        {
            Caption = 'Billing Status';
            DataClassification = CustomerContent;

            trigger OnValidate()
            begin
                // Keep the legacy flags in sync for the Jira Time Entries page.
                "Is Billable" := "Billing Status" in ["Billing Status"::Billable, "Billing Status"::Billed];
                "Is Billed" := "Billing Status" = "Billing Status"::Billed;
            end;
        }
        field(19; "Bill-to Customer No."; Code[20])
        {
            Caption = 'Bill-to Customer No.';
            Editable = false;
            FieldClass = FlowField;
            CalcFormula = lookup(Job."Bill-to Customer No." where("No."=field("Project No.")));
        }
        field(20; "Billable Hours"; Decimal)
        {
            Caption = 'Billable Hours';
            DecimalPlaces = 0 : 2;
            MinValue = 0;
            Editable = false;
            DataClassification = CustomerContent;
        }
        field(21; "Review No."; Integer)
        {
            Caption = 'Customer Review No.';
            Editable = false;
            DataClassification = CustomerContent;
            TableRelation = "BCJ Customer Review"."Review No.";
            ValidateTableRelation = false;
        }
    }
    keys
    {
        key(Key1; "Jira ID", "Jira Issue Id")
        {
            Clustered = true;
        }
        key(ProjectTaskDate; "Project No.", "Project Task No.", "Posting Date")
        {
        }
        key(BillingStatus; "Billing Status", "Posting Date")
        {
        }
        key(ReviewAlloc; "Review No.", "Project Task No.", "Posting Date", "Jira ID")
        {
        }
    }

    trigger OnInsert()
    begin
        if "Billable Hours" = 0 then
            "Billable Hours" := "Time Spent in Hours";
    end;
}
