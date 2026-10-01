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
                    ToolTip = 'Specifies which time entries to list and to change with the mark actions. Every customer, project and task within the date, customer and project filters is always shown with all its hours. Unbilled lists entries with open, in-review or billable hours.';

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
                    ToolTip = 'Specifies the hours that are not billed yet and not excluded from billing (Open + Sent for Review + Billable).';
                }
                field("Open Hours"; Rec."Open Hours")
                {
                    ToolTip = 'Specifies the unbilled hours that are free: not in a review, not approved and not written off. Hours you leave out of a review and hours the customer does not approve come back here.';
                }
                field("Sent for Review Hours"; Rec."Sent for Review Hours")
                {
                    Caption = 'In Review Hours';
                    ToolTip = 'Specifies the hours reserved in a draft customer review or sent to the customer and waiting for an answer. Choose the value to open the review.';

                    trigger OnDrillDown()
                    begin
                        OpenReviewsForLine();
                    end;
                }
                field("Billable Hours"; Rec."Billable Hours")
                {
                    ToolTip = 'Specifies the hours approved, by the customer in a review or by you, and waiting to be billed.';
                }
                field("Not Billable Hours"; Rec."Not Billable Hours")
                {
                    ToolTip = 'Specifies the hours written off.';
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
                    ToolTip = 'Approve the open (unbilled) hours under the selected lines without a customer review. Hours in review are not changed. Works on all hours under the selected lines within the date, customer and project filters, whatever Show is set to.';

                    trigger OnAction()
                    begin
                        SetStatusForSelection("BCJ Billing Status"::Billable);
                    end;
                }
                action(MarkNotBillable)
                {
                    Caption = 'Not Billable';
                    Image = Reject;
                    ToolTip = 'Write off the open (unbilled) hours under the selected lines. Hours in review and hours approved by the customer are not changed. Works on all hours under the selected lines within the date, customer and project filters, whatever Show is set to.';

                    trigger OnAction()
                    begin
                        SetStatusForSelection("BCJ Billing Status"::"Not Billable");
                    end;
                }
                action(MarkBilled)
                {
                    Caption = 'Billed';
                    Image = Invoice;
                    ToolTip = 'Mark the approved (billable) hours under the selected lines as billed after invoicing them. Open hours and hours in review are not billed. Works on all hours under the selected lines within the date, customer and project filters, whatever Show is set to.';

                    trigger OnAction()
                    begin
                        SetStatusForSelection("BCJ Billing Status"::Billed);
                    end;
                }
                action(MarkOpen)
                {
                    Caption = 'Open';
                    Image = ReOpen;
                    ToolTip = 'Undo your own decisions under the selected lines: billed hours go back to billable, otherwise hours you marked billable or not billable go back to open. Hours approved in a customer review are taken back only by reopening the review. Works on all hours under the selected lines within the date, customer and project filters, whatever Show is set to.';

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
                ToolTip = 'Reserve the open hours under the selected lines in a draft customer review per project and open it, so you can set the hours to bill before sending it. A project that already has a draft gets the hours added to it. Takes the open hours under the selected lines within the date, customer and project filters, whatever Show is set to.';

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
                ToolTip = 'Open the draft or sent customer review that holds hours under the current line. When there are several, the list of those reviews opens.';

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
    begin
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
        ChangeBilledQst: Label '%1 of the time entries under the selected lines have billed hours. Mark Open takes their billed hours back to %2. Continue?', Comment = '%1 = number of time entries with billed hours, %2 = Billable';
        ShowTimeEntries: Boolean;
        IsTimeEntryLine: Boolean;
        LineStyle: Text;
        StatusStyle: Text;
        EntriesUpdatedMsg: Label '%1 time entries updated.', Comment = '%1 = number of time entries';
        EntriesInReviewMsg: Label '%1 time entries have hours in a customer review; those hours were not changed.', Comment = '%1 = number of time entries';
        NoOpenReviewMsg: Label 'No draft or sent customer review holds hours under this line.';

    local procedure RefreshOverview()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        ViewEntry: Record "BCJ Project Time Entry";
        CurrentLine: Record "BCJ Billing Overview Buffer" temporary;
    begin
        // Entry numbers are reassigned on rebuild, so find the current line again by its keys.
        CurrentLine := Rec;
        // Every customer, project and task in the date, customer and project filters stays in the tree;
        // the Show view only decides which time entries are listed.
        SetBaseFilters(TimeEntry);
        SetViewFilter(ViewEntry);
        BillingOverviewMgt.BuildOverview(Rec, TimeEntry, ViewEntry, ShowTimeEntries);
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

    /// <summary>
    /// The time entries listed on the page: the date, customer and project filters plus the Show view.
    /// </summary>
    local procedure SetTimeEntryFilters(var TimeEntry: Record "BCJ Project Time Entry")
    begin
        SetBaseFilters(TimeEntry);
        SetViewFilter(TimeEntry);
    end;

    local procedure SetBaseFilters(var TimeEntry: Record "BCJ Project Time Entry")
    begin
        TimeEntry.Reset();
        if DateFilter <> '' then
            TimeEntry.SetFilter("Posting Date", DateFilter);
        if CustomerFilter <> '' then
            TimeEntry.SetFilter("Bill-to Customer No.", CustomerFilter);
        if ProjectFilter <> '' then
            TimeEntry.SetFilter("Project No.", ProjectFilter);
    end;

    local procedure SetViewFilter(var TimeEntry: Record "BCJ Project Time Entry")
    begin
        case StatusView of
            // A worklog can be split over several buckets, so a view shows every worklog holding hours in it.
            StatusView::Unbilled:
                TimeEntry.SetFilter("Unbilled Hours", '<>0');
            StatusView::Open:
                TimeEntry.SetFilter("Open Hours", '<>0');
            StatusView::"Sent for Review":
                TimeEntry.SetFilter("In Review Hours", '<>0');
            StatusView::Billable:
                TimeEntry.SetFilter("Billable Hours", '<>0');
            StatusView::"Not Billable":
                TimeEntry.SetFilter("Not Billable Hours", '<>0');
            StatusView::Billed:
                TimeEntry.SetFilter("Billed Hours", '<>0');
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
        // Only Mark Open touches billed hours (it takes them back to Billable).
        if NewStatus = "BCJ Billing Status"::Open then begin
            if SelectedLine.FindSet() then
                repeat
                    SetBaseFilters(TimeEntry);
                    BillingOverviewMgt.ApplyLineFilter(SelectedLine, TimeEntry);
                    TimeEntry.SetFilter("Billed Hours", '<>0');
                    BilledCount += TimeEntry.Count();
                until SelectedLine.Next() = 0;
            if BilledCount > 0 then
                if not Confirm(ChangeBilledQst, false, BilledCount, "BCJ Billing Status"::Billable) then
                    exit;
        end;
        if SelectedLine.FindSet() then
            repeat
                SetBaseFilters(TimeEntry);
                ChangedCount += BillingOverviewMgt.SetStatusForLine(SelectedLine, TimeEntry, NewStatus);
            until SelectedLine.Next() = 0;
        // Count the skipped entries. A single selected row needs one Count; several rows may overlap
        // (a customer row plus one of its tasks), so those are de-duplicated through marks.
        SetBaseFilters(TimeEntry);
        if SelectedLine.Count() = 1 then begin
            SelectedLine.FindFirst();
            BillingOverviewMgt.ApplyLineFilter(SelectedLine, TimeEntry);
            InReviewCount := BillingMgt.CountEntriesInReview(TimeEntry);
        end else begin
            BillingOverviewMgt.MarkEntriesForLines(SelectedLine, TimeEntry, MarkedEntry);
            MarkedEntry.SetFilter("In Review Hours", '<>0');
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
    begin
        SelectedLine.Copy(Rec, true);
        CurrPage.SetSelectionFilter(SelectedLine);
        SetBaseFilters(TimeEntryFilter);
        BillingOverviewMgt.MarkEntriesForLines(SelectedLine, TimeEntryFilter, MarkedEntry);
        CustomerReviewMgt.CreateReviews(MarkedEntry, TempReview);
        // Nothing is e-mailed here: the user sets the hours to bill on the review, then sends it from the card.
        // The reviews must be committed before the card opens modally.
        Commit();
        OpenReviews(TempReview);
        RefreshOverview();
    end;

    local procedure OpenReviewsForLine()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        TempReview: Record "BCJ Customer Review" temporary;
        CustomerReviewMgt: Codeunit "BCJ Customer Review Mgt.";
    begin
        // Whichever status view is shown, look at the worklogs with hours in review under the line.
        SetBaseFilters(TimeEntry);
        BillingOverviewMgt.ApplyLineFilter(Rec, TimeEntry);
        TimeEntry.SetFilter("In Review Hours", '<>0');
        if CustomerReviewMgt.GetOpenReviews(TimeEntry, TempReview) = 0 then begin
            Message(NoOpenReviewMsg);
            exit;
        end;
        OpenReviews(TempReview);
        RefreshOverview();
    end;

    /// Opens the card when there is one review, otherwise the list limited to these reviews.
    local procedure OpenReviews(var TempReview: Record "BCJ Customer Review" temporary)
    var
        Review: Record "BCJ Customer Review";
    begin
        if TempReview.Count() = 1 then begin
            TempReview.FindFirst();
            Review.SetRange("Review No.", TempReview."Review No.");
            Page.RunModal(Page::"BCJ Customer Review", Review);
            exit;
        end;
        if TempReview.FindSet() then
            repeat
                if Review.Get(TempReview."Review No.") then
                    Review.Mark(true);
            until TempReview.Next() = 0;
        Review.MarkedOnly(true);
        Page.RunModal(Page::"BCJ Customer Reviews", Review);
    end;
}
