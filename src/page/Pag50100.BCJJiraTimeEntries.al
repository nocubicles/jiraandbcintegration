page 50100 "BCJ Jira Time Entries"
{
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Administration;
    SourceTable = "BCJ Project Time Entry";

    layout
    {
        area(Content)
        {
            repeater(GroupName)
            {

                field("Entry No"; Rec."Entry No")
                {
                    ToolTip = 'Specifies the value of the Entry No. field.';
                }
                field("Jira ID"; Rec."Jira ID")
                {
                    ToolTip = 'Specifies the value of the Jira ID field.';
                }
                field("BC Resource No."; Rec."BC Resource No.")
                {
                    ToolTip = 'Specifies the value of the Resource No. field.';
                }
                field("Posting Date"; Rec."Posting Date")
                {
                    ToolTip = 'Specifies the value of the Posting Date field.';
                }
                field("Project No."; Rec."Project No.")
                {
                    ToolTip = 'Specifies the value of the Project No. field.';
                }
                field("Project Task No."; Rec."Project Task No.")
                {
                    ToolTip = 'Specifies the value of the Project Task No. field.';
                }
                field("Time Spend Seconds"; Rec."Time Spend Seconds")
                {
                    ToolTip = 'Specifies the value of the Time Spent in Seconds field.';
                }
                field("Time Spent in Hours"; Rec."Time Spent in Hours")
                {
                    ToolTip = 'Specifies the value of the Time Spent in Hours field.';
                }
                field(Comment; Rec.Comment)
                {

                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(ActionName)
            {
                ApplicationArea = All;

                trigger OnAction()
                begin

                end;
            }
        }
    }
}