---
description: "Safety rules for Jira operations â€” blocks DELETE and protects skill integrity"
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

* .github/skills/jira-user-stories/scripts/shared.psm1 â€” contains safety-critical ValidateSet and runtime DELETE guard
* .github/hooks/scripts/Validate-JiraSafety.ps1 â€” PreToolUse hook enforcement script
* .github/hooks/jira-safety.json â€” hook configuration
* .github/instructions/jira-safety.instructions.md â€” this file

## Enforcement

These rules are enforced by a PreToolUse hook at .github/hooks/jira-safety.json. On Windows, the hook runs a PowerShell validation script that blocks violations before tool execution. On non-Windows platforms, the hook uses a passthrough script that allows all operations (full non-Windows enforcement is not yet implemented). The hook operates as the fourth and fifth defense layers above the existing three-layer DELETE blocking in shared.psm1.
