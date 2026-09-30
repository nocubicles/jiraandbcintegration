codeunit 50103 "BCJ Billing Mgt."
{
    /// <summary>
    /// Applies one overview decision to every time entry within the filters of TimeEntry and returns the number of entries
    /// whose hours moved: Billable / Not Billable take the Open hours, Billed bills the Billable hours, Open undoes the
    /// consultant's own decisions (Billed goes back to Billable first). Hours in review and hours a customer approved are
    /// never taken. Sent for Review is refused: hours go into review only through a customer review.
    /// </summary>
    procedure SetBillingStatus(var TimeEntry: Record "BCJ Project Time Entry"; NewStatus: Enum "BCJ Billing Status"): Integer
    var
        EntryToChange: Record "BCJ Project Time Entry";
        EntryToModify: Record "BCJ Project Time Entry";
        HourAllocationMgt: Codeunit "BCJ Hour Allocation Mgt.";
        ChangedCount: Integer;
    begin
        HourAllocationMgt.CheckManualDecision(NewStatus);
        EntryToChange.Copy(TimeEntry);
        if EntryToChange.FindSet() then
            repeat
                EntryToModify := EntryToChange;
                if HourAllocationMgt.ApplyManualDecision(EntryToModify, NewStatus) then
                    ChangedCount += 1;
            until EntryToChange.Next() = 0;
        exit(ChangedCount);
    end;

    /// <summary>
    /// Returns the number of entries within the filters of TimeEntry that have hours in a customer review.
    /// </summary>
    procedure CountEntriesInReview(var TimeEntry: Record "BCJ Project Time Entry"): Integer
    var
        EntryInReview: Record "BCJ Project Time Entry";
    begin
        EntryInReview.Copy(TimeEntry);
        EntryInReview.FilterGroup(10);
        EntryInReview.SetFilter("In Review Hours", '<>0');
        EntryInReview.FilterGroup(0);
        exit(EntryInReview.Count());
    end;

    /// <summary>
    /// Maps the legacy flags to a billing status: Billed if IsBilled, else Billable if IsBillable, else Open.
    /// </summary>
    procedure GetStatusFromFlags(IsBillable: Boolean; IsBilled: Boolean): Enum "BCJ Billing Status"
    begin
        if IsBilled then
            exit("BCJ Billing Status"::Billed);
        if IsBillable then
            exit("BCJ Billing Status"::Billable);
        exit("BCJ Billing Status"::Open);
    end;

    /// <summary>
    /// No longer used: the Jira Time Entries page now changes hours through SetBillingStatus. Kept for compatibility.
    /// </summary>
    procedure SyncStatusFromLegacyFlags()
    begin
    end;
}
