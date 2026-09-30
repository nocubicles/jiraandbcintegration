page 50105 "BCJ Customer Review"
{
    Caption = 'Customer Time Review';
    PageType = Card;
    ApplicationArea = All;
    UsageCategory = None;
    SourceTable = "BCJ Customer Review";
    InsertAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'General';

                field("Review No."; Rec."Review No.")
                {
                    ToolTip = 'Specifies the number of the customer review.';
                }
                field("Project No."; Rec."Project No.")
                {
                    ToolTip = 'Specifies the project whose hours were sent to the customer.';
                }
                field("Customer No."; Rec."Customer No.")
                {
                    ToolTip = 'Specifies the bill-to customer of the project when the review was created.';
                }
                field(Status; Rec.Status)
                {
                    ToolTip = 'Specifies whether the review is waiting for the customer, answered, or cancelled.';
                }
                field(ReviewLink; ReviewLink)
                {
                    Caption = 'Review Link';
                    Editable = false;
                    ExtendedDatatype = URL;
                    ToolTip = 'Specifies the link the customer uses to answer the review. Requires the Customer Review Base URL in the Jira Integration Setup.';
                }
            }
            group(Hours)
            {
                Caption = 'Hours';

                field("Logged Hours"; Rec."Logged Hours")
                {
                    ToolTip = 'Specifies the hours logged on the time entries included in this review.';
                }
                field("Hours to Bill"; Rec."Hours to Bill")
                {
                    Style = Strong;
                    ToolTip = 'Specifies the hours you ask the customer to approve. Set them per task in the lines, or for all tasks with Set Hours to Bill %.';
                }
                field("Approved Hours"; Rec."Approved Hours")
                {
                    ToolTip = 'Specifies the hours the customer agreed to be billed.';
                }
                field("Applied Hours"; Rec."Applied Hours")
                {
                    ToolTip = 'Specifies the approved hours that were allocated to time entries.';
                }
            }
            part(Lines; "BCJ Customer Review Subform")
            {
                Caption = 'Tasks';
                SubPageLink = "Review No." = field("Review No.");
                // Editing Hours to Bill on a line must refresh the totals in the header.
                UpdatePropagation = Both;
            }
            group(Communication)
            {
                Caption = 'Communication';

                field("Sent To E-Mail"; Rec."Sent To E-Mail")
                {
                    ToolTip = 'Specifies the address the review was e-mailed to. Blank if no e-mail was sent.';
                }
                field("Sent On"; Rec."Sent On")
                {
                    ToolTip = 'Specifies when the review was sent to the customer.';
                }
                field("E-Mail Sent On"; Rec."E-Mail Sent On")
                {
                    ToolTip = 'Specifies when the review was e-mailed. Blank if no e-mail was sent.';
                }
                field("Answered On"; Rec."Answered On")
                {
                    ToolTip = 'Specifies when the customer answered.';
                }
                field("Cancelled On"; Rec."Cancelled On")
                {
                    ToolTip = 'Specifies when the review was cancelled.';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(SendToCustomer)
            {
                Caption = 'Send to Customer';
                Image = SendApprovalRequest;
                Enabled = Rec.Status = Rec.Status::Draft;
                ToolTip = 'Send the draft review to the customer. The hours you left out of Hours to Bill go back to Open, the review is frozen and e-mailed to the project contact; without an e-mail address, share the review link yourself.';

                trigger OnAction()
                var
                    CustomerReviewMgt: Codeunit "BCJ Customer Review Mgt.";
                begin
                    if not Confirm(SendQst, false, Rec."Review No.") then
                        exit;
                    if CustomerReviewMgt.SendReview(Rec) then
                        Message(EmailSentMsg, Rec."Sent To E-Mail")
                    else
                        Message(SentWithoutEmailMsg);
                    CurrPage.Update(false);
                end;
            }
            action(SendEmail)
            {
                Caption = 'Resend E-Mail';
                Image = SendMail;
                Enabled = Rec.Status = Rec.Status::Sent;
                ToolTip = 'Send the review e-mail to the project contact again.';

                trigger OnAction()
                var
                    ReviewMail: Codeunit "BCJ Review Mail";
                begin
                    if ReviewMail.SendReviewEmail(Rec) then
                        Message(EmailSentMsg, Rec."Sent To E-Mail")
                    else
                        Message(EmailNotSentMsg);
                end;
            }
            action(SetHoursToBillPct)
            {
                Caption = 'Set Hours to Bill %';
                Image = Percentage;
                Enabled = Rec.Status = Rec.Status::Draft;
                ToolTip = 'Set the hours to bill on every task to a percentage of its hours in review, for example 50. You can still change single tasks afterwards.';

                trigger OnAction()
                var
                    PctDialog: Page "BCJ Hours to Bill Pct Dialog";
                    CustomerReviewMgt: Codeunit "BCJ Customer Review Mgt.";
                begin
                    if PctDialog.RunModal() <> Action::OK then
                        exit;
                    CustomerReviewMgt.SetHoursToBillPct(Rec, PctDialog.GetPct());
                    CurrPage.Update(false);
                end;
            }
            action(Cancel)
            {
                Caption = 'Cancel Review';
                Image = Cancel;
                Enabled = (Rec.Status = Rec.Status::Draft) or (Rec.Status = Rec.Status::Sent);
                ToolTip = 'Cancel the review and return its hours in review to Open.';

                trigger OnAction()
                var
                    CustomerReviewMgt: Codeunit "BCJ Customer Review Mgt.";
                begin
                    if not Confirm(CancelQst, false, Rec."Review No.") then
                        exit;
                    CustomerReviewMgt.CancelReview(Rec);
                end;
            }
            action(Reopen)
            {
                Caption = 'Reopen';
                Image = ReOpen;
                Enabled = Rec.Status = Rec.Status::Answered;
                ToolTip = 'Reopen an answered review so the customer can adjust the answer. The approved hours go back into review; hours already billed stay billed.';

                trigger OnAction()
                var
                    CustomerReviewMgt: Codeunit "BCJ Customer Review Mgt.";
                begin
                    if not Confirm(ReopenQst, false, Rec."Review No.") then
                        exit;
                    CustomerReviewMgt.ReopenReview(Rec);
                end;
            }
        }
        area(Navigation)
        {
            action(TimeEntries)
            {
                Caption = 'Time Entries';
                Image = Timesheet;
                ToolTip = 'Open the time entries that belong to this review.';

                trigger OnAction()
                var
                    TimeEntry: Record "BCJ Project Time Entry";
                begin
                    TimeEntry.SetRange("Review No.", Rec."Review No.");
                    Page.Run(Page::"BCJ Jira Time Entry Worksheet", TimeEntry);
                end;
            }
        }
        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Process';

                actionref(SetHoursToBillPct_Promoted; SetHoursToBillPct)
                {
                }
                actionref(SendToCustomer_Promoted; SendToCustomer)
                {
                }
                actionref(SendEmail_Promoted; SendEmail)
                {
                }
                actionref(Cancel_Promoted; Cancel)
                {
                }
                actionref(Reopen_Promoted; Reopen)
                {
                }
                actionref(TimeEntries_Promoted; TimeEntries)
                {
                }
            }
        }
    }

    trigger OnAfterGetCurrRecord()
    var
        Setup: Record "BCJ Jira Integration Setup";
        ReviewMail: Codeunit "BCJ Review Mail";
    begin
        // The card must open even when the base URL is not configured yet.
        ReviewLink := '';
        if Setup.Get() then
            if Setup."Review Base URL" <> '' then
                ReviewLink := ReviewMail.GetReviewLink(Rec);
    end;

    var
        ReviewLink: Text;
        EmailSentMsg: Label 'The review was e-mailed to %1.', Comment = '%1 = e-mail address';
        EmailNotSentMsg: Label 'The review was not sent. The project has no bill-to contact or customer e-mail, or the e-mail could not be sent.';
        CancelQst: Label 'Cancel customer review %1 and return its hours in review to Open?', Comment = '%1 = review no.';
        SendQst: Label 'Send customer review %1 to the customer? The hours left out of Hours to Bill go back to Open and the review can no longer be changed.', Comment = '%1 = review no.';
        SentWithoutEmailMsg: Label 'The review was sent but not e-mailed: the project has no bill-to contact or customer e-mail, or the e-mail could not be sent. Share the review link with the customer yourself.';
        ReopenQst: Label 'Reopen customer review %1? The customer can then change the answer.', Comment = '%1 = review no.';
}
