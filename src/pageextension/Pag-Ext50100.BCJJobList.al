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
                Caption = 'Sync added Jobs, Tasks and Time Entries from Jira';
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
            action("BCJ FullSync")
            {
                Caption = 'Schedule Full Sync';
                ToolTip = 'Schedule a full sync for all projects, tasks and time entries from Jira. Please not that after scheduling the full sync you have to wait until job queue actually processes the full sync';
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                PromotedOnly = true;
                ApplicationArea = All;
                trigger OnAction()
                var
                    ProcessJiraSync: codeunit "BCJ Process Jira Queue";
                begin
                    ProcessJiraSync.DoFullSyncAllIssuesAndWorkEntries('dofullsync');
                end;
            }
        }
    }
}