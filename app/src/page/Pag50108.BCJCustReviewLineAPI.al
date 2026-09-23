page 50108 "BCJ Cust. Review Line API"
{
    PageType = API;
    APIPublisher = 'integrated';
    APIGroup = 'jira';
    APIVersion = 'v1.0';
    EntityName = 'customerReviewLine';
    EntitySetName = 'customerReviewLines';
    EntityCaption = 'Customer Review Line';
    EntitySetCaption = 'Customer Review Lines';
    SourceTable = "BCJ Customer Review Line";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = true;
    Extensible = false;

    layout
    {
        area(Content)
        {
            repeater(Records)
            {
                field(systemId; Rec.SystemId)
                {
                    Editable = false;
                }
                field(reviewNo; Rec."Review No.")
                {
                    Editable = false;
                }
                field(taskNo; Rec."Project Task No.")
                {
                    Editable = false;
                }
                field(taskDescription; Rec."Task Description")
                {
                    Editable = false;
                }
                field(loggedHours; Rec."Logged Hours")
                {
                    Editable = false;
                }
                field(taskLoggedHours; Rec."Task Logged Hours")
                {
                    Editable = false;
                }
                field(taskBilledHours; Rec."Task Billed Hours")
                {
                    Editable = false;
                }
                field(taskNotBillableHours; Rec."Task Not Billable Hours")
                {
                    Editable = false;
                }
                field(taskNotBilledHours; Rec."Task Not Billed Hours")
                {
                    Editable = false;
                }
                field(hoursToBill; Rec."Hours to Bill")
                {
                    Editable = false;
                }
                field(approvedHours; Rec."Approved Hours")
                {
                }
                field(customerComment; Rec."Customer Comment")
                {
                }
                field(appliedHours; Rec."Applied Hours")
                {
                    Editable = false;
                }
            }
        }
    }
}
