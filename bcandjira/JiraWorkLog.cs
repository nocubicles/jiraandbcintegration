﻿// <auto-generated />
//
// To parse this JSON data, add NuGet 'System.Text.Json' then do:
//
//    using JiraWorkLog;
//
//    var workLog = WorkLog.FromJson(jsonString);
#nullable enable
#pragma warning disable CS8618
#pragma warning disable CS8601
#pragma warning disable CS8603
using JiraIssue;

namespace JiraWorkLog
{
    using System;
    using System.Collections.Generic;

    using System.Text.Json;
    using System.Text.Json.Serialization;
    using System.Globalization;
    using System.Text;
    using TimeLogComplexComment;

    public partial class WorkLog
    {
        [JsonPropertyName("timestamp")]
        public long Timestamp { get; set; }

        [JsonPropertyName("webhookEvent")]
        public string WebhookEvent { get; set; }

        [JsonPropertyName("worklog")]
        public Worklog Worklog { get; set; }
    }

    public partial class Worklog
    {
        [JsonPropertyName("self")]
        public Uri Self { get; set; }

        [JsonPropertyName("author")]
        public Author Author { get; set; }

        [JsonPropertyName("updateAuthor")]
        public Author UpdateAuthor { get; set; }

        [JsonPropertyName("created")]
        public string Created { get; set; }

        [JsonPropertyName("updated")]
        public string Updated { get; set; }

        [JsonPropertyName("started")]
        public string Started { get; set; }

        [JsonPropertyName("timeSpent")]
        public string TimeSpent { get; set; }

        [JsonPropertyName("timeSpentSeconds")]
        public long TimeSpentSeconds { get; set; }

        [JsonPropertyName("id")]
        [JsonConverter(typeof(ParseStringConverter))]
        public long Id { get; set; }

        [JsonPropertyName("issueId")]
        [JsonConverter(typeof(ParseStringConverter))]
        public long IssueId { get; set; }

        [JsonPropertyName("comment")]
        public object Comment { get; set; }
    }

    public partial class Author
    {
        [JsonPropertyName("self")]
        public Uri Self { get; set; }

        [JsonPropertyName("accountId")]
        public string AccountId { get; set; }

        [JsonPropertyName("avatarUrls")]
        public AvatarUrls AvatarUrls { get; set; }

        [JsonPropertyName("displayName")]
        public string DisplayName { get; set; }

        [JsonPropertyName("active")]
        public bool Active { get; set; }

        [JsonPropertyName("timeZone")]
        public string TimeZone { get; set; }

        [JsonPropertyName("accountType")]
        public string AccountType { get; set; }
    }

    public partial class AvatarUrls
    {
        [JsonPropertyName("48x48")]
        public Uri The48X48 { get; set; }

        [JsonPropertyName("24x24")]
        public Uri The24X24 { get; set; }

        [JsonPropertyName("16x16")]
        public Uri The16X16 { get; set; }

        [JsonPropertyName("32x32")]
        public Uri The32X32 { get; set; }
    }

    public partial class WorkLog
    {
        public static WorkLog FromJson(string json) => JsonSerializer.Deserialize<WorkLog>(json, JiraWorkLog.Converter.Settings);
        public static StringBuilder GetWorkLogMessage(Worklog workLog)
        {
            StringBuilder message = new StringBuilder();

            message.Append(workLog.Id);
            message.Append(";");
            message.Append(workLog.IssueId);
            message.Append(";");
            message.Append(workLog.Author.DisplayName);
            message.Append(";");
            message.Append(workLog.Started);
            message.Append(";");
            message.Append(workLog.TimeSpentSeconds);
            message.Append(";");

            //This below is here because Jira sends comment differently. On webhook its a string but in API request its a object.
            if (workLog.Comment != null)
            {
                JsonElement element = (JsonElement)workLog.Comment;
                switch (element.ValueKind)
                {
                    case JsonValueKind.String:
                        message.Append(workLog.Comment);
                        break;
                    case JsonValueKind.Object:
                        ComplexComment complexComment = ComplexComment.FromJson(workLog.Comment.ToString());
                        message.Append(complexComment.Content[0].Content[0].Text);
                        break;
                }
            } 
            else
            {
                message.Append("");
            }
 
            return message;
        }        
    }

    public static class Serialize
    {
        public static string ToJson(this WorkLog self) => JsonSerializer.Serialize(self, JiraWorkLog.Converter.Settings);
    }

    internal static class Converter
    {
        public static readonly JsonSerializerOptions Settings = new(JsonSerializerDefaults.General)
        {
            Converters =
            {
                new DateOnlyConverter(),
                new TimeOnlyConverter(),
                IsoDateTimeOffsetConverter.Singleton
            },
        };
    }

    internal class ParseStringConverter : JsonConverter<long>
    {
        public override bool CanConvert(Type t) => t == typeof(long);

        public override long Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            var value = reader.GetString();
            long l;
            if (Int64.TryParse(value, out l))
            {
                return l;
            }
            throw new Exception("Cannot unmarshal type long");
        }

        public override void Write(Utf8JsonWriter writer, long value, JsonSerializerOptions options)
        {
            JsonSerializer.Serialize(writer, value.ToString(), options);
            return;
        }

        public static readonly ParseStringConverter Singleton = new ParseStringConverter();
    }

    public class DateOnlyConverter : JsonConverter<DateOnly>
    {
        private readonly string serializationFormat;
        public DateOnlyConverter() : this(null) { }

        public DateOnlyConverter(string? serializationFormat)
        {
            this.serializationFormat = serializationFormat ?? "yyyy-MM-dd";
        }

        public override DateOnly Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            var value = reader.GetString();
            return DateOnly.Parse(value!);
        }

        public override void Write(Utf8JsonWriter writer, DateOnly value, JsonSerializerOptions options)
            => writer.WriteStringValue(value.ToString(serializationFormat));
    }

    public class TimeOnlyConverter : JsonConverter<TimeOnly>
    {
        private readonly string serializationFormat;

        public TimeOnlyConverter() : this(null) { }

        public TimeOnlyConverter(string? serializationFormat)
        {
            this.serializationFormat = serializationFormat ?? "HH:mm:ss.fff";
        }

        public override TimeOnly Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            var value = reader.GetString();
            return TimeOnly.Parse(value!);
        }

        public override void Write(Utf8JsonWriter writer, TimeOnly value, JsonSerializerOptions options)
            => writer.WriteStringValue(value.ToString(serializationFormat));
    }

    internal class IsoDateTimeOffsetConverter : JsonConverter<DateTimeOffset>
    {
        public override bool CanConvert(Type t) => t == typeof(DateTimeOffset);

        private const string DefaultDateTimeFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss.FFFFFFFK";

        private DateTimeStyles _dateTimeStyles = DateTimeStyles.RoundtripKind;
        private string? _dateTimeFormat;
        private CultureInfo? _culture;

        public DateTimeStyles DateTimeStyles
        {
            get => _dateTimeStyles;
            set => _dateTimeStyles = value;
        }

        public string? DateTimeFormat
        {
            get => _dateTimeFormat ?? string.Empty;
            set => _dateTimeFormat = (string.IsNullOrEmpty(value)) ? null : value;
        }

        public CultureInfo Culture
        {
            get => _culture ?? CultureInfo.CurrentCulture;
            set => _culture = value;
        }

        public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options)
        {
            string text;


            if ((_dateTimeStyles & DateTimeStyles.AdjustToUniversal) == DateTimeStyles.AdjustToUniversal
                || (_dateTimeStyles & DateTimeStyles.AssumeUniversal) == DateTimeStyles.AssumeUniversal)
            {
                value = value.ToUniversalTime();
            }

            text = value.ToString(_dateTimeFormat ?? DefaultDateTimeFormat, Culture);

            writer.WriteStringValue(text);
        }

        public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            string? dateText = reader.GetString();

            if (string.IsNullOrEmpty(dateText) == false)
            {
                if (!string.IsNullOrEmpty(_dateTimeFormat))
                {
                    return DateTimeOffset.ParseExact(dateText, _dateTimeFormat, Culture, _dateTimeStyles);
                }
                else
                {
                    return DateTimeOffset.Parse(dateText, Culture, _dateTimeStyles);
                }
            }
            else
            {
                return default(DateTimeOffset);
            }
        }


        public static readonly IsoDateTimeOffsetConverter Singleton = new IsoDateTimeOffsetConverter();
    }
}
#pragma warning restore CS8618
#pragma warning restore CS8601
#pragma warning restore CS8603
