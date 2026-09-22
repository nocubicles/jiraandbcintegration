codeunit 50108 "BCJ Review Mail"
{
    var
        SubjectLbl: Label 'Please review the hours logged on project %1 %2', Comment = '%1 = project no., %2 = project description';
        IntroLbl: Label 'Below are the hours we logged on your project %1. Please open the review link, confirm the hours you approve for each task, and submit your answer.', Comment = '%1 = project description or no.';
        TaskHdrLbl: Label 'Task';
        DescriptionHdrLbl: Label 'Description';
        HoursHdrLbl: Label 'Hours';
        TotalLbl: Label 'Total';
        OpenReviewLbl: Label 'Open the review';
        LinkHintLbl: Label 'If the button does not work, copy this address into your browser: %1', Comment = '%1 = review link';

    /// <summary>
    /// Errors when the customer review base URL is not configured.
    /// </summary>
    procedure CheckSetup()
    var
        Setup: Record "BCJ Jira Integration Setup";
    begin
        if not Setup.Get() then
            Setup.Init();
        Setup.TestField("Review Base URL");
    end;

    /// <summary>
    /// Returns the link the customer opens to answer the review: base URL + /review/ + access token.
    /// </summary>
    procedure GetReviewLink(Review: Record "BCJ Customer Review"): Text
    var
        Setup: Record "BCJ Jira Integration Setup";
        BaseUrl: Text;
    begin
        CheckSetup();
        Setup.Get();
        BaseUrl := Setup."Review Base URL".Trim();
        while BaseUrl.EndsWith('/') do
            BaseUrl := CopyStr(BaseUrl, 1, StrLen(BaseUrl) - 1);
        exit(BaseUrl + '/review/' + Review."Access Token");
    end;

    /// <summary>
    /// Resolves the recipient: the project's bill-to contact e-mail, else the bill-to customer's e-mail, else blank.
    /// </summary>
    procedure GetRecipientEmail(Review: Record "BCJ Customer Review"): Text[80]
    var
        Job: Record Job;
        Contact: Record Contact;
        Customer: Record Customer;
    begin
        Job.SetLoadFields("Bill-to Contact No.", "Bill-to Customer No.");
        if not Job.Get(Review."Project No.") then
            exit('');
        if Job."Bill-to Contact No." <> '' then begin
            Contact.SetLoadFields("E-Mail");
            if Contact.Get(Job."Bill-to Contact No.") then
                if Contact."E-Mail" <> '' then
                    exit(Contact."E-Mail");
        end;
        if Job."Bill-to Customer No." <> '' then begin
            Customer.SetLoadFields("E-Mail");
            if Customer.Get(Job."Bill-to Customer No.") then
                exit(Customer."E-Mail");
        end;
        exit('');
    end;

    /// <summary>
    /// Builds the review e-mail message without sending it: one row per task with the logged hours, a total, and the review link.
    /// </summary>
    procedure BuildReviewEmail(Review: Record "BCJ Customer Review"; Recipient: Text; var EmailMessage: Codeunit "Email Message")
    var
        Job: Record Job;
        ReviewLine: Record "BCJ Customer Review Line";
        Link: Text;
        Body: TextBuilder;
        TotalHours: Decimal;
        ProjectDescription: Text;
    begin
        Link := GetReviewLink(Review);
        Job.SetLoadFields(Description);
        if Job.Get(Review."Project No.") then
            ProjectDescription := Job.Description;
        if ProjectDescription = '' then
            ProjectDescription := Review."Project No.";

        Body.AppendLine('<html><body style="font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#222">');
        Body.AppendLine('<p>' + Html(StrSubstNo(IntroLbl, ProjectDescription)) + '</p>');
        Body.AppendLine('<table cellpadding="6" cellspacing="0" style="border-collapse:collapse;border:1px solid #ccc">');
        Body.AppendLine('<tr style="background:#f2f2f2"><th align="left">' + Html(TaskHdrLbl) + '</th><th align="left">' + Html(DescriptionHdrLbl) + '</th><th align="right">' + Html(HoursHdrLbl) + '</th></tr>');
        ReviewLine.SetRange("Review No.", Review."Review No.");
        if ReviewLine.FindSet() then
            repeat
                TotalHours += ReviewLine."Logged Hours";
                Body.AppendLine('<tr><td style="border-top:1px solid #ddd">' + Html(ReviewLine."Project Task No.") +
                    '</td><td style="border-top:1px solid #ddd">' + Html(ReviewLine."Task Description") +
                    '</td><td align="right" style="border-top:1px solid #ddd">' + FormatHours(ReviewLine."Logged Hours") + '</td></tr>');
            until ReviewLine.Next() = 0;
        Body.AppendLine('<tr><td colspan="2" style="border-top:2px solid #999"><b>' + Html(TotalLbl) + '</b></td><td align="right" style="border-top:2px solid #999"><b>' + FormatHours(TotalHours) + '</b></td></tr>');
        Body.AppendLine('</table>');
        Body.AppendLine('<p style="margin:24px 0"><a href="' + Html(Link) + '" style="background:#0b5cad;color:#fff;padding:10px 18px;text-decoration:none;border-radius:6px">' + Html(OpenReviewLbl) + '</a></p>');
        Body.AppendLine('<p style="color:#666;font-size:12px">' + Html(StrSubstNo(LinkHintLbl, Link)) + '</p>');
        Body.AppendLine('</body></html>');

        EmailMessage.Create(Recipient, StrSubstNo(SubjectLbl, Review."Project No.", ProjectDescription), Body.ToText(), true);
    end;

    /// <summary>
    /// Builds and sends the review e-mail and stamps the review. Returns false when there is no recipient or sending failed.
    /// </summary>
    procedure SendReviewEmail(var Review: Record "BCJ Customer Review"): Boolean
    var
        EmailMessage: Codeunit "Email Message";
        Recipient: Text[80];
    begin
        Recipient := GetRecipientEmail(Review);
        if Recipient = '' then
            exit(false);
        BuildReviewEmail(Review, Recipient, EmailMessage);
        if not TrySend(EmailMessage) then
            exit(false);
        Review."Sent To E-Mail" := Recipient;
        Review."E-Mail Sent On" := CurrentDateTime();
        Review.Modify(false);
        exit(true);
    end;

    [TryFunction]
    local procedure TrySend(var EmailMessage: Codeunit "Email Message")
    var
        Email: Codeunit Email;
    begin
        if not Email.Send(EmailMessage, Enum::"Email Scenario"::"BCJ Customer Time Review") then
            Error('');
    end;

    local procedure FormatHours(Hours: Decimal): Text
    begin
        exit(Format(Hours, 0, '<Precision,2:2><Standard Format,0>'));
    end;

    local procedure Html(Value: Text): Text
    begin
        Value := Value.Replace('&', '&amp;');
        Value := Value.Replace('<', '&lt;');
        Value := Value.Replace('>', '&gt;');
        Value := Value.Replace('"', '&quot;');
        exit(Value);
    end;
}
