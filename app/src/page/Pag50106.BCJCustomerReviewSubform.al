page 50106 "BCJ Customer Review Subform"
{
    Caption = 'Customer Time Review Lines';
    PageType = ListPart;
    ApplicationArea = All;
    SourceTable = "BCJ Customer Review Line";
    Editable = false;
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
                    ToolTip = 'Specifies the project task (Jira issue key).';
                }
                field("Task Description"; Rec."Task Description")
                {
                    ToolTip = 'Specifies the task description when the review was created.';
                }
                field("Logged Hours"; Rec."Logged Hours")
                {
                    ToolTip = 'Specifies the hours logged on the task that were sent to the customer.';
                }
                field("Approved Hours"; Rec."Approved Hours")
                {
                    ToolTip = 'Specifies the hours the customer agreed to be billed for this task.';
                }
                field("Customer Comment"; Rec."Customer Comment")
                {
                    ToolTip = 'Specifies the comment the customer entered for this task.';
                }
                field("Applied Hours"; Rec."Applied Hours")
                {
                    ToolTip = 'Specifies the approved hours that were allocated to time entries. Lower than the approved hours if entries were deleted or shortened in Jira after sending.';
                }
                field("Entry Count"; Rec."Entry Count")
                {
                    ToolTip = 'Specifies how many time entries were included when the review was created.';
                }
            }
        }
    }
}
