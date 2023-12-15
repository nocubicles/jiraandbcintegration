pageextension 50100 "BCJ Job List" extends "Job List"
{
    layout
    {
        // Add changes to page layout here
    }

    actions
    {
        addlast(processing)
        {
            action("BCJ SyncFromJira")
            {
                Caption = 'Sync Jobs from Jira';
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                PromotedOnly = true;
                ApplicationArea = All;
                trigger OnAction()
                var
                    ProcessJiraSync: codeunit "BCJ Process Jira Queue";
                begin
                    ProcessJiraSync.Run();
                end;
            }
        }
    }
}