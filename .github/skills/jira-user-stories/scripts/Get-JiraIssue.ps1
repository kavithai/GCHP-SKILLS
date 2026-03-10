<#
.SYNOPSIS
    Retrieves a single Jira issue by its key.

.DESCRIPTION
    Fetches a Jira issue using the REST API v2. Supports selecting specific
    fields, expanding nested data (renderedFields, changelog, etc.), and
    optionally retrieving comments in a separate request. The issue key is
    URL-encoded before use.

    Use -Format Summary for a concise, human-readable markdown output
    that agents can return directly to users without extra parsing.

.PARAMETER IssueKey
    The Jira issue key to retrieve (e.g., PROJ-123). Must match the standard
    Jira key format: 1-10 uppercase alphanumeric/underscore characters
    starting with a letter, followed by a dash and 1-7 digits.

.PARAMETER Fields
    An optional array of field names to include in the response
    (e.g., summary, status, assignee). When omitted, all fields are returned.

.PARAMETER IncludeComments
    When set, performs a separate request to retrieve all comments for the issue
    and appends them to the output.

.PARAMETER Expand
    An optional array of expand options (e.g., renderedFields, changelog,
    transitions). These are passed as the expand query parameter.

.PARAMETER Format
    Output format: 'Json' (default) returns the full API response as JSON.
    'Summary' returns a concise, human-readable markdown summary with key
    fields, description, and comments.

.EXAMPLE
    .\Get-JiraIssue.ps1 -IssueKey 'PROJ-123'
    Retrieves all fields of issue PROJ-123 as JSON.

.EXAMPLE
    .\Get-JiraIssue.ps1 -IssueKey 'PROJ-123' -Format Summary
    Retrieves issue PROJ-123 and displays a clean readable summary.

.EXAMPLE
    .\Get-JiraIssue.ps1 -IssueKey 'PROJ-456' -Fields summary,status -IncludeComments
    Retrieves only summary and status fields, plus all comments.

.EXAMPLE
    .\Get-JiraIssue.ps1 -IssueKey 'PROJ-789' -Expand renderedFields,changelog
    Retrieves the issue with rendered fields and changelog expanded.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$IssueKey,

    [Parameter()]
    [string[]]$Fields,

    [Parameter()]
    [switch]$IncludeComments,

    [Parameter()]
    [string[]]$Expand,

    [Parameter()]
    [ValidateSet('Json', 'Summary')]
    [string]$Format = 'Json'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'shared.psm1') -Force

if ($MyInvocation.InvocationName -ne '.') {
    try {
        # Validate issue key
        if (-not (Test-JiraIssueKey -IssueKey $IssueKey)) {
            throw "Invalid Jira issue key format: '$IssueKey'. Expected format: PROJ-123."
        }

        # Load credentials
        $creds = Get-JiraCredentials

        # URL-encode the issue key
        $encodedKey = [Uri]::EscapeDataString($IssueKey)

        # Build the endpoint with optional query parameters
        $endpoint = "/rest/api/2/issue/$encodedKey"
        $queryParts = @()

        if ($Fields -and $Fields.Count -gt 0) {
            $queryParts += "fields=$($Fields -join ',')"
        }

        if ($Expand -and $Expand.Count -gt 0) {
            $queryParts += "expand=$($Expand -join ',')"
        }

        if ($queryParts.Count -gt 0) {
            $endpoint += '?' + ($queryParts -join '&')
        }

        # Fetch the issue
        Write-SkillOutput -Title 'GetIssue' -Message "Retrieving issue $IssueKey..."
        $issue = Invoke-JiraApi -Credentials $creds -Endpoint $endpoint -Method Get

        # Optionally fetch comments
        $comments = $null
        if ($IncludeComments -or $Format -eq 'Summary') {
            $commentEndpoint = "/rest/api/2/issue/$encodedKey/comment"
            Write-SkillOutput -Title 'GetIssue' -Message "Retrieving comments for $IssueKey..."
            $comments = Invoke-JiraApi -Credentials $creds -Endpoint $commentEndpoint -Method Get
            Write-SkillOutput -Title 'Comments' -Message "Found $($comments.total) comment(s)."
        }

        # Output based on format
        if ($Format -eq 'Summary') {
            Format-JiraIssueSummary -Issue $issue -Comments $comments
        }
        else {
            # Merge comments into issue object for single JSON output
            if ($comments) {
                $issue | Add-Member -NotePropertyName '_comments' -NotePropertyValue $comments -Force
            }
            $issue | ConvertTo-Json -Depth 10
        }

        Write-AuditLog -Operation 'GetIssue' -IssueKey $IssueKey -Details "Retrieved issue. IncludeComments=$IncludeComments"
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
