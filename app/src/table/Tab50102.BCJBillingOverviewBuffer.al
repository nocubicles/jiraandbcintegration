table 50102 "BCJ Billing Overview Buffer"
{
    Caption = 'Jira Billing Overview Buffer';
    TableType = Temporary;
    DataClassification = SystemMetadata;

    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
        }
        field(2; "Line Type"; Enum "BCJ Overview Line Type")
        {
            Caption = 'Line Type';
        }
        field(3; Indentation; Integer)
        {
            Caption = 'Indentation';
        }
        field(4; "Customer No."; Code[20])
        {
            Caption = 'Customer No.';
            TableRelation = Customer."No.";
        }
        field(5; "Project No."; Code[20])
        {
            Caption = 'Project No.';
            TableRelation = Job."No.";
        }
        field(6; "Project Task No."; Code[20])
        {
            Caption = 'Project Task No.';
        }
        field(7; "Jira ID"; Text[50])
        {
            Caption = 'Jira Worklog ID';
        }
        field(8; "Jira Issue Id"; Text[50])
        {
            Caption = 'Jira Issue Id';
        }
        field(9; Description; Text[250])
        {
            Caption = 'Description';
        }
        field(10; "Resource No."; Code[20])
        {
            Caption = 'Resource No.';
            TableRelation = Resource."No.";
        }
        field(11; "Posting Date"; Date)
        {
            Caption = 'Posting Date';
        }
        field(12; "Billing Status"; Enum "BCJ Billing Status")
        {
            Caption = 'Billing Status';
        }
        field(13; "Jira Status"; Code[250])
        {
            Caption = 'Status in Jira';
        }
        field(20; "Total Hours"; Decimal)
        {
            Caption = 'Total Hours';
            DecimalPlaces = 0 : 2;
        }
        field(21; "Open Hours"; Decimal)
        {
            Caption = 'Open Hours';
            DecimalPlaces = 0 : 2;
        }
        field(22; "Billable Hours"; Decimal)
        {
            Caption = 'Billable Hours';
            DecimalPlaces = 0 : 2;
        }
        field(23; "Not Billable Hours"; Decimal)
        {
            Caption = 'Not Billable Hours';
            DecimalPlaces = 0 : 2;
        }
        field(24; "Billed Hours"; Decimal)
        {
            Caption = 'Billed Hours';
            DecimalPlaces = 0 : 2;
        }
        field(25; "Unbilled Hours"; Decimal)
        {
            Caption = 'Unbilled Hours';
            DecimalPlaces = 0 : 2;
        }
        field(26; "Sent for Review Hours"; Decimal)
        {
            Caption = 'Sent for Review Hours';
            DecimalPlaces = 0 : 2;
        }
        field(27; "Allocated Hours"; Decimal)
        {
            Caption = 'Allocated Hours';
            DecimalPlaces = 0 : 2;
        }
    }
    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
        key(Tree; "Customer No.", "Project No.", "Project Task No.", "Posting Date", "Jira ID")
        {
        }
    }
}
