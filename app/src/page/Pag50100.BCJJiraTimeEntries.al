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
                field("Project Description"; Rec."Project Description")
                {
                }
                field("Project Task No."; Rec."Project Task No.")
                {
                    ToolTip = 'Specifies the value of the Project Task No. field.';
                }
                field("Task Description"; Rec."Task Description")
                {
                }
                field(Status; Rec.Status)
                {
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
                field("Is Billable"; Rec."Is Billable")
                {
                    ApplicationArea = All;
                }
                field("Is Billed"; Rec."Is Billed")
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
            {
            }
            actionref(MarkBillableActionRef; MarkSelectedAsBillable)
            {
            }
            actionref(MarkBilledActionRef; MarkSelectedAsBilled)
            {
            }
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
            action(MarkSelectedAsBillable)
            {
                ApplicationArea = All;
                Caption = 'Mark Selected Entries As Billable';
                Image = Journals;

                trigger OnAction()
                var
                    JiraEntries: Record "BCJ Project Time Entry";
                    BillingMgt: Codeunit "BCJ Billing Mgt.";
                begin
                    CurrPage.SetSelectionFilter(JiraEntries);
                    BillingMgt.SetBillingStatus(JiraEntries, "BCJ Billing Status"::Billable);
                    CurrPage.Update(false);
                end;
            }
            action(MarkSelectedAsBilled)
            {
                ApplicationArea = All;
                Caption = 'Mark Selected Entries As Billed';
                Image = Journals;

                trigger OnAction()
                var
                    JiraEntries: Record "BCJ Project Time Entry";
                    BillingMgt: Codeunit "BCJ Billing Mgt.";
                begin
                    // Billing from this page bills the Open hours too, as it always did.
                    CurrPage.SetSelectionFilter(JiraEntries);
                    BillingMgt.SetBillingStatus(JiraEntries, "BCJ Billing Status"::Billable);
                    BillingMgt.SetBillingStatus(JiraEntries, "BCJ Billing Status"::Billed);
                    CurrPage.Update(false);
                end;
            }
        }
    }
}
