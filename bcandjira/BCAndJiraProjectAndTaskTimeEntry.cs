using System;
using System.Net;
using Azure.Storage.Queues.Models;
using Google.Protobuf;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using System.Text.Json;
using System.Text;
using JiraWorkLog;
using JiraIssue;

namespace bcandjira
{
    public class BCAndJiraProjectAndTaskTimeEntry
    {

        [Function("SyncBCAndJiraProjectAndTaskTimeEntry")]
        public static async Task<TimeEntryResponse> Run([HttpTrigger(AuthorizationLevel.Anonymous, "get", "post")] HttpRequestData req,
        FunctionContext executionContext)
        {
            var logger = executionContext.GetLogger("HttpExample");
            logger.LogInformation("C# HTTP trigger function processed a request.");

            var content = await new StreamReader(req.Body).ReadToEndAsync();

            WorkLog workLog = WorkLog.FromJson(content);
            StringBuilder message = new StringBuilder();

            message.Append(workLog.Worklog.Id);
            message.Append(";");
            message.Append(workLog.Worklog.IssueId);
            message.Append(";");
            message.Append(workLog.Worklog.Author.DisplayName);
            message.Append(";");
            message.Append(workLog.Worklog.Started);
            message.Append(";");
            message.Append(workLog.Worklog.TimeSpentSeconds);
            message.Append(";");
            message.Append(workLog.Worklog.Comment);

            var response = req.CreateResponse(HttpStatusCode.OK);
            response.Headers.Add("Content-Type", "text/plain; charset=utf-8");

            response.WriteString("Added to the queue");

            return new TimeEntryResponse()
            {
                // Write a single message.
                Messages = new string[] { message.ToString() },
                HttpResponse = response
            };
        }
    }

    public class TimeEntryResponse
    {
        [QueueOutput("syncprojecttimeentries", Connection = "AzureWebJobsStorage")]
        public string[] Messages { get; set; }
        public HttpResponseData HttpResponse { get; set; }
    }
}
