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
                field("Is Posted"; Rec."Transfer To Job Journal")
                {

                }
                field("Skip transfer to Job Journal"; Rec."Skip transfer to Job Journal")
                {

                }
            }
        }
    }

    actions
    {
        area(Promoted)
        {
            actionref(CreateJournal; CreateJournalEntries)
            { }
        }
        area(Processing)
        {
            action(CreateJournalEntries)
            {
                ApplicationArea = All;
                Caption = 'Create Project Journal Entries';
                Image = Journals;
                trigger OnAction()
                var
                    PostJiraTimeToJob: Codeunit "BCJ Post Jira Time To Job";
                begin
                    PostJiraTimeToJob.ProcessUnpostedJiraTimeEntries();
                end;
            }
        }
    }
}