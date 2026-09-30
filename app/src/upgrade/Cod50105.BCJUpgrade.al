codeunit 50105 "BCJ Upgrade"
{
    Subtype = Upgrade;

    trigger OnUpgradePerCompany()
    begin
        UpgradeHourAllocation();
        // The billing status and billable hours upgrades of 1.1 are superseded by the hour allocation migration:
        // their tags only need to exist so they never run on data that is already in the new model.
        SetTagIfMissing(GetBillingStatusUpgradeTag());
        SetTagIfMissing(GetBillableHoursUpgradeTag());
    end;

    local procedure UpgradeHourAllocation()
    var
        HourAllocationMgt: Codeunit "BCJ Hour Allocation Mgt.";
        UpgradeTag: Codeunit "Upgrade Tag";
    begin
        if UpgradeTag.HasUpgradeTag(GetHourAllocationUpgradeTag()) then
            exit;
        HourAllocationMgt.MigrateLegacyEntries();
        UpgradeTag.SetUpgradeTag(GetHourAllocationUpgradeTag());
    end;

    local procedure SetTagIfMissing(Tag: Code[250])
    var
        UpgradeTag: Codeunit "Upgrade Tag";
    begin
        if not UpgradeTag.HasUpgradeTag(Tag) then
            UpgradeTag.SetUpgradeTag(Tag);
    end;

    procedure GetHourAllocationUpgradeTag(): Code[250]
    begin
        exit('BCJ-HOURALLOCATION-20261001');
    end;

    procedure GetBillableHoursUpgradeTag(): Code[250]
    begin
        exit('BCJ-BILLABLEHOURS-20260922');
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
        PerCompanyUpgradeTags.Add(GetHourAllocationUpgradeTag());
    end;
}
