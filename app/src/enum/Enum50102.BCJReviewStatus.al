enum 50102 "BCJ Review Status"
{
    Extensible = false;
    Caption = 'Review Status';

    value(0; Sent)
    {
        Caption = 'Sent for Review';
    }
    value(1; Answered)
    {
        Caption = 'Answered';
    }
    value(2; Cancelled)
    {
        Caption = 'Cancelled';
    }
    value(3; Draft)
    {
        Caption = 'Draft';
    }
}
