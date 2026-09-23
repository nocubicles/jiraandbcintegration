codeunit 50108 "BCJ Review Mail"
{
    var
        SubjectLbl: Label 'Please review the hours logged on project %1 %2', Comment = '%1 = project no., %2 = project description';
        IntroLbl: Label 'We ask you to approve %1 hours on your project %2, shown per task in the To approve column below. Please open the review link, confirm the hours you approve for each task, and submit your answer.', Comment = '%1 = total hours to approve, %2 = project description or no.';
        HistoryNoteLbl: Label 'Logged: all hours logged on the task. Billed: invoiced or approved earlier. Not billable: written off earlier. Not billed: not invoiced yet. To approve: the hours we ask you to approve now.';
        TaskHdrLbl: Label 'Task';
        DescriptionHdrLbl: Label 'Description';
        LoggedHdrLbl: Label 'Logged';
        BilledHdrLbl: Label 'Billed';
        NotBillableHdrLbl: Label 'Not billable';
        NotBilledHdrLbl: Label 'Not billed';
        ToApproveHdrLbl: Label 'To approve';
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
    /// Builds the review e-mail message without sending it: one row per task with the task's history (logged, billed,
    /// not billable, not billed) and the hours to approve, a total row, and the review link.
    /// </summary>
    procedure BuildReviewEmail(Review: Record "BCJ Customer Review"; Recipient: Text; var EmailMessage: Codeunit "Email Message")
    var
        Job: Record Job;
        ReviewLine: Record "BCJ Customer Review Line";
        Link: Text;
        Body: TextBuilder;
        Totals: array[5] of Decimal;
        ProjectDescription: Text;
        Cell: Text;
        AskCell: Text;
    begin
        Link := GetReviewLink(Review);
        Job.SetLoadFields(Description);
        if Job.Get(Review."Project No.") then
            ProjectDescription := Job.Description;
        if ProjectDescription = '' then
            ProjectDescription := Review."Project No.";

        ReviewLine.SetRange("Review No.", Review."Review No.");
        ReviewLine.CalcSums("Task Logged Hours", "Task Billed Hours", "Task Not Billable Hours", "Task Not Billed Hours", "Hours to Bill");
        Totals[1] := ReviewLine."Task Logged Hours";
        Totals[2] := ReviewLine."Task Billed Hours";
        Totals[3] := ReviewLine."Task Not Billable Hours";
        Totals[4] := ReviewLine."Task Not Billed Hours";
        Totals[5] := ReviewLine."Hours to Bill";

        Cell := '<td align="right" style="border-top:1px solid #ddd">';
        // The hours asked for approval are highlighted so the customer sees at once what the question is.
        AskCell := '<td align="right" style="border-top:1px solid #ddd;background:#eef5fc;font-weight:bold">';
        Body.AppendLine('<html><body style="font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#222">');
        Body.AppendLine('<p>' + Html(StrSubstNo(IntroLbl, FormatHours(Totals[5]), ProjectDescription)) + '</p>');
        Body.AppendLine('<table cellpadding="6" cellspacing="0" style="border-collapse:collapse;border:1px solid #ccc">');
        Body.AppendLine('<tr style="background:#f2f2f2"><th align="left">' + Html(TaskHdrLbl) + '</th><th align="left">' + Html(DescriptionHdrLbl) +
            '</th><th align="right">' + Html(LoggedHdrLbl) + '</th><th align="right">' + Html(BilledHdrLbl) +
            '</th><th align="right">' + Html(NotBillableHdrLbl) + '</th><th align="right">' + Html(NotBilledHdrLbl) +
            '</th><th align="right" style="background:#eef5fc;color:#0b5cad">' + Html(ToApproveHdrLbl) + '</th></tr>');
        if ReviewLine.FindSet() then
            repeat
                Body.AppendLine('<tr><td style="border-top:1px solid #ddd">' + Html(ReviewLine."Project Task No.") +
                    '</td><td style="border-top:1px solid #ddd">' + Html(ReviewLine."Task Description") + '</td>' +
                    Cell + FormatHours(ReviewLine."Task Logged Hours") + '</td>' +
                    Cell + FormatHours(ReviewLine."Task Billed Hours") + '</td>' +
                    Cell + FormatHours(ReviewLine."Task Not Billable Hours") + '</td>' +
                    Cell + FormatHours(ReviewLine."Task Not Billed Hours") + '</td>' +
                    AskCell + FormatHours(ReviewLine."Hours to Bill") + '</td></tr>');
            until ReviewLine.Next() = 0;
        Body.AppendLine('<tr><td colspan="2" style="border-top:2px solid #999"><b>' + Html(TotalLbl) + '</b></td>' +
            TotalCell(Totals[1], false) + TotalCell(Totals[2], false) + TotalCell(Totals[3], false) + TotalCell(Totals[4], false) +
            TotalCell(Totals[5], true) + '</tr>');
        Body.AppendLine('</table>');
        Body.AppendLine('<p style="color:#666;font-size:12px">' + Html(HistoryNoteLbl) + '</p>');
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
        TempEmailAccount: Record "Email Account" temporary;
        EmailMessage: Codeunit "Email Message";
        Email: Codeunit Email;
        EmailScenario: Codeunit "Email Scenario";
        Recipient: Text[80];
    begin
        Recipient := GetRecipientEmail(Review);
        if Recipient = '' then
            exit(false);
        // No account for the scenario (and no default account): skip rather than error, the review still exists.
        if not EmailScenario.GetEmailAccount(Enum::"Email Scenario"::"BCJ Customer Time Review", TempEmailAccount) then
            exit(false);
        // Building can fail on a malformed recipient address; that must skip the mail, not roll back the reviews.
        if not TryBuildReviewEmail(Review, Recipient, EmailMessage) then
            exit(false);
        // Email.Send commits before dispatching, so it must not run inside a TryFunction. It returns false on failure.
        if not Email.Send(EmailMessage, Enum::"Email Scenario"::"BCJ Customer Time Review") then
            exit(false);
        Review."Sent To E-Mail" := Recipient;
        Review."E-Mail Sent On" := CurrentDateTime();
        Review.Modify(false);
        exit(true);
    end;

    [TryFunction]
    local procedure TryBuildReviewEmail(Review: Record "BCJ Customer Review"; Recipient: Text; var EmailMessage: Codeunit "Email Message")
    begin
        BuildReviewEmail(Review, Recipient, EmailMessage);
    end;

    local procedure TotalCell(Hours: Decimal; Highlight: Boolean): Text
    begin
        if Highlight then
            exit('<td align="right" style="border-top:2px solid #999;background:#eef5fc"><b>' + FormatHours(Hours) + '</b></td>');
        exit('<td align="right" style="border-top:2px solid #999"><b>' + FormatHours(Hours) + '</b></td>');
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
