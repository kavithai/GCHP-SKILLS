---
title: JQL Query Examples
description: Common and advanced JQL query patterns for use with Search-JiraIssues.ps1, including safety notes for user-supplied values
ms.date: 2026-03-06
ms.topic: reference
keywords:
  - jql
  - jira
  - search
  - query
estimated_reading_time: 5
---

## Common JQL Queries

| Purpose                        | JQL                                                          |
|--------------------------------|--------------------------------------------------------------|
| Assigned to current user       | `assignee = currentUser()`                                   |
| All issues in a project        | `project = MYPROJ`                                           |
| Stories in open sprints        | `issuetype = Story AND sprint in openSprints()`              |
| Issues in progress             | `status = "In Progress"`                                     |
| Updated in the last 7 days     | `updated >= -7d`                                             |
| Issues with a specific label   | `labels = "backend"`                                         |
| High priority issues           | `priority = High`                                            |
| Bugs created in last 30 days   | `created >= -30d AND issuetype = Bug`                        |
| Unresolved issues              | `resolution = Unresolved`                                    |
| Full-text search               | `text ~ "search term"`                                       |
| Issues in a specific epic      | `"Epic Link" = MYPROJ-100`                                  |
| Issues without an assignee     | `assignee = EMPTY`                                           |
| Issues due this week           | `due >= startOfWeek() AND due <= endOfWeek()`                |

## Advanced JQL Patterns

### OR Conditions

Combine multiple criteria where any condition can match:

```text
project = MYPROJ AND (status = "To Do" OR status = "In Progress")
```

```text
issuetype in (Story, Task, Bug)
```

### NOT Conditions

Exclude specific values:

```text
project = MYPROJ AND status != Done
```

```text
assignee != currentUser() AND resolution = Unresolved
```

### ORDER BY

Sort results by one or more fields:

```text
project = MYPROJ ORDER BY priority DESC, created ASC
```

```text
assignee = currentUser() AND resolution = Unresolved ORDER BY updated DESC
```

### JQL Functions

| Function           | Description                                         | Example                                          |
|--------------------|-----------------------------------------------------|--------------------------------------------------|
| `currentUser()`    | The authenticated user                              | `assignee = currentUser()`                       |
| `openSprints()`    | All currently active sprints                        | `sprint in openSprints()`                        |
| `closedSprints()`  | All completed sprints                               | `sprint in closedSprints()`                      |
| `futureSprints()`  | All upcoming sprints                                | `sprint in futureSprints()`                      |
| `startOfDay()`     | Midnight of the current day                         | `created >= startOfDay()`                        |
| `startOfWeek()`    | Start of the current week                           | `created >= startOfWeek()`                       |
| `startOfMonth()`   | Start of the current month                          | `created >= startOfMonth()`                      |
| `endOfDay()`       | End of the current day                              | `due <= endOfDay()`                              |
| `endOfWeek()`      | End of the current week                             | `due <= endOfWeek()`                             |
| `membersOf(group)` | All members of a Jira group                         | `assignee in membersOf("developers")`            |

### Relative Date Offsets

| Pattern  | Meaning          |
|----------|------------------|
| `-1d`    | 1 day ago        |
| `-7d`    | 7 days ago       |
| `-30d`   | 30 days ago      |
| `-1w`    | 1 week ago       |
| `-4w`    | 4 weeks ago      |
| `1d`     | 1 day from now   |

## JQL Safety Notes

### Always Use ConvertTo-SafeJqlValue

When constructing JQL queries that include user-supplied values, always use the `ConvertTo-SafeJqlValue` function from `shared.psm1`. This function escapes special characters, strips newlines, and wraps the value in double quotes to prevent JQL injection.

Correct approach:

```powershell
Import-Module (Join-Path $PSScriptRoot 'shared.psm1') -Force
$safeValue = ConvertTo-SafeJqlValue -Value $userInput
$jql = "project = MYPROJ AND summary ~ $safeValue"
```

Incorrect approach (vulnerable to injection):

```powershell
# Do NOT concatenate user input directly into JQL
$jql = "project = MYPROJ AND summary ~ `"$userInput`""
```

### Reserved Characters

JQL treats these characters as special operators. `ConvertTo-SafeJqlValue` handles them automatically:

* `"` (double quote) — escaped as `\"`
* `\` (backslash) — escaped as `\\`
* Newlines and carriage returns — stripped

### URL Encoding

All scripts URL-encode the JQL string using `[Uri]::EscapeDataString()` before sending it to the Jira API. You do not need to manually encode JQL values.

## Script Invocation Examples

Search with default fields:

    powershell -ExecutionPolicy Bypass -File scripts/Search-JiraIssues.ps1 -Jql "project = MYPROJ AND status = 'To Do'"

Search with specific fields and limited results:

    powershell -ExecutionPolicy Bypass -File scripts/Search-JiraIssues.ps1 -Jql "assignee = currentUser()" -Fields summary,status -MaxResults 10

Search for all matching issues with automatic pagination:

    powershell -ExecutionPolicy Bypass -File scripts/Search-JiraIssues.ps1 -Jql "project = MYPROJ AND resolution = Unresolved" -All

Search with ordering:

    powershell -ExecutionPolicy Bypass -File scripts/Search-JiraIssues.ps1 -Jql "project = MYPROJ ORDER BY priority DESC, updated DESC" -MaxResults 25

Search for recent bugs:

    powershell -ExecutionPolicy Bypass -File scripts/Search-JiraIssues.ps1 -Jql "created >= -7d AND issuetype = Bug AND project = MYPROJ"
