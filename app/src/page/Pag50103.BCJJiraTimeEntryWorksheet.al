page 50103 "BCJ Jira Time Entry Worksheet"
{
    Caption = 'Jira Time Entry Billing';
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Tasks;
    SourceTable = "BCJ Project Time Entry";
    SourceTableView = sorting("Project No.", "Project Task No.", "Posting Date");
    InsertAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("Bill-to Customer No."; Rec."Bill-to Customer No.")
                {
                    ToolTip = 'Specifies the bill-to customer of the project.';
                }
                field("Project No."; Rec."Project No.")
                {
                    Editable = false;
                    ToolTip = 'Specifies the project (Jira project key).';
                }
                field("Project Description"; Rec."Project Description")
                {
                    ToolTip = 'Specifies the project description.';
                }
                field("Project Task No."; Rec."Project Task No.")
                {
                    Editable = false;
                    ToolTip = 'Specifies the project task (Jira issue key).';
                }
                field("Task Description"; Rec."Task Description")
                {
                    ToolTip = 'Specifies the task description.';
                }
                field(Status; Rec.Status)
                {
                    ToolTip = 'Specifies the status of the issue in Jira.';
                }
                field("BC Resource No."; Rec."BC Resource No.")
                {
                    Editable = false;
                    ToolTip = 'Specifies who logged the time.';
                }
                field("Posting Date"; Rec."Posting Date")
                {
                    Editable = false;
                    ToolTip = 'Specifies the date the time was logged for.';
                }
                field("Time Spent in Hours"; Rec."Time Spent in Hours")
                {
                    Editable = false;
                    ToolTip = 'Specifies the logged time in hours.';
                }
                field(Comment; Rec.Comment)
                {
                    Editable = false;
                    ToolTip = 'Specifies the worklog comment from Jira.';
                }
                field("Billing Status"; Rec."Billing Status")
                {
                    StyleExpr = StatusStyle;
                    ToolTip = 'Specifies whether the time entry is open (not reviewed), sent for customer review, billable, not billable or billed.';
                }
                field("Billable Hours"; Rec."Billable Hours")
                {
                    ToolTip = 'Specifies the hours to bill for this entry. Equal to the logged hours unless the customer approved only part of the hours of the task.';
                }
                field("Review No."; Rec."Review No.")
                {
                    Visible = false;
                    ToolTip = 'Specifies the customer review the entry was sent with.';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            group(MarkAs)
            {
                Caption = 'Mark Selected As';
                Image = Approve;

                action(MarkBillable)
                {
                    Caption = 'Billable';
                    Image = Approve;
                    ToolTip = 'Mark the selected time entries as billable.';

                    trigger OnAction()
                    begin
                        SetStatusForSelection("BCJ Billing Status"::Billable);
                    end;
                }
                action(MarkNotBillable)
                {
                    Caption = 'Not Billable';
                    Image = Reject;
                    ToolTip = 'Mark the selected time entries as not billable.';

                    trigger OnAction()
                    begin
                        SetStatusForSelection("BCJ Billing Status"::"Not Billable");
                    end;
                }
                action(MarkBilled)
                {
                    Caption = 'Billed';
                    Image = Invoice;
                    ToolTip = 'Mark the selected time entries as billed.';

                    trigger OnAction()
                    begin
                        SetStatusForSelection("BCJ Billing Status"::Billed);
                    end;
                }
                action(MarkOpen)
                {
                    Caption = 'Open';
                    Image = ReOpen;
                    ToolTip = 'Reset the selected time entries to open (not reviewed).';

                    trigger OnAction()
                    begin
                        SetStatusForSelection("BCJ Billing Status"::Open);
                    end;
                }
            }
        }
        area(Navigation)
        {
            action(BillingOverview)
            {
                Caption = 'Billing Overview';
                Image = ViewDetails;
                RunObject = page "BCJ Jira Billing Overview";
                ToolTip = 'Open the customer, project and task overview of logged and unbilled hours.';
            }
        }
        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Process';

                actionref(MarkBillable_Promoted; MarkBillable)
                {
                }
                actionref(MarkNotBillable_Promoted; MarkNotBillable)
                {
                }
                actionref(MarkBilled_Promoted; MarkBilled)
                {
                }
                actionref(MarkOpen_Promoted; MarkOpen)
                {
                }
            }
        }
    }

    views
    {
        view(Unbilled)
        {
            Caption = 'Unbilled';
            Filters = where("Billing Status" = filter(Open | "Sent for Review" | Billable));
        }
        view(InReview)
        {
            Caption = 'Sent for Review';
            Filters = where("Billing Status" = const("Sent for Review"));
        }
        view(OpenEntries)
        {
            Caption = 'To Review';
            Filters = where("Billing Status" = const(Open));
        }
        view(BillableEntries)
        {
            Caption = 'Ready to Bill';
            Filters = where("Billing Status" = const(Billable));
        }
    }

    trigger OnAfterGetRecord()
    begin
        case Rec."Billing Status" of
            Rec."Billing Status"::Billable:
                StatusStyle := 'Attention';
            Rec."Billing Status"::Billed:
                StatusStyle := 'Favorable';
            Rec."Billing Status"::"Not Billable":
                StatusStyle := 'Subordinate';
            Rec."Billing Status"::"Sent for Review":
                StatusStyle := 'Ambiguous';
            else
                StatusStyle := 'Standard';
        end;
    end;

    var
        StatusStyle: Text;
        EntriesUpdatedMsg: Label '%1 time entries updated.', Comment = '%1 = number of time entries';
        EntriesInReviewMsg: Label '%1 time entries were not changed because they are waiting for a customer answer.', Comment = '%1 = number of time entries';

    local procedure SetStatusForSelection(NewStatus: Enum "BCJ Billing Status")
    var
        TimeEntry: Record "BCJ Project Time Entry";
        BillingMgt: Codeunit "BCJ Billing Mgt.";
        ChangedCount: Integer;
        InReviewCount: Integer;
    begin
        CurrPage.SetSelectionFilter(TimeEntry);
        ChangedCount := BillingMgt.SetBillingStatus(TimeEntry, NewStatus);
        InReviewCount := BillingMgt.CountEntriesInReview(TimeEntry);
        CurrPage.Update(false);
        if InReviewCount > 0 then
            Message(EntriesUpdatedMsg + ' ' + EntriesInReviewMsg, ChangedCount, InReviewCount)
        else
            Message(EntriesUpdatedMsg, ChangedCount);
    end;
}
