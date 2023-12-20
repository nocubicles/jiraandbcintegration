tableextension 50101 "BCJ Job Setup" extends "Jobs Setup"
{
    fields
    {
        field(50100; "BCJ Job Journal Templ."; Code[20])
        {
            Caption = 'Jira Integration Default Job Journal Template';
            TableRelation = "Job Journal Template".Name;
        }
        field(50101; "BCJ Job Journal Batch"; Code[20])
        {
            Caption = 'Jira Integration Default Job Journal Batch';
            TableRelation = "Job Journal Batch"."Name" where("Journal Template Name" = field("BCJ Job Journal Templ."));
        }
    }
}