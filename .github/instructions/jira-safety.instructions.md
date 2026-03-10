---
description: "Safety rules for Jira operations — blocks DELETE and protects skill integrity"
applyTo: "**"
---

# Jira Safety Policy

## Blocked Operations

* DELETE operations against Jira REST API are permanently blocked
* Do not attempt to delete issues, comments, projects, or attachments via any method

## Direct API Bypass Prevention

* Do not use Invoke-RestMethod, Invoke-WebRequest, or curl with -Method Delete or -X DELETE targeting Jira endpoints
* Always use the skill scripts in .github/skills/jira-user-stories/scripts/ for Jira operations
* Do not construct direct HTTP calls to Jira REST API endpoints that bypass the skill scripts

## Protected Files

Do not modify these files:

* .github/skills/jira-user-stories/scripts/shared.psm1 — contains safety-critical ValidateSet and runtime DELETE guard
* .github/hooks/scripts/Validate-JiraSafety.ps1 — Windows PreToolUse hook enforcement script
* .github/hooks/scripts/validate-jira-safety.sh — macOS/Linux PreToolUse hook enforcement script
* .github/hooks/jira-safety.json — hook configuration
* .github/instructions/jira-safety.instructions.md — this file

## Enforcement

These rules are enforced by a PreToolUse hook at .github/hooks/jira-safety.json. On Windows, the hook runs a PowerShell validation script (`Validate-JiraSafety.ps1`) that blocks violations before tool execution. On macOS/Linux, an equivalent Python-based bash script (`validate-jira-safety.sh`) provides the same enforcement. Together, the PreToolUse hook (fourth defense layer) and this workspace instructions file (fifth defense layer) sit above the existing three-layer DELETE blocking in `shared.psm1`.
