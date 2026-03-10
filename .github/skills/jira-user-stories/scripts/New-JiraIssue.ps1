<#
.SYNOPSIS
Creates a new Jira issue.

.DESCRIPTION
Creates a new issue in the specified Jira project with the given summary,
description, type, priority, labels, assignee, and custom fields. Builds
the request body as a hashtable and converts to JSON (never string
concatenation). Outputs the created issue key on success.

.PARAMETER ProjectKey
The Jira project key (e.g. MYPROJ). Must match ^[A-Z][A-Z0-9_]{0,9}$.

.PARAMETER Summary
The issue title/summary. Must not be empty or whitespace.

.PARAMETER Description
Optional description body for the issue.

.PARAMETER IssueType
The issue type name. Defaults to 'Story'. Common values: Story, Task, Bug, Epic.

.PARAMETER Priority
Optional priority name (e.g. High, Medium, Low).

.PARAMETER Labels
Optional array of label strings to apply to the issue.

.PARAMETER Assignee
Optional username or account ID to assign the issue to.

.PARAMETER CustomFields
Optional hashtable of custom field key-value pairs (e.g. @{customfield_10001='value'}).

.EXAMPLE
.\New-JiraIssue.ps1 -ProjectKey 'MYPROJ' -Summary 'Implement login page'

.EXAMPLE
.\New-JiraIssue.ps1 -ProjectKey 'MYPROJ' -Summary 'Fix bug' -IssueType 'Bug' -Priority 'High' -Labels @('frontend','urgent')
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectKey,

    [Parameter(Mandatory = $true)]
    [string]$Summary,

    [Parameter()]
    [string]$Description,

    [Parameter()]
    [string]$IssueType = 'Story',

    [Parameter()]
    [string]$Priority,

    [Parameter()]
    [string[]]$Labels,

    [Parameter()]
    [string]$Assignee,

    [Parameter()]
    [hashtable]$CustomFields
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'shared.psm1') -Force

if ($MyInvocation.InvocationName -ne '.') {
    try {
        # Validate Summary is not empty/whitespace
        if ([string]::IsNullOrWhiteSpace($Summary)) {
            throw "Summary must not be empty or whitespace."
        }

        # Validate ProjectKey format
        if ($ProjectKey -cnotmatch '^[A-Z][A-Z0-9_]{0,9}$') {
            throw "Invalid ProjectKey '$ProjectKey'. Must match pattern ^[A-Z][A-Z0-9_]{0,9}$."
        }

        # Load credentials
        $creds = Get-JiraCredentials

        # Build request body as hashtable
        $fields = @{
            project = @{
                key = $ProjectKey
            }
            summary   = $Summary
            issuetype = @{
                name = $IssueType
            }
        }

        if ($PSBoundParameters.ContainsKey('Description') -and $Description) {
            $fields['description'] = $Description
        }

        if ($PSBoundParameters.ContainsKey('Priority') -and $Priority) {
            $fields['priority'] = @{
                name = $Priority
            }
        }

        if ($PSBoundParameters.ContainsKey('Labels') -and $Labels) {
            $fields['labels'] = @($Labels)
        }

        if ($PSBoundParameters.ContainsKey('Assignee') -and $Assignee) {
            $fields['assignee'] = @{
                name = $Assignee
            }
        }

        if ($PSBoundParameters.ContainsKey('CustomFields') -and $CustomFields) {
            foreach ($cfKey in $CustomFields.Keys) {
                $fields[$cfKey] = $CustomFields[$cfKey]
            }
        }

        $body = @{
            fields = $fields
        }

        $jsonBody = $body | ConvertTo-Json -Depth 10

        Write-SkillOutput -Title 'CreateIssue' -Message "Creating $IssueType in project $ProjectKey..."

        $response = Invoke-JiraApi -Credentials $creds -Endpoint '/rest/api/2/issue' -Method 'Post' -Body $jsonBody

        $issueKey = $response.key

        Write-AuditLog -Operation 'CreateIssue' -IssueKey $issueKey -Details "Created $IssueType '$Summary' in $ProjectKey"
        Write-SkillOutput -Title 'CreateIssue' -Message "Successfully created issue: $issueKey"
        Write-Output $issueKey

        exit 0
    }
    catch {
        Write-Error (Get-SanitizedErrorMessage -Message $_.Exception.Message)
        exit 1
    }
    finally {
        if ($creds) { $creds['jirapat'] = $null; Remove-Variable -Name creds -ErrorAction SilentlyContinue }
    }
}
