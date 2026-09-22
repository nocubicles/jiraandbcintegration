codeunit 50103 "BCJ Billing Mgt."
{
    /// <summary>
    /// Sets the billing status on every time entry within the filters of TimeEntry.
    /// Keeps the legacy "Is Billable"/"Is Billed" flags in sync. Returns the number of entries changed.
    /// </summary>
    procedure SetBillingStatus(var TimeEntry: Record "BCJ Project Time Entry"; NewStatus: Enum "BCJ Billing Status"): Integer
    var
        EntryToChange: Record "BCJ Project Time Entry";
        EntryToModify: Record "BCJ Project Time Entry";
        ChangedCount: Integer;
    begin
        EntryToChange.Copy(TimeEntry);
        // Own filter group, so a caller's filter on Billing Status is kept (filter groups are combined with AND).
        // Entries waiting for a customer answer are never re-decided here; cancel the review first.
        EntryToChange.FilterGroup(10);
        EntryToChange.SetFilter("Billing Status", '<>%1&<>%2', NewStatus, EntryToChange."Billing Status"::"Sent for Review");
        EntryToChange.FilterGroup(0);
        if EntryToChange.FindSet() then
            repeat
                EntryToModify := EntryToChange;
                EntryToModify.Validate("Billing Status", NewStatus);
                EntryToModify.Modify(true);
                ChangedCount += 1;
            until EntryToChange.Next() = 0;
        exit(ChangedCount);
    end;

    /// <summary>
    /// Returns the number of entries within the filters of TimeEntry that are waiting for a customer answer.
    /// </summary>
    procedure CountEntriesInReview(var TimeEntry: Record "BCJ Project Time Entry"): Integer
    var
        EntryInReview: Record "BCJ Project Time Entry";
    begin
        EntryInReview.Copy(TimeEntry);
        EntryInReview.FilterGroup(10);
        EntryInReview.SetRange("Billing Status", EntryInReview."Billing Status"::"Sent for Review");
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
    /// Picks up entries marked on the old Jira Time Entries page, which only sets the legacy flags.
    /// "Is Billed" always wins (any status becomes Billed) so billed work never shows as unbilled again;
    /// "Is Billable" only promotes entries that are still Open.
    /// </summary>
    procedure SyncStatusFromLegacyFlags()
    var
        TimeEntry: Record "BCJ Project Time Entry";
    begin
        TimeEntry.SetFilter("Billing Status", '<>%1&<>%2', TimeEntry."Billing Status"::Billed, TimeEntry."Billing Status"::"Sent for Review");
        TimeEntry.SetRange("Is Billed", true);
        if not TimeEntry.IsEmpty() then
            TimeEntry.ModifyAll("Billing Status", TimeEntry."Billing Status"::Billed);

        TimeEntry.SetRange("Billing Status", TimeEntry."Billing Status"::Open);
        TimeEntry.SetRange("Is Billed", false);
        TimeEntry.SetRange("Is Billable", true);
        if not TimeEntry.IsEmpty() then
            TimeEntry.ModifyAll("Billing Status", TimeEntry."Billing Status"::Billable);
    end;
}
