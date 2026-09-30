codeunit 50106 "BCJ Install"
{
    Subtype = Install;

    trigger OnInstallAppPerCompany()
    var
        BCJUpgrade: Codeunit "BCJ Upgrade";
        HourAllocationMgt: Codeunit "BCJ Hour Allocation Mgt.";
        UpgradeTag: Codeunit "Upgrade Tag";
    begin
        // Also runs when the app is reinstalled over existing data.
        if not UpgradeTag.HasUpgradeTag(BCJUpgrade.GetHourAllocationUpgradeTag()) then begin
            HourAllocationMgt.MigrateLegacyEntries();
            UpgradeTag.SetUpgradeTag(BCJUpgrade.GetHourAllocationUpgradeTag());
        end;
        if not UpgradeTag.HasUpgradeTag(BCJUpgrade.GetBillingStatusUpgradeTag()) then
            UpgradeTag.SetUpgradeTag(BCJUpgrade.GetBillingStatusUpgradeTag());
        if not UpgradeTag.HasUpgradeTag(BCJUpgrade.GetBillableHoursUpgradeTag()) then
            UpgradeTag.SetUpgradeTag(BCJUpgrade.GetBillableHoursUpgradeTag());
    end;
}
