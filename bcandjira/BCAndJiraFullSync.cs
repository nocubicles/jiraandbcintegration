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
using System.Threading;
using JiraWorkLog;

namespace bcandjira
{
    public class BCAndJiraFullSync
    {

        [Function("FullSyncBCAndJiraProjectAndTask")]
        public async Task<FullSyncJobAndTaskResponse> RunProjectAndTaskSync([QueueTrigger("dofullsync")] string DoSullSync, FunctionContext executionContext)
        {
            var logger = executionContext.GetLogger("HttpExample");
            logger.LogInformation("C# HTTP trigger function processed a request.");
            List<string> JobAndTaskMessages = new List<string>();
            List<string> WorklogMessages = new List<string>();

            // Queue Output messages
            await foreach (Issue issue in JiraTask.GetAllIssuesAsync(0))
            {
                JobAndTaskMessages.Add(JiraTask.GetIssueMessage(issue).ToString());

                await foreach (Worklog worklog in JiraTask.GetIssueWorkLog(0, issue.Id.ToString()))
                {
                    WorklogMessages.Add(WorkLog.GetWorkLogMessage(worklog).ToString());
                }
            }
            return new FullSyncJobAndTaskResponse
            {
                ProjectAndTaskMessages = JobAndTaskMessages.ToArray(),
                WorkLogMessages = WorklogMessages.ToArray(),
            };
        }
    }

    public class FullSyncJobAndTaskResponse
    {
        [QueueOutput("syncprojectandtask", Connection = "AzureWebJobsStorage")]
        public string[] ProjectAndTaskMessages { get; set; }
        [QueueOutput("syncprojecttimeentries", Connection = "AzureWebJobsStorage")]
        public string[] WorkLogMessages { get; set; }
    }
}
