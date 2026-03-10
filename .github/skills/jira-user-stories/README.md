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
