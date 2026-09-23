page 50102 "BCJ Jira Billing Overview"
{
    Caption = 'Jira Billing Overview';
    PageType = Worksheet;
    ApplicationArea = All;
    UsageCategory = Tasks;
    SourceTable = "BCJ Billing Overview Buffer";
    SourceTableTemporary = true;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;

    layout
    {
        area(Content)
        {
            group(Filters)
            {
                Caption = 'Filters';

                field(DateFilterCtrl; DateFilter)
                {
                    Caption = 'Date Filter';
                    ToolTip = 'Specifies the posting dates of the Jira time entries to include, for example 01.08.26..31.08.26 or a period like cm (current month).';

                    trigger OnValidate()
                    var
                        FilterTokens: Codeunit "Filter Tokens";
                    begin
                        FilterTokens.MakeDateFilter(DateFilter);
                        RefreshOverview();
                    end;
                }
                field(CustomerFilterCtrl; CustomerFilter)
                {
                    Caption = 'Customer Filter';
                    ToolTip = 'Specifies the bill-to customers of the projects to include.';

                    trigger OnLookup(var Text: Text): Boolean
                    var
                        CustomerList: Page "Customer List";
                    begin
                        CustomerList.LookupMode(true);
                        if CustomerList.RunModal() <> Action::LookupOK then
                            exit(false);
                        Text := CustomerList.GetSelectionFilter();
                        exit(true);
                    end;

                    trigger OnValidate()
                    begin
                        RefreshOverview();
                    end;
                }
                field(ProjectFilterCtrl; ProjectFilter)
                {
                    Caption = 'Project Filter';
                    ToolTip = 'Specifies the projects (Jira projects) to include.';

                    trigger OnLookup(var Text: Text): Boolean
                    var
                        Job: Record Job;
                        JobList: Page "Job List";
                    begin
                        JobList.LookupMode(true);
                        if JobList.RunModal() <> Action::LookupOK then
                            exit(false);
                        JobList.GetRecord(Job);
                        Text := Job."No.";
                        exit(true);
                    end;

                    trigger OnValidate()
                    begin
                        RefreshOverview();
                    end;
                }
                field(StatusViewCtrl; StatusView)
                {
                    Caption = 'Show';
                    OptionCaption = 'Unbilled,Open,Sent for Review,Billable,Not Billable,Billed,All';
                    ToolTip = 'Specifies which time entries to include. Unbilled shows entries that are Open, Sent for Review or Billable, i.e. everything that is not billed yet and not excluded from billing.';

                    trigger OnValidate()
                    begin
                        RefreshOverview();
                    end;
                }
                field(ShowTimeEntriesCtrl; ShowTimeEntries)
                {
                    Caption = 'Show Time Entries';
                    ToolTip = 'Specifies whether individual Jira time entries are shown under each task. Turn off for a faster overview over long periods.';

                    trigger OnValidate()
                    begin
                        RefreshOverview();
                    end;
                }
            }
            repeater(Lines)
            {
                IndentationColumn = Rec.Indentation;
                IndentationControls = Description;
                ShowAsTree = true;
                TreeInitialState = CollapseAll;

                field(Description; Rec.Description)
                {
                    StyleExpr = LineStyle;
                    ToolTip = 'Specifies the customer, project, task or time entry comment.';
                }
                field("Line Type"; Rec."Line Type")
                {
                    Visible = false;
                    ToolTip = 'Specifies whether the line is a customer, project, task or time entry.';
                }
                field("Customer No."; Rec."Customer No.")
                {
                    Visible = false;
                    ToolTip = 'Specifies the bill-to customer of the project.';
                }
                field("Project No."; Rec."Project No.")
                {
                    ToolTip = 'Specifies the project (Jira project key).';
                }
                field("Project Task No."; Rec."Project Task No.")
                {
                    ToolTip = 'Specifies the project task (Jira issue key).';
                }
                field("Jira Status"; Rec."Jira Status")
                {
                    ToolTip = 'Specifies the status of the issue in Jira.';
                }
                field("Resource No."; Rec."Resource No.")
                {
                    ToolTip = 'Specifies who logged the time.';
                }
                field("Posting Date"; Rec."Posting Date")
                {
                    ToolTip = 'Specifies the date the time was logged for.';
                }
                field("Billing Status"; Rec."Billing Status")
                {
                    HideValue = not IsTimeEntryLine;
                    StyleExpr = StatusStyle;
                    ToolTip = 'Specifies the billing status of the time entry.';
                }
                field("Total Hours"; Rec."Total Hours")
                {
                    StyleExpr = LineStyle;
                    ToolTip = 'Specifies the total hours logged.';
                }
                field("Unbilled Hours"; Rec."Unbilled Hours")
                {
                    Style = Attention;
                    ToolTip = 'Specifies the hours that are not billed yet and not excluded from billing (Open + Billable).';
                }
                field("Open Hours"; Rec."Open Hours")
                {
                    ToolTip = 'Specifies the hours not reviewed yet.';
                }
                field("Sent for Review Hours"; Rec."Sent for Review Hours")
                {
                    ToolTip = 'Specifies the hours sent to the customer and waiting for an answer. Choose the value to open the customer review.';

                    trigger OnDrillDown()
                    begin
                        OpenReviewsForLine();
                    end;
                }
                field("Billable Hours"; Rec."Billable Hours")
                {
                    ToolTip = 'Specifies the hours marked as billable and waiting to be billed. For entries the customer approved only partly, only the approved part counts here.';
                }
                field("Not Billable Hours"; Rec."Not Billable Hours")
                {
                    ToolTip = 'Specifies the hours marked as not billable, including the part of partly approved entries that the customer did not approve.';
                }
                field("Billed Hours"; Rec."Billed Hours")
                {
                    ToolTip = 'Specifies the hours already billed.';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(Refresh)
            {
                Caption = 'Refresh';
                Image = Refresh;
                ToolTip = 'Rebuild the overview from the current time entries.';

                trigger OnAction()
                begin
                    RefreshOverview();
                end;
            }
            group(MarkAs)
            {
                Caption = 'Mark Selected As';
                Image = Approve;

                action(MarkBillable)
                {
                    Caption = 'Billable';
                    Image = Approve;
                    ToolTip = 'Mark all time entries under the selected lines as billable. Only entries within the current filters are changed.';

                    trigger OnAction()
                    begin
                        SetStatusForSelection("BCJ Billing Status"::Billable);
                    end;
                }
                action(MarkNotBillable)
                {
                    Caption = 'Not Billable';
                    Image = Reject;
                    ToolTip = 'Mark all time entries under the selected lines as not billable. Only entries within the current filters are changed.';

                    trigger OnAction()
                    begin
                        SetStatusForSelection("BCJ Billing Status"::"Not Billable");
                    end;
                }
                action(MarkBilled)
                {
                    Caption = 'Billed';
                    Image = Invoice;
                    ToolTip = 'Mark all time entries under the selected lines as billed. Only entries within the current filters are changed.';

                    trigger OnAction()
                    begin
                        SetStatusForSelection("BCJ Billing Status"::Billed);
                    end;
                }
                action(MarkOpen)
                {
                    Caption = 'Open';
                    Image = ReOpen;
                    ToolTip = 'Reset all time entries under the selected lines to open (not reviewed). Only entries within the current filters are changed.';

                    trigger OnAction()
                    begin
                        SetStatusForSelection("BCJ Billing Status"::Open);
                    end;
                }
            }
            action(SendForReview)
            {
                Caption = 'Send for Customer Review';
                Image = SendApprovalRequest;
                ToolTip = 'Create a customer review per project from the open time entries under the selected lines and e-mail it to the bill-to contact of the project. The entries wait as Sent for Review until the customer answers. Only entries within the current filters are included.';

                trigger OnAction()
                begin
                    SendSelectionForReview();
                end;
            }
        }
        area(Navigation)
        {
            action(OpenCustomerReview)
            {
                Caption = 'Customer Review';
                Image = Document;
                ToolTip = 'Open the customer review that the time entries under the current line are waiting on, to see the tasks and hours sent to the customer. When there are several, the list of those reviews opens.';

                trigger OnAction()
                begin
                    OpenReviewsForLine();
                end;
            }
            action(CustomerReviews)
            {
                Caption = 'Customer Reviews';
                Image = Questionaire;
                ToolTip = 'Open the customer reviews, filtered to the current project when one is selected.';

                trigger OnAction()
                var
                    Review: Record "BCJ Customer Review";
                begin
                    if Rec."Project No." <> '' then
                        Review.SetRange("Project No.", Rec."Project No.");
                    Page.RunModal(Page::"BCJ Customer Reviews", Review);
                    RefreshOverview();
                end;
            }
            action(TimeEntries)
            {
                Caption = 'Time Entries';
                Image = Timesheet;
                ToolTip = 'Open the time entries under the current line, within the current filters.';

                trigger OnAction()
                var
                    TimeEntry: Record "BCJ Project Time Entry";
                begin
                    SetTimeEntryFilters(TimeEntry);
                    BillingOverviewMgt.ApplyLineFilter(Rec, TimeEntry);
                    Page.RunModal(Page::"BCJ Jira Time Entry Worksheet", TimeEntry);
                    RefreshOverview();
                end;
            }
            action(ProjectCard)
            {
                Caption = 'Project';
                Image = Job;
                ToolTip = 'Open the project card, for example to set the bill-to customer.';
                Enabled = Rec."Project No." <> '';

                trigger OnAction()
                var
                    Job: Record Job;
                begin
                    if not Job.Get(Rec."Project No.") then
                        exit;
                    Page.RunModal(Page::"Job Card", Job);
                    RefreshOverview();
                end;
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
                actionref(SendForReview_Promoted; SendForReview)
                {
                }
                actionref(Refresh_Promoted; Refresh)
                {
                }
            }
            group(Category_Navigate)
            {
                Caption = 'Navigate';

                actionref(TimeEntries_Promoted; TimeEntries)
                {
                }
                actionref(OpenCustomerReview_Promoted; OpenCustomerReview)
                {
                }
                actionref(CustomerReviews_Promoted; CustomerReviews)
                {
                }
                actionref(ProjectCard_Promoted; ProjectCard)
                {
                }
            }
        }
    }

    trigger OnOpenPage()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        BillingMgt: Codeunit "BCJ Billing Mgt.";
    begin
        // Picks up entries marked on the legacy Jira Time Entries page; skipped for read-only users.
        if TimeEntry.WritePermission() then
            BillingMgt.SyncStatusFromLegacyFlags();
        ShowTimeEntries := true;
        RefreshOverview();
    end;

    trigger OnAfterGetRecord()
    begin
        IsTimeEntryLine := Rec."Line Type" = Rec."Line Type"::"Time Entry";
        if IsTimeEntryLine then
            LineStyle := 'Standard'
        else
            LineStyle := 'Strong';
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
        BillingOverviewMgt: Codeunit "BCJ Billing Overview Mgt.";
        DateFilter: Text;
        CustomerFilter: Text;
        ProjectFilter: Text;
        StatusView: Option Unbilled,Open,"Sent for Review",Billable,"Not Billable",Billed,All;
        ChangeBilledQst: Label '%1 of the time entries under the selected lines are already billed. Change them to %2 as well?', Comment = '%1 = number of billed time entries, %2 = new billing status';
        ShowTimeEntries: Boolean;
        IsTimeEntryLine: Boolean;
        LineStyle: Text;
        StatusStyle: Text;
        EntriesUpdatedMsg: Label '%1 time entries updated.', Comment = '%1 = number of time entries';
        EntriesInReviewMsg: Label '%1 time entries were not changed because they are waiting for a customer answer.', Comment = '%1 = number of time entries';
        ReviewsCreatedMsg: Label '%1 customer reviews created, %2 e-mails sent.', Comment = '%1 = number of reviews, %2 = number of e-mails';
        NoOpenReviewMsg: Label 'There is no customer review waiting for an answer under this line.';

    local procedure RefreshOverview()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        CurrentLine: Record "BCJ Billing Overview Buffer" temporary;
    begin
        // Entry numbers are reassigned on rebuild, so find the current line again by its keys.
        CurrentLine := Rec;
        SetTimeEntryFilters(TimeEntry);
        BillingOverviewMgt.BuildOverview(Rec, TimeEntry, ShowTimeEntries);
        Rec.SetRange("Line Type", CurrentLine."Line Type");
        Rec.SetRange("Customer No.", CurrentLine."Customer No.");
        Rec.SetRange("Project No.", CurrentLine."Project No.");
        Rec.SetRange("Project Task No.", CurrentLine."Project Task No.");
        Rec.SetRange("Jira ID", CurrentLine."Jira ID");
        Rec.SetRange("Jira Issue Id", CurrentLine."Jira Issue Id");
        if not Rec.FindFirst() then begin
            Rec.Reset();
            if Rec.FindFirst() then;
        end;
        Rec.Reset();
        CurrPage.Update(false);
    end;

    local procedure SetTimeEntryFilters(var TimeEntry: Record "BCJ Project Time Entry")
    begin
        TimeEntry.Reset();
        if DateFilter <> '' then
            TimeEntry.SetFilter("Posting Date", DateFilter);
        if CustomerFilter <> '' then
            TimeEntry.SetFilter("Bill-to Customer No.", CustomerFilter);
        if ProjectFilter <> '' then
            TimeEntry.SetFilter("Project No.", ProjectFilter);
        case StatusView of
            StatusView::Unbilled:
                TimeEntry.SetFilter("Billing Status", '%1|%2|%3', TimeEntry."Billing Status"::Open, TimeEntry."Billing Status"::"Sent for Review", TimeEntry."Billing Status"::Billable);
            StatusView::Open:
                TimeEntry.SetRange("Billing Status", TimeEntry."Billing Status"::Open);
            StatusView::"Sent for Review":
                TimeEntry.SetRange("Billing Status", TimeEntry."Billing Status"::"Sent for Review");
            StatusView::Billable:
                TimeEntry.SetRange("Billing Status", TimeEntry."Billing Status"::Billable);
            StatusView::"Not Billable":
                TimeEntry.SetRange("Billing Status", TimeEntry."Billing Status"::"Not Billable");
            StatusView::Billed:
                TimeEntry.SetRange("Billing Status", TimeEntry."Billing Status"::Billed);
        end;
    end;

    local procedure SetStatusForSelection(NewStatus: Enum "BCJ Billing Status")
    var
        SelectedLine: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntry: Record "BCJ Project Time Entry";
        MarkedEntry: Record "BCJ Project Time Entry";
        BillingMgt: Codeunit "BCJ Billing Mgt.";
        ChangedCount: Integer;
        BilledCount: Integer;
        InReviewCount: Integer;
    begin
        SelectedLine.Copy(Rec, true);
        CurrPage.SetSelectionFilter(SelectedLine);
        if NewStatus <> "BCJ Billing Status"::Billed then begin
            if SelectedLine.FindSet() then
                repeat
                    SetTimeEntryFilters(TimeEntry);
                    BillingOverviewMgt.ApplyLineFilter(SelectedLine, TimeEntry);
                    TimeEntry.SetRange("Billing Status", TimeEntry."Billing Status"::Billed);
                    BilledCount += TimeEntry.Count();
                until SelectedLine.Next() = 0;
            if BilledCount > 0 then
                if not Confirm(ChangeBilledQst, false, BilledCount, NewStatus) then
                    exit;
        end;
        if SelectedLine.FindSet() then
            repeat
                SetTimeEntryFilters(TimeEntry);
                ChangedCount += BillingOverviewMgt.SetStatusForLine(SelectedLine, TimeEntry, NewStatus);
            until SelectedLine.Next() = 0;
        // Count the skipped entries. A single selected row needs one Count; several rows may overlap
        // (a customer row plus one of its tasks), so those are de-duplicated through marks.
        SetTimeEntryFilters(TimeEntry);
        if SelectedLine.Count() = 1 then begin
            SelectedLine.FindFirst();
            BillingOverviewMgt.ApplyLineFilter(SelectedLine, TimeEntry);
            InReviewCount := BillingMgt.CountEntriesInReview(TimeEntry);
        end else begin
            BillingOverviewMgt.MarkEntriesForLines(SelectedLine, TimeEntry, MarkedEntry);
            MarkedEntry.SetRange("Billing Status", MarkedEntry."Billing Status"::"Sent for Review");
            InReviewCount := MarkedEntry.Count();
        end;
        RefreshOverview();
        if InReviewCount > 0 then
            Message(EntriesUpdatedMsg + ' ' + EntriesInReviewMsg, ChangedCount, InReviewCount)
        else
            Message(EntriesUpdatedMsg, ChangedCount);
    end;

    local procedure SendSelectionForReview()
    var
        SelectedLine: Record "BCJ Billing Overview Buffer" temporary;
        TimeEntryFilter: Record "BCJ Project Time Entry";
        MarkedEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        CustomerReviewMgt: Codeunit "BCJ Customer Review Mgt.";
        ReviewCount: Integer;
        SentCount: Integer;
    begin
        SelectedLine.Copy(Rec, true);
        CurrPage.SetSelectionFilter(SelectedLine);
        SetTimeEntryFilters(TimeEntryFilter);
        BillingOverviewMgt.MarkEntriesForLines(SelectedLine, TimeEntryFilter, MarkedEntry);
        ReviewCount := CustomerReviewMgt.CreateReviews(MarkedEntry, TempReview);
        SentCount := CustomerReviewMgt.SendReviews(TempReview);
        RefreshOverview();
        Message(ReviewsCreatedMsg, ReviewCount, SentCount);
    end;

    local procedure OpenReviewsForLine()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        Review: Record "BCJ Customer Review";
        TempReview: Record "BCJ Customer Review" temporary;
        CustomerReviewMgt: Codeunit "BCJ Customer Review Mgt.";
    begin
        // Entries waiting for an answer are always Sent for Review, whichever status view is shown.
        SetTimeEntryFilters(TimeEntry);
        BillingOverviewMgt.ApplyLineFilter(Rec, TimeEntry);
        TimeEntry.SetRange("Billing Status", TimeEntry."Billing Status"::"Sent for Review");
        case CustomerReviewMgt.GetOpenReviews(TimeEntry, TempReview) of
            0:
                begin
                    Message(NoOpenReviewMsg);
                    exit;
                end;
            1:
                begin
                    TempReview.FindFirst();
                    Review.SetRange("Review No.", TempReview."Review No.");
                    Page.RunModal(Page::"BCJ Customer Review", Review);
                end;
            else begin
                TempReview.FindSet();
                repeat
                    if Review.Get(TempReview."Review No.") then
                        Review.Mark(true);
                until TempReview.Next() = 0;
                Review.MarkedOnly(true);
                Page.RunModal(Page::"BCJ Customer Reviews", Review);
            end;
        end;
        RefreshOverview();
    end;
}
