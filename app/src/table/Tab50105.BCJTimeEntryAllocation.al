table 50105 "BCJ Time Entry Allocation"
{
    Caption = 'Time Entry Allocation';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Jira ID"; Text[50])
        {
            Caption = 'Jira ID';
        }
        field(2; "Jira Issue Id"; Text[50])
        {
            Caption = 'Jira Issue Id';
        }
        field(3; "Review No."; Integer)
        {
            Caption = 'Customer Review No.';
            TableRelation = "BCJ Customer Review"."Review No.";
            ValidateTableRelation = false;
        }
        field(4; "Project No."; Code[20])
        {
            Caption = 'Project No.';
        }
        field(5; "Project Task No."; Code[20])
        {
            Caption = 'Project Task No.';
        }
        field(6; "Posting Date"; Date)
        {
            Caption = 'Posting Date';
        }
        field(10; "Reserved Hours"; Decimal)
        {
            Caption = 'Reserved Hours';
            DecimalPlaces = 0 : 2;
        }
        field(11; "In Review Hours"; Decimal)
        {
            Caption = 'In Review Hours';
            DecimalPlaces = 0 : 2;
        }
        field(12; "Billable Hours"; Decimal)
        {
            Caption = 'Billable Hours';
            DecimalPlaces = 0 : 2;
        }
        field(13; "Billed Hours"; Decimal)
        {
            Caption = 'Billed Hours';
            DecimalPlaces = 0 : 2;
        }
        field(14; "Not Billable Hours"; Decimal)
        {
            Caption = 'Not Billable Hours';
            DecimalPlaces = 0 : 2;
        }
    }
    keys
    {
        key(PK; "Jira ID", "Jira Issue Id", "Review No.")
        {
            Clustered = true;
            SumIndexFields = "In Review Hours", "Billable Hours", "Billed Hours", "Not Billable Hours";
        }
        key(ReviewWalk; "Review No.", "Project Task No.", "Posting Date", "Jira ID")
        {
        }
    }
}
