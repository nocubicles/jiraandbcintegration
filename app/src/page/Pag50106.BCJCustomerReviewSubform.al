page 50106 "BCJ Customer Review Subform"
{
    Caption = 'Customer Time Review Lines';
    PageType = ListPart;
    ApplicationArea = All;
    SourceTable = "BCJ Customer Review Line";
    InsertAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("Project Task No."; Rec."Project Task No.")
                {
                    Editable = false;
                    ToolTip = 'Specifies the project task (Jira issue key).';
                }
                field("Task Description"; Rec."Task Description")
                {
                    Editable = false;
                    ToolTip = 'Specifies the task description when the review was created.';
                }
                field("Task Logged Hours"; Rec."Task Logged Hours")
                {
                    Editable = false;
                    ToolTip = 'Specifies all hours ever logged on the task when the review was created. The customer sees this as Logged.';
                }
                field("Task Billed Hours"; Rec."Task Billed Hours")
                {
                    Editable = false;
                    ToolTip = 'Specifies the hours on the task that were billed, or approved for billing, before this review. The customer sees this as Billed.';
                }
                field("Task Not Billable Hours"; Rec."Task Not Billable Hours")
                {
                    Editable = false;
                    ToolTip = 'Specifies the hours on the task that were written off before this review. The customer sees this as Not billable.';
                }
                field("Task Not Billed Hours"; Rec."Task Not Billed Hours")
                {
                    Editable = false;
                    ToolTip = 'Specifies the hours on the task not billed yet, including the hours in this review. The customer sees this as Not billed.';
                }
                field("Logged Hours"; Rec."Logged Hours")
                {
                    Editable = false;
                    ToolTip = 'Specifies the hours logged on the task that are included in this review.';
                }
                field("Hours to Bill"; Rec."Hours to Bill")
                {
                    Editable = CanEditHoursToBill;
                    Style = Strong;
                    ToolTip = 'Specifies the hours you ask the customer to approve for this task, between 0 and the hours in this review. The customer can approve up to this amount.';

                    trigger OnValidate()
                    begin
                        CurrPage.Update(true);
                    end;
                }
                field("Approved Hours"; Rec."Approved Hours")
                {
                    Editable = false;
                    ToolTip = 'Specifies the hours the customer agreed to be billed for this task.';
                }
                field("Customer Comment"; Rec."Customer Comment")
                {
                    Editable = false;
                    ToolTip = 'Specifies the comment the customer entered for this task.';
                }
                field("Applied Hours"; Rec."Applied Hours")
                {
                    Editable = false;
                    ToolTip = 'Specifies the approved hours that were allocated to time entries. Lower than the approved hours if entries were deleted or shortened in Jira after sending.';
                }
                field("Entry Count"; Rec."Entry Count")
                {
                    Editable = false;
                    ToolTip = 'Specifies how many time entries were included when the review was created.';
                }
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        Review: Record "BCJ Customer Review";
    begin
        // Hours to Bill can only change while the customer has not answered.
        CanEditHoursToBill := false;
        Review.SetLoadFields(Status);
        if Review.Get(Rec."Review No.") then
            CanEditHoursToBill := Review.Status = Review.Status::Sent;
    end;

    var
        CanEditHoursToBill: Boolean;
}
