---
title: Jira User Stories Skill Reference
description: API endpoint reference for the Jira User Stories skill, covering allowed operations, blocked operations, authentication, response formats, pagination, error codes, and expand options
ms.date: 2026-03-06
ms.topic: reference
keywords:
  - jira
  - rest-api
  - user-stories
  - reference
estimated_reading_time: 8
---

<!-- markdownlint-disable MD024 -->

## Allowed Operations

| Script                  | HTTP Method | Endpoint                            | Description                              |
|-------------------------|-------------|-------------------------------------|------------------------------------------|
| Search-JiraIssues.ps1   | GET         | /rest/api/2/search                  | Search issues using JQL with pagination  |
| Get-JiraIssue.ps1       | GET         | /rest/api/2/issue/{key}             | Retrieve a single issue by key           |
| New-JiraIssue.ps1       | POST        | /rest/api/2/issue                   | Create a new issue                       |
| Update-JiraIssue.ps1    | PUT         | /rest/api/2/issue/{key}             | Update fields on an existing issue       |
| Add-JiraComment.ps1     | POST        | /rest/api/2/issue/{key}/comment     | Add a comment to an issue                |
| Set-JiraTransition.ps1  | GET / POST  | /rest/api/2/issue/{key}/transitions | List or execute a status transition      |
| Set-JiraAssignee.ps1    | PUT         | /rest/api/2/issue/{key}/assignee    | Assign or unassign an issue              |

## Blocked Operations

| Operation         | HTTP Method | Reason                                                                 |
|-------------------|-------------|------------------------------------------------------------------------|
| Delete issue      | DELETE      | Permanent, irreversible data loss                                      |
| Delete comment    | DELETE      | Permanent, irreversible data loss                                      |
| Delete project    | DELETE      | Destroys an entire project and all associated issues                   |
| Delete attachment | DELETE      | Permanent file removal with no recovery                                |

DELETE is blocked at three independent layers:

1. `[ValidateSet('Get', 'Post', 'Put')]` on the `-Method` parameter rejects DELETE at bind time.
2. A runtime guard inside `Invoke-JiraApi` checks the method and throws before any HTTP request.
3. No script in the skill constructs or invokes a DELETE request.

## Authentication Reference

### Bearer PAT (Data Center / Server)

The authorization header format:

```text
Authorization: Bearer <PAT>
```

Required `.env` keys: `jirapat`, `jiraurl`

### Basic Auth (Jira Cloud)

The authorization header format:

```text
Authorization: Basic <base64(email:api-token)>
```

Required `.env` keys: `jirapat`, `jiraurl`, `jiraemail`, `jiraauthtype=Basic`

The skill reads `jiraemail` and `jirapat`, concatenates them as `email:token`, Base64-encodes the result, and sends it as a `Basic` header. Jira Cloud API tokens are passed in the `jirapat` field.

### Credentials File Format

```text
jiraurl=https://jira.example.com
jirapat=your-personal-access-token
jiraemail=user@example.com
jiraauthtype=Basic
```

Lines starting with `#` are treated as comments. Empty lines are ignored. Keys are case-insensitive.

## API Response Format

### Issue Object

Common fields returned by `Get-JiraIssue.ps1` and `Search-JiraIssues.ps1`:

| Field Path                  | Type   | Description                        |
|-----------------------------|--------|------------------------------------|
| `key`                       | string | Issue key (e.g., `PROJ-123`)       |
| `id`                        | string | Numeric issue ID                   |
| `self`                      | string | REST API URL for this issue        |
| `fields.summary`            | string | Issue title                        |
| `fields.description`        | string | Issue description (wiki/ADF)       |
| `fields.status.name`        | string | Current status (e.g., `To Do`)     |
| `fields.status.id`          | string | Status ID                          |
| `fields.issuetype.name`     | string | Issue type (e.g., `Story`)         |
| `fields.priority.name`      | string | Priority (e.g., `High`)           |
| `fields.assignee.displayName` | string | Assignee display name            |
| `fields.assignee.name`      | string | Assignee username (Server)         |
| `fields.assignee.accountId` | string | Assignee account ID (Cloud)        |
| `fields.reporter.displayName` | string | Reporter display name            |
| `fields.labels`             | array  | Labels applied to the issue        |
| `fields.created`            | string | Creation timestamp (ISO 8601)      |
| `fields.updated`            | string | Last update timestamp (ISO 8601)   |
| `fields.resolution`         | object | Resolution details (null if open)  |
| `fields.comment.total`      | int    | Total comment count                |

### Search Response

The search endpoint returns a wrapper object:

| Field        | Type   | Description                                  |
|--------------|--------|----------------------------------------------|
| `startAt`    | int    | Index of the first result returned            |
| `maxResults` | int    | Maximum results per page                      |
| `total`      | int    | Total matching issues                         |
| `issues`     | array  | Array of issue objects                        |

### Create Response

`New-JiraIssue.ps1` returns the created issue reference:

| Field  | Type   | Description                         |
|--------|--------|-------------------------------------|
| `id`   | string | Numeric issue ID                    |
| `key`  | string | Issue key (e.g., `PROJ-456`)        |
| `self` | string | REST API URL for the created issue  |

### Transition Object

`Set-JiraTransition.ps1` with `-ListTransitions` returns:

| Field Path          | Type   | Description                        |
|---------------------|--------|------------------------------------|
| `transitions`       | array  | Available transitions              |
| `transitions[].id`  | string | Transition ID                      |
| `transitions[].name`| string | Transition name (e.g., `In Progress`) |
| `transitions[].to`  | object | Target status object               |

## Pagination

The search endpoint supports pagination through three query parameters:

| Parameter    | Type | Default | Description                                     |
|--------------|------|---------|-------------------------------------------------|
| `startAt`    | int  | 0       | Zero-based index of the first result to return   |
| `maxResults` | int  | 50      | Maximum results per page (Jira caps at 100)      |
| `total`      | int  | —       | Total matching issues (returned in the response) |

To paginate, increment `startAt` by `maxResults` on each request until `startAt >= total`. The `-All` switch on `Search-JiraIssues.ps1` automates this loop with a safety cap of 500 results.

## Error Codes

| HTTP Code | Name                  | Description                                                  | Resolution                                                    |
|-----------|-----------------------|--------------------------------------------------------------|---------------------------------------------------------------|
| 400       | Bad Request           | Malformed request body or invalid JQL                        | Check request JSON structure and JQL syntax                   |
| 401       | Unauthorized          | Invalid, expired, or missing authentication token            | Verify `jirapat` in `.env`; regenerate the PAT if expired     |
| 403       | Forbidden             | Valid credentials but insufficient project permissions       | Check Jira project role assignments for the service account   |
| 404       | Not Found             | Issue key, project, or endpoint does not exist               | Verify the issue key format and project existence             |
| 429       | Too Many Requests     | Rate limited by Jira server                                  | Handled automatically with backoff; reduce concurrent requests|
| 500       | Internal Server Error | Jira server error                                            | Retry with exponential backoff (handled automatically)        |

The `Invoke-JiraApi` function handles 429 and 5xx errors with automatic retry:

* On 429, reads the `Retry-After` header and waits the specified duration (defaults to 5 seconds).
* On 5xx, retries up to 3 times with exponential backoff (2, 4, 8 seconds).
* All other error codes result in an immediate throw with a sanitized error message.

## Expand Options

The `expand` query parameter controls additional data included in issue responses. Pass these values via the `-Expand` parameter on `Get-JiraIssue.ps1`.

| Option            | Description                                                  |
|-------------------|--------------------------------------------------------------|
| `renderedFields`  | Returns HTML-rendered versions of text fields                |
| `changelog`       | Includes the issue change history                            |
| `names`           | Includes human-readable field names alongside field IDs      |
| `schema`          | Includes the JSON schema for each field                      |
| `transitions`     | Includes available status transitions                        |
| `operations`      | Includes permitted operations on the issue                   |
| `editmeta`        | Includes metadata about which fields can be edited           |
