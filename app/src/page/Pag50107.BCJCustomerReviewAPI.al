page 50107 "BCJ Customer Review API"
{
    PageType = API;
    APIPublisher = 'integrated';
    APIGroup = 'jira';
    APIVersion = 'v1.0';
    EntityName = 'customerReview';
    EntitySetName = 'customerReviews';
    EntityCaption = 'Customer Review';
    EntitySetCaption = 'Customer Reviews';
    SourceTable = "BCJ Customer Review";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;
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
                field(accessToken; Rec."Access Token")
                {
                    Editable = false;
                }
                field(projectNo; Rec."Project No.")
                {
                    Editable = false;
                }
                field(projectDescription; ProjectDescription)
                {
                    Caption = 'Project Description';
                    Editable = false;
                }
                field(customerName; CustomerName)
                {
                    Caption = 'Customer Name';
                    Editable = false;
                }
                field(status; Rec.Status)
                {
                    Editable = false;
                }
                field(loggedHours; Rec."Logged Hours")
                {
                    Editable = false;
                }
                field(approvedHours; Rec."Approved Hours")
                {
                    Editable = false;
                }
                field(createdOn; Rec.SystemCreatedAt)
                {
                    Caption = 'Created On';
                    Editable = false;
                }
                field(answeredOn; Rec."Answered On")
                {
                    Editable = false;
                }
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        Job: Record Job;
        Customer: Record Customer;
    begin
        Rec.CalcFields("Logged Hours", "Approved Hours");
        ProjectDescription := '';
        CustomerName := '';
        Job.SetLoadFields(Description);
        if Job.Get(Rec."Project No.") then
            ProjectDescription := Job.Description;
        Customer.SetLoadFields(Name);
        if Customer.Get(Rec."Customer No.") then
            CustomerName := Customer.Name;
    end;

    /// <summary>
    /// Bound action: records the customer's answer and applies the approved hours.
    /// POST .../customerReviews({systemId})/Microsoft.NAV.submit
    /// </summary>
    [ServiceEnabled]
    procedure submit(var ActionContext: WebServiceActionContext)
    var
        Review: Record "BCJ Customer Review";
        CustomerReviewMgt: Codeunit "BCJ Customer Review Mgt.";
    begin
        Review.Get(Rec."Review No.");
        CustomerReviewMgt.SubmitReview(Review);
        ActionContext.SetObjectType(ObjectType::Page);
        ActionContext.SetObjectId(Page::"BCJ Customer Review API");
        ActionContext.AddEntityKey(Rec.FieldNo(SystemId), Rec.SystemId);
        ActionContext.SetResultCode(WebServiceActionResultCode::Updated);
    end;

    var
        ProjectDescription: Text[100];
        CustomerName: Text[100];
}
