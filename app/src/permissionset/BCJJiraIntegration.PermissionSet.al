permissionset 50100 "BCJ JiraIntegration"
{
    Assignable = true;
    Permissions = tabledata "BCJ Jira Integration Setup"=RIMD,
        tabledata "BCJ Project Time Entry"=RIMD,
        tabledata "BCJ Customer Review"=RIMD,
        tabledata "BCJ Customer Review Line"=RIMD,
        table "BCJ Customer Review"=X,
        table "BCJ Customer Review Line"=X,
        codeunit "BCJ Customer Review Mgt."=X,
        codeunit "BCJ Review Mail"=X,
        page "BCJ Customer Reviews"=X,
        page "BCJ Customer Review"=X,
        page "BCJ Customer Review Subform"=X,
        page "BCJ Customer Review API"=X,
        page "BCJ Cust. Review Line API"=X,
        table "BCJ Jira Integration Setup"=X,
        table "BCJ Project Time Entry"=X,
        table "BCJ Billing Overview Buffer"=X,
        codeunit "BCJ Jira SDK"=X,
        codeunit "BCJ Post Jira Time To Job"=X,
        codeunit "BCJ Process Jira Queue"=X,
        codeunit "BCJ Billing Mgt."=X,
        codeunit "BCJ Billing Overview Mgt."=X,
        page "BCJ Jira Integration Setup"=X,
        page "BCJ Jira Time Entries"=X,
        page "BCJ Jira Billing Overview"=X,
        page "BCJ Jira Time Entry Worksheet"=X;
}
