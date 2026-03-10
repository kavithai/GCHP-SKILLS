---
title: Jira User Stories Skill Usage
description: Quick usage guide for the Jira user story management skill scripts, including setup, read and write operations, and troubleshooting. Supports PowerShell (Windows) and bash/curl (macOS/Linux).
author: GCHP-SKILLS
ms.date: 2026-03-10
ms.topic: how-to
keywords:
  - jira
  - powershell
  - bash
  - automation
  - user stories
  - macos
  - cross-platform
estimated_reading_time: 6
---

## Jira User Stories Skill

Use this skill to read, search, create, update, assign, comment on, and transition Jira issues through Jira REST API v2.

Two runtime options are available:

* **PowerShell** (`scripts/*.ps1`) — for Windows and PowerShell 7+ environments.
* **Bash** (`scripts/bash/*.sh`) — for macOS and Linux (uses `curl`, `python3`, and `base64`).

## Location

Skill root: `.github/skills/jira-user-stories`

PowerShell scripts: `.github/skills/jira-user-stories/scripts`

Bash scripts: `.github/skills/jira-user-stories/scripts/bash`

## Prerequisites

### Windows

* PowerShell 5.1 or later (Windows built-in)

### macOS / Linux

* bash 3.2+ (macOS built-in)
* curl (pre-installed)
* python3 (pre-installed on macOS via Xcode CLT)
* base64 (pre-installed)

### All Platforms

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

* Prefer `--format summary` (bash) or `-Format Summary` (PowerShell) for read operations.
* Check exit code after each script run (`$?` in bash, `$LASTEXITCODE` in PowerShell).
* `0` means success and `1` means failure.
* DELETE operations are blocked by design and not supported.
