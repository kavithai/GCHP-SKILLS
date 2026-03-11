---
title: Jira User Stories Skill Usage
description: Quick usage guide for the Jira user story management skill scripts, including setup, read and write operations, and troubleshooting.
author: GCHP-SKILLS
ms.date: 2026-03-10
ms.topic: how-to
keywords:
  - jira
  - powershell
  - automation
  - user stories
estimated_reading_time: 6
---

## Jira User Stories Skill

Use this skill to read, search, create, update, assign, comment on, and transition Jira issues through Jira REST API v2.

## Location

Skill root: `.github/skills/jira-user-stories`

Scripts: `.github/skills/jira-user-stories/scripts`

## Prerequisites

* PowerShell 5.1 or later (Windows built-in)
* Jira REST API v2 access over HTTPS
* Workspace root credentials file: `.env` or `credentials.env`

Required credential keys:

```env
jirapat=<token>
jiraurl=<https://your-jira-host>
```

Optional keys for Jira Cloud Basic auth:

```env
jiraemail=<your-email>
jiraauthtype=Basic
```

## Authentication Modes

* Data Center or Server: Bearer token (`jirapat`, `jiraurl`)
* Jira Cloud: Basic auth with API token (`jirapat`, `jiraurl`, `jiraemail`, `jiraauthtype=Basic`)

## Safe Defaults

* Prefer `-Format Summary` for read operations.
* Check `$LASTEXITCODE` after each script run.
* `0` means success and `1` means failure.
* DELETE operations are blocked by design and not supported.

## Limitations

| Area                    | Scope    | Limitation                                                                                         |
|-------------------------|----------|----------------------------------------------------------------------------------------------------|
| API version             | Skill    | Only Jira REST API v2 is supported; v3 (Jira Cloud next-gen) endpoints are not available           |
| HTTP methods            | Skill    | Only GET, POST, and PUT are allowed; DELETE is permanently blocked at three independent layers      |
| Pagination              | Skill    | Search results are capped at 500 issues even with `-All`; larger result sets require external tools |
| Attachments             | Skill    | No support for uploading, downloading, or managing file attachments                                |
| Sprints and boards      | Skill    | No direct sprint or board management; Agile-specific endpoints are not exposed                     |
| Bulk operations         | Skill    | No batch create, update, or transition; each issue must be handled individually                    |
| Webhooks                | Skill    | No webhook registration or event-driven workflows                                                  |
| Issue linking           | Skill    | No support for creating or managing issue links between Jira issues                                |
| Watchers                | Skill    | No support for adding, removing, or listing issue watchers                                         |
| Work logs               | Skill    | No support for logging or retrieving time-tracking entries                                          |
| Components and versions | Skill    | No support for managing project components or fix versions                                          |
| Rich text editing       | REST API | Descriptions and comments use plain text or wiki markup only; ADF (Atlassian Document Format) requires API v3 |
| Permissions discovery   | Skill    | No built-in check for user permissions before attempting operations                                |
| OAuth                   | Skill    | Only Bearer PAT and Basic Auth are supported; OAuth 2.0 flows are not implemented                  |
| Rate limiting           | REST API | Jira enforces per-user rate limits; the skill retries on 429 responses but cannot increase quotas  |
| Field validation        | REST API | Custom field IDs and allowed values are instance-specific; the skill does not pre-validate them    |
