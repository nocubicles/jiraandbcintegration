codeunit 50105 "BCJ Upgrade"
{
    Subtype = Upgrade;

    trigger OnUpgradePerCompany()
    begin
        UpgradeBillingStatus();
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
    end;
}
