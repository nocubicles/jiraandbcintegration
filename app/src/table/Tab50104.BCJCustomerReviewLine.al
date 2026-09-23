table 50104 "BCJ Customer Review Line"
{
    Caption = 'Customer Time Review Line';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Review No."; Integer)
        {
            Caption = 'Review No.';
            TableRelation = "BCJ Customer Review"."Review No.";
            Editable = false;
        }
        field(2; "Project Task No."; Code[20])
        {
            Caption = 'Project Task No.';
            Editable = false;
        }
        field(3; "Task Description"; Text[100])
        {
            Caption = 'Task Description';
            Editable = false;
        }
        field(4; "Logged Hours"; Decimal)
        {
            Caption = 'Logged Hours';
            DecimalPlaces = 0 : 2;
            Editable = false;
        }
        field(5; "Approved Hours"; Decimal)
        {
            Caption = 'Approved Hours';
            DecimalPlaces = 0 : 2;
            MinValue = 0;

            trigger OnValidate()
            begin
                if ("Approved Hours" < 0) or ("Approved Hours" > "Hours to Bill") then
                    Error(ApprovedHoursOutOfRangeErr, "Hours to Bill");
            end;
        }
        field(6; "Customer Comment"; Text[250])
        {
            Caption = 'Customer Comment';
        }
        field(7; "Applied Hours"; Decimal)
        {
            Caption = 'Applied Hours';
            DecimalPlaces = 0 : 2;
            Editable = false;
        }
        field(8; "Entry Count"; Integer)
        {
            Caption = 'Entry Count';
            Editable = false;
        }
        field(9; "Hours to Bill"; Decimal)
        {
            Caption = 'Hours to Bill';
            DecimalPlaces = 0 : 2;
            MinValue = 0;

            trigger OnValidate()
            begin
                if ("Hours to Bill" < 0) or ("Hours to Bill" > "Logged Hours") then
                    Error(HoursToBillOutOfRangeErr, "Logged Hours");
                // The customer can never have approved more than is asked.
                if "Approved Hours" > "Hours to Bill" then
                    "Approved Hours" := "Hours to Bill";
            end;
        }
        field(10; "Task Logged Hours"; Decimal)
        {
            Caption = 'Task Logged Hours';
            DecimalPlaces = 0 : 2;
            Editable = false;
        }
        field(11; "Task Billed Hours"; Decimal)
        {
            Caption = 'Task Billed Hours';
            DecimalPlaces = 0 : 2;
            Editable = false;
        }
        field(12; "Task Not Billable Hours"; Decimal)
        {
            Caption = 'Task Not Billable Hours';
            DecimalPlaces = 0 : 2;
            Editable = false;
        }
        field(13; "Task Not Billed Hours"; Decimal)
        {
            Caption = 'Task Not Billed Hours';
            DecimalPlaces = 0 : 2;
            Editable = false;
        }
    }
    keys
    {
        key(PK; "Review No.", "Project Task No.")
        {
            Clustered = true;
        }
    }

    trigger OnModify()
    var
        Review: Record "BCJ Customer Review";
    begin
        // The customer's answer is frozen once applied or cancelled. Internal writes use Modify(false).
        Review.Get("Review No.");
        Review.TestField(Status, Review.Status::Sent);
    end;

    var
        ApprovedHoursOutOfRangeErr: Label 'The approved hours must be between 0 and %1.', Comment = '%1 = hours to bill on the line';
        HoursToBillOutOfRangeErr: Label 'The hours to bill must be between 0 and %1, the hours logged in this review.', Comment = '%1 = logged hours on the line';
}
