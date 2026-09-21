codeunit 50106 "BCJ Install"
{
    Subtype = Install;

    trigger OnInstallAppPerCompany()
    var
        BillingMgt: Codeunit "BCJ Billing Mgt.";
        BCJUpgrade: Codeunit "BCJ Upgrade";
        UpgradeTag: Codeunit "Upgrade Tag";
    begin
        // Also runs when the app is reinstalled over existing data.
        BillingMgt.SyncStatusFromLegacyFlags();
        if not UpgradeTag.HasUpgradeTag(BCJUpgrade.GetBillingStatusUpgradeTag()) then
            UpgradeTag.SetUpgradeTag(BCJUpgrade.GetBillingStatusUpgradeTag());
    end;
}
