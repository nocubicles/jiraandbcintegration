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
                if ("Approved Hours" < 0) or ("Approved Hours" > "Logged Hours") then
                    Error(ApprovedHoursOutOfRangeErr, "Logged Hours");
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
        ApprovedHoursOutOfRangeErr: Label 'The approved hours must be between 0 and %1.', Comment = '%1 = logged hours on the line';
}
