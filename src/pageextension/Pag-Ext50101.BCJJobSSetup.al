pageextension 50101 "BCJ JobS Setup" extends "Jobs Setup"
{
    layout
    {
        addlast(content)
        {
            group("BCJ JiraIntegration")
            {
                Caption = 'Jira Integration';
                field("BCJ Job Journal Templ."; Rec."BCJ Job Journal Templ.")
                {
                    ApplicationArea = All;
                }
                field("BCJ Job Journal Batch"; Rec."BCJ Job Journal Batch")
                {
                    ApplicationArea = All;
                }
            }
        }
    }
}