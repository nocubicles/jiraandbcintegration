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
                    ToolTip = 'Specifies what the time entry needs next: hours in review, open hours, hours to bill, or billed / not billable when nothing else is left. The hour columns show how its logged hours are split.';
                }
                field("Open Hours"; Rec."Open Hours")
                {
                    ToolTip = 'Specifies the unbilled hours that are free: not in a review, not approved and not written off.';
                }
                field("In Review Hours"; Rec."In Review Hours")
                {
                    ToolTip = 'Specifies the hours reserved in a draft customer review or waiting for the customer''s answer.';
                }
                field("Billable Hours"; Rec."Billable Hours")
                {
                    ToolTip = 'Specifies the hours approved, by the customer or by you, and waiting to be billed.';
                }
                field("Billed Hours"; Rec."Billed Hours")
                {
                    ToolTip = 'Specifies the hours already billed.';
                }
                field("Not Billable Hours"; Rec."Not Billable Hours")
                {
                    ToolTip = 'Specifies the hours written off.';
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
                    ToolTip = 'Undo your own decisions on the selected time entries: billed hours go back to billable, otherwise hours you marked billable or not billable go back to open. Hours approved in a customer review are taken back only by reopening the review.';

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
            Filters = where("Unbilled Hours" = filter(<> 0));
        }
        view(InReview)
        {
            Caption = 'In Review';
            Filters = where("In Review Hours" = filter(<> 0));
        }
        view(OpenEntries)
        {
            Caption = 'To Review';
            Filters = where("Open Hours" = filter(<> 0));
        }
        view(BillableEntries)
        {
            Caption = 'Ready to Bill';
            Filters = where("Billable Hours" = filter(<> 0));
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
        EntriesInReviewMsg: Label '%1 time entries have hours in a customer review; those hours were not changed.', Comment = '%1 = number of time entries';
        UnbillQst: Label '%1 of the selected time entries have billed hours. Open takes their billed hours back to Billable. Continue?', Comment = '%1 = number of time entries with billed hours';

    local procedure SetStatusForSelection(NewStatus: Enum "BCJ Billing Status")
    var
        TimeEntry: Record "BCJ Project Time Entry";
        BilledEntry: Record "BCJ Project Time Entry";
        BillingMgt: Codeunit "BCJ Billing Mgt.";
        ChangedCount: Integer;
        InReviewCount: Integer;
    begin
        CurrPage.SetSelectionFilter(TimeEntry);
        if NewStatus = NewStatus::Open then begin
            BilledEntry.CopyFilters(TimeEntry);
            BilledEntry.SetFilter("Billed Hours", '<>0');
            if not BilledEntry.IsEmpty() then
                if not Confirm(UnbillQst, false, BilledEntry.Count()) then
                    exit;
        end;
        ChangedCount := BillingMgt.SetBillingStatus(TimeEntry, NewStatus);
        InReviewCount := BillingMgt.CountEntriesInReview(TimeEntry);
        CurrPage.Update(false);
        if InReviewCount > 0 then
            Message(EntriesUpdatedMsg + ' ' + EntriesInReviewMsg, ChangedCount, InReviewCount)
        else
            Message(EntriesUpdatedMsg, ChangedCount);
    end;
}
