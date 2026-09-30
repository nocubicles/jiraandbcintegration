page 50104 "BCJ Customer Reviews"
{
    Caption = 'Customer Time Reviews';
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Lists;
    SourceTable = "BCJ Customer Review";
    CardPageId = "BCJ Customer Review";
    Editable = false;
    InsertAllowed = false;
    SourceTableView = sorting("Review No.") order(descending);

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
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
                field("Logged Hours"; Rec."Logged Hours")
                {
                    ToolTip = 'Specifies the hours sent to the customer.';
                }
                field("Approved Hours"; Rec."Approved Hours")
                {
                    ToolTip = 'Specifies the hours the customer agreed to be billed.';
                }
                field("Applied Hours"; Rec."Applied Hours")
                {
                    ToolTip = 'Specifies the approved hours that were allocated to time entries.';
                }
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
                field(SystemCreatedAt; Rec.SystemCreatedAt)
                {
                    Caption = 'Created On';
                    ToolTip = 'Specifies when the review was created.';
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
            action(CopyLink)
            {
                Caption = 'Copy Review Link';
                Image = Link;
                ToolTip = 'Show the link the customer uses to answer the review, so you can copy it.';

                trigger OnAction()
                var
                    ReviewMail: Codeunit "BCJ Review Mail";
                begin
                    Message('%1', ReviewMail.GetReviewLink(Rec));
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
        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Process';

                actionref(SendToCustomer_Promoted; SendToCustomer)
                {
                }
                actionref(SendEmail_Promoted; SendEmail)
                {
                }
                actionref(CopyLink_Promoted; CopyLink)
                {
                }
                actionref(Cancel_Promoted; Cancel)
                {
                }
                actionref(Reopen_Promoted; Reopen)
                {
                }
            }
        }
    }

    var
        EmailSentMsg: Label 'The review was e-mailed to %1.', Comment = '%1 = e-mail address';
        EmailNotSentMsg: Label 'The review was not sent. The project has no bill-to contact or customer e-mail, or the e-mail could not be sent.';
        CancelQst: Label 'Cancel customer review %1 and return its hours in review to Open?', Comment = '%1 = review no.';
        SendQst: Label 'Send customer review %1 to the customer? The hours left out of Hours to Bill go back to Open and the review can no longer be changed.', Comment = '%1 = review no.';
        SentWithoutEmailMsg: Label 'The review was sent but not e-mailed: the project has no bill-to contact or customer e-mail, or the e-mail could not be sent. Share the review link with the customer yourself.';
        ReopenQst: Label 'Reopen customer review %1? The customer can then change the answer.', Comment = '%1 = review no.';
}
