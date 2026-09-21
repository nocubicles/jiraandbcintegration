permissionset 50100 "BCJ JiraIntegration"
{
    Assignable = true;
    Permissions = tabledata "BCJ Jira Integration Setup"=RIMD,
        tabledata "BCJ Project Time Entry"=RIMD,
        table "BCJ Jira Integration Setup"=X,
        table "BCJ Project Time Entry"=X,
        codeunit "BCJ Jira SDK"=X,
        codeunit "BCJ Post Jira Time To Job"=X,
        codeunit "BCJ Process Jira Queue"=X,
        page "BCJ Jira Integration Setup"=X,
        page "BCJ Jira Time Entries"=X;
}
