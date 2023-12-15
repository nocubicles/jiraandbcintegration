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

            JiraTask jiraTask = JiraTask.FromJson(content);
            StringBuilder message = new StringBuilder();
            message.Append(jiraTask.Issue.Fields.Project.Key);
            message.Append(';');
            message.Append(jiraTask.Issue.Fields.Project.Name);
            message.Append(";");
            message.Append(jiraTask.Issue.Key);
            message.Append(";");
            message.Append(jiraTask.Issue.Fields.Summary);
            message.Append(";");
            message.Append(jiraTask.Issue.Id);

            var response = req.CreateResponse(HttpStatusCode.OK);
            response.Headers.Add("Content-Type", "text/plain; charset=utf-8");

            response.WriteString("Welcome to Azure Functions!");            

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
