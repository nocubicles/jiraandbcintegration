table 50103 "BCJ Customer Review"
{
    Caption = 'Customer Time Review';
    DataClassification = CustomerContent;
    LookupPageId = "BCJ Customer Reviews";
    DrillDownPageId = "BCJ Customer Reviews";

    fields
    {
        field(1; "Review No."; Integer)
        {
            Caption = 'Review No.';
            AutoIncrement = true;
            Editable = false;
        }
        field(2; "Project No."; Code[20])
        {
            Caption = 'Project No.';
            TableRelation = Job."No.";
            Editable = false;
        }
        field(3; "Customer No."; Code[20])
        {
            Caption = 'Customer No.';
            TableRelation = Customer."No.";
            Editable = false;
        }
        field(4; Status; Enum "BCJ Review Status")
        {
            Caption = 'Status';
            Editable = false;
        }
        field(5; "Access Token"; Text[50])
        {
            Caption = 'Access Token';
            Editable = false;
        }
        field(6; "Sent To E-Mail"; Text[80])
        {
            Caption = 'Sent To E-Mail';
            Editable = false;
        }
        field(7; "E-Mail Sent On"; DateTime)
        {
            Caption = 'E-Mail Sent On';
            Editable = false;
        }
        field(8; "Answered On"; DateTime)
        {
            Caption = 'Answered On';
            Editable = false;
        }
        field(9; "Cancelled On"; DateTime)
        {
            Caption = 'Cancelled On';
            Editable = false;
        }
        field(10; "Sent On"; DateTime)
        {
            Caption = 'Sent On';
            Editable = false;
            DataClassification = SystemMetadata;
        }
        field(20; "Logged Hours"; Decimal)
        {
            Caption = 'Logged Hours';
            DecimalPlaces = 0 : 2;
            FieldClass = FlowField;
            CalcFormula = sum("BCJ Customer Review Line"."Logged Hours" where("Review No." = field("Review No.")));
            Editable = false;
        }
        field(21; "Approved Hours"; Decimal)
        {
            Caption = 'Approved Hours';
            DecimalPlaces = 0 : 2;
            FieldClass = FlowField;
            CalcFormula = sum("BCJ Customer Review Line"."Approved Hours" where("Review No." = field("Review No.")));
            Editable = false;
        }
        field(22; "Applied Hours"; Decimal)
        {
            Caption = 'Applied Hours';
            DecimalPlaces = 0 : 2;
            FieldClass = FlowField;
            CalcFormula = sum("BCJ Customer Review Line"."Applied Hours" where("Review No." = field("Review No.")));
            Editable = false;
        }
        field(23; "Hours to Bill"; Decimal)
        {
            Caption = 'Hours to Bill';
            DecimalPlaces = 0 : 2;
            FieldClass = FlowField;
            CalcFormula = sum("BCJ Customer Review Line"."Hours to Bill" where("Review No." = field("Review No.")));
            Editable = false;
        }
    }
    keys
    {
        key(PK; "Review No.")
        {
            Clustered = true;
        }
        key(Token; "Access Token")
        {
        }
        key(ProjectStatus; "Project No.", Status)
        {
        }
    }

    trigger OnDelete()
    var
        ReviewLine: Record "BCJ Customer Review Line";
        HourAllocationMgt: Codeunit "BCJ Hour Allocation Mgt.";
    begin
        if not (Status in [Status::Draft, Status::Cancelled]) then
            Error(CannotDeleteReviewErr);
        // A deleted draft gives its hours back.
        HourAllocationMgt.ReleaseReview("Review No.");
        HourAllocationMgt.DeleteEmptyReviewRows("Review No.");
        ReviewLine.SetRange("Review No.", "Review No.");
        ReviewLine.DeleteAll(false);
    end;

    var
        CannotDeleteReviewErr: Label 'Only a draft or cancelled customer review can be deleted. Cancel the review first.';
}
