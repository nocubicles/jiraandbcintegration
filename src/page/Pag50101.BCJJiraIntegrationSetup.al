page 50101 "BCJ Jira Integration Setup"
{
    PageType = Card;
    ApplicationArea = All;
    UsageCategory = Administration;
    SourceTable = "BCJ Jira Integration Setup";

    layout
    {
        area(Content)
        {
            field("Worklog changed last sync"; Rec."Worklog changed last sync")
            {
                ToolTip = 'Specifies the value of the Last Synced Timestamp for changed Work Log Entries field.', Comment = '%';
            }
            field("Worklog deleted last sync"; Rec."Worklog deleted last sync")
            {
                ToolTip = 'Specifies the value of the Last Synced Timestamp for deleted Work Log Entries field.', Comment = '%';
            }
            field("Jira Env Name"; Rec."Jira Env Name")
            {
                ToolTip = 'Specifies the value of the Name of the Jira Environment field.', Comment = '%';
            }
            field("Jira User E-mail"; Rec."Jira User E-mail")
            {
                ToolTip = 'Specifies the value of the Jira User E-Mail field.', Comment = '%';
                ExtendedDatatype = EMail;
            }
            field("Jira API-Key"; Rec."Jira API-Key")
            {
                ToolTip = 'Specifies the value of the Jira API Key field.', Comment = '%';
                ExtendedDatatype = Masked;
            }
            field("Sync Start Date"; Rec."Sync Start Date")
            {
            }
        }
    }
    actions
    {
        area(Processing)
        {
            action(TestConnection)
            {
                ApplicationArea = All;
                Caption = 'Test Connection';

                trigger OnAction()
                begin
                    Rec.TestConnection();
                end;
            }
            action(DoFullSync)
            {
                ApplicationArea = All;
                Caption = 'Do Full Sync For Jira Time Logs';

                trigger OnAction()
                begin
                    Rec.DoFullSync();
                end;
            }
            action(SyncChangedAndDeleted)
            {
                ApplicationArea = All;
                Caption = 'Sync New, Changed and Deleted Time Entries and Issues';

                trigger OnAction()
                begin
                    Rec.SyncChangedAndDeletedEntries();
                end;
            }
            action(UpdateExistingIssues)
            {
                ApplicationArea = All;
                Caption = 'Update Already synced Issues Statuses & other Issue data from Jira';

                trigger OnAction()
                begin
                    Rec.UpdateIssueData();
                end;
            }
        }
    }
    trigger OnOpenPage()
    begin
        Rec.Reset;
        if not Rec.Get then begin
            Rec.Init;
            Rec.Insert;
        end;
    end;
}
