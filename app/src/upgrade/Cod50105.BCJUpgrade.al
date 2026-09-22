codeunit 50105 "BCJ Upgrade"
{
    Subtype = Upgrade;

    trigger OnUpgradePerCompany()
    begin
        UpgradeBillingStatus();
        UpgradeBillableHours();
    end;

    local procedure UpgradeBillableHours()
    var
        TimeEntry: Record "BCJ Project Time Entry";
        UpgradeTag: Codeunit "Upgrade Tag";
    begin
        if UpgradeTag.HasUpgradeTag(GetBillableHoursUpgradeTag()) then
            exit;
        // Existing entries get their logged hours as billable hours. Modify(false): no trigger, no flag sync.
        TimeEntry.SetRange("Billable Hours", 0);
        TimeEntry.SetFilter("Time Spent in Hours", '<>%1', 0);
        TimeEntry.SetLoadFields("Time Spent in Hours", "Billable Hours");
        if TimeEntry.FindSet(true) then
            repeat
                TimeEntry."Billable Hours" := TimeEntry."Time Spent in Hours";
                TimeEntry.Modify(false);
            until TimeEntry.Next() = 0;
        UpgradeTag.SetUpgradeTag(GetBillableHoursUpgradeTag());
    end;

    procedure GetBillableHoursUpgradeTag(): Code[250]
    begin
        exit('BCJ-BILLABLEHOURS-20260922');
    end;

    local procedure UpgradeBillingStatus()
    var
        UpgradeTag: Codeunit "Upgrade Tag";
        BillingMgt: Codeunit "BCJ Billing Mgt.";
    begin
        if UpgradeTag.HasUpgradeTag(GetBillingStatusUpgradeTag()) then
            exit;
        BillingMgt.SyncStatusFromLegacyFlags();
        UpgradeTag.SetUpgradeTag(GetBillingStatusUpgradeTag());
    end;

    procedure GetBillingStatusUpgradeTag(): Code[250]
    begin
        exit('BCJ-BILLINGSTATUS-20260921');
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Upgrade Tag", 'OnGetPerCompanyUpgradeTags', '', false, false)]
    local procedure RegisterPerCompanyTags(var PerCompanyUpgradeTags: List of [Code[250]])
    begin
        PerCompanyUpgradeTags.Add(GetBillingStatusUpgradeTag());
        PerCompanyUpgradeTags.Add(GetBillableHoursUpgradeTag());
    end;
}
