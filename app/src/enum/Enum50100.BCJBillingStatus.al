enum 50100 "BCJ Billing Status"
{
    Extensible = false;
    Caption = 'Billing Status';

    value(0; Open)
    {
        Caption = 'Open';
    }
    value(1; Billable)
    {
        Caption = 'Billable';
    }
    value(2; "Not Billable")
    {
        Caption = 'Not Billable';
    }
    value(3; Billed)
    {
        Caption = 'Billed';
    }
}
