<#
.SYNOPSIS
    Searches for Jira issues using JQL.

.DESCRIPTION
    Executes a JQL query against the Jira REST API v2 search endpoint.
    Supports field selection, pagination with startAt/maxResults, and
    an -All switch that automatically paginates through all matching
    results (capped at 500 for safety).

    Use -Format Summary for a concise markdown table that agents can
    return directly to users without extra parsing.

.PARAMETER Jql
    The JQL query string to execute (e.g., "project = PROJ AND status = Open").

.PARAMETER Fields
    An optional array of field names to include in the results.
    Defaults to summary, status, assignee, and priority.

.PARAMETER MaxResults
    The maximum number of results to return per page. Defaults to 50.

.PARAMETER StartAt
    The zero-based index of the first result to return. Defaults to 0.

.PARAMETER All
    When set, automatically paginates through all matching results.
    Total results are capped at 500 for safety.

.PARAMETER Format
    Output format: 'Json' (default) returns the full API response as JSON.
    'Summary' returns a concise markdown table with key fields.

.EXAMPLE
    .\Search-JiraIssues.ps1 -Jql 'project = PROJ AND status = Open'
    Searches for open issues in project PROJ with default fields.

.EXAMPLE
    .\Search-JiraIssues.ps1 -Jql 'project = PROJ AND status = Open' -Format Summary
    Searches and returns a clean markdown table of results.

.EXAMPLE
    .\Search-JiraIssues.ps1 -Jql 'assignee = currentUser()' -Fields summary,status -MaxResults 10
    Searches for issues assigned to the current user, returning only summary
    and status, with a maximum of 10 results.

.EXAMPLE
    .\Search-JiraIssues.ps1 -Jql 'project = PROJ' -All
    Retrieves all matching issues (up to 500) by paginating automatically.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Jql,

    [Parameter()]
    [string[]]$Fields = @('summary', 'status', 'assignee', 'priority'),

    [Parameter()]
    [int]$MaxResults = 50,

    [Parameter()]
    [int]$StartAt = 0,

    [Parameter()]
    [switch]$All,

    [Parameter()]
    [ValidateSet('Json', 'Summary')]
    [string]$Format = 'Json'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'shared.psm1') -Force

if ($MyInvocation.InvocationName -ne '.') {
    try {
        # Load credentials
        $creds = Get-JiraCredentials

        # URL-encode the JQL query
        $encodedJql = [Uri]::EscapeDataString($Jql)

        # Build the fields parameter
        $fieldsParam = $Fields -join ','

        # Safety cap for -All pagination
        $safetyCap = 500

        if ($All) {
            Write-SkillOutput -Title 'Search' -Message "Searching with pagination (cap: $safetyCap results)..."

            $allIssues = @()
            $currentStart = $StartAt
            $pageSize = [math]::Min($MaxResults, 100)
            $totalAvailable = $null

            while ($true) {
                $endpoint = "/rest/api/2/search?jql=$encodedJql&startAt=$currentStart&maxResults=$pageSize&fields=$fieldsParam"

                $page = Invoke-JiraApi -Credentials $creds -Endpoint $endpoint -Method Get

                if ($null -eq $totalAvailable) {
                    $totalAvailable = $page.total
                    Write-SkillOutput -Title 'Search' -Message "Total matching issues: $totalAvailable"
                }

                if ($page.issues -and $page.issues.Count -gt 0) {
                    $allIssues += $page.issues
                }

                $currentStart += $pageSize

                # Stop if we have fetched all available results
                if ($currentStart -ge $totalAvailable) {
                    break
                }

                # Stop if we hit the safety cap
                if ($allIssues.Count -ge $safetyCap) {
                    Write-SkillOutput -Title 'Search' -Message "Safety cap of $safetyCap results reached. Stopping pagination."
                    break
                }
            }

            # Trim to safety cap if needed
            if ($allIssues.Count -gt $safetyCap) {
                $allIssues = $allIssues[0..($safetyCap - 1)]
            }

            # Build output object matching Jira search response structure
            $output = @{
                startAt    = $StartAt
                maxResults = $allIssues.Count
                total      = $totalAvailable
                issues     = $allIssues
            }

            Write-SkillOutput -Title 'Search' -Message "Returning $($allIssues.Count) of $totalAvailable total issues."
            if ($Format -eq 'Summary') {
                Format-JiraSearchSummary -SearchResult $output
            }
            else {
                $output | ConvertTo-Json -Depth 10
            }
        }
        else {
            # Single page request
            $endpoint = "/rest/api/2/search?jql=$encodedJql&startAt=$StartAt&maxResults=$MaxResults&fields=$fieldsParam"

            Write-SkillOutput -Title 'Search' -Message "Searching: $Jql (startAt=$StartAt, maxResults=$MaxResults)..."
            $result = Invoke-JiraApi -Credentials $creds -Endpoint $endpoint -Method Get

            $issueCount = 0
            if ($result.issues) {
                $issueCount = $result.issues.Count
            }

            Write-SkillOutput -Title 'Search' -Message "Returned $issueCount of $($result.total) total matching issues."
            if ($Format -eq 'Summary') {
                Format-JiraSearchSummary -SearchResult $result
            }
            else {
                $result | ConvertTo-Json -Depth 10
            }
        }

        Write-AuditLog -Operation 'SearchIssues' -Details "JQL: $Jql. All=$All"
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
