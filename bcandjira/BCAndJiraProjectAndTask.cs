using System;
using System.Net;
using Azure.Storage.Queues.Models;
using Google.Protobuf;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using System.Text.Json;
using System.Text;
using JiraIssue;

namespace bcandjira
{
    public class BCAndJiraProjectAndTask
    {
    
        [Function("SyncBCAndJiraProjectAndTask")]
        public static async Task<JobAndTaskResponse> Run([HttpTrigger(AuthorizationLevel.Anonymous, "get", "post")] HttpRequestData req,
        FunctionContext executionContext)
        {
            var logger = executionContext.GetLogger("HttpExample");
            logger.LogInformation("C# HTTP trigger function processed a request.");

            var content = await new StreamReader(req.Body).ReadToEndAsync();

            JiraTask jiraTask = JiraTask.GetJiraTaskFromJson(content);
            StringBuilder message = JiraTask.GetIssueMessage(jiraTask.Issue);

            var response = req.CreateResponse(HttpStatusCode.OK);
            response.Headers.Add("Content-Type", "text/plain; charset=utf-8");

            response.WriteString("Added to the queue");

            return new JobAndTaskResponse()
            {
                // Write a single message.
                Messages = new string[] { message.ToString() },
                HttpResponse = response
            };
        }

    }

    public class JobAndTaskResponse
    {
        [QueueOutput("syncprojectandtask", Connection = "AzureWebJobsStorage")]
        public string[] Messages { get; set; }
        public HttpResponseData HttpResponse { get; set; }
    }
}
