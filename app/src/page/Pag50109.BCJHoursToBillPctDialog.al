page 50109 "BCJ Hours to Bill Pct Dialog"
{
    Caption = 'Set Hours to Bill %';
    PageType = StandardDialog;
    ApplicationArea = All;
    UsageCategory = None;

    layout
    {
        area(Content)
        {
            field(PctCtrl; Pct)
            {
                Caption = 'Percentage of Logged Hours';
                DecimalPlaces = 0 : 2;
                MinValue = 0;
                MaxValue = 100;
                ToolTip = 'Specifies the percentage of the logged hours to ask the customer to approve on every task, for example 50.';
            }
        }
    }

    trigger OnOpenPage()
    begin
        Pct := 100;
    end;

    var
        Pct: Decimal;

    procedure GetPct(): Decimal
    begin
        exit(Pct);
    end;
}
