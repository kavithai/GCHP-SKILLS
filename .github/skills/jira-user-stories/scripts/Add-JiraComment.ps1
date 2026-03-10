<#
.SYNOPSIS
Adds a comment to a Jira issue.

.DESCRIPTION
Posts a new comment to the specified Jira issue. Supports optional
visibility restrictions to limit comment visibility to specific roles
or groups.

.PARAMETER IssueKey
The Jira issue key to comment on (e.g. MYPROJ-123).

.PARAMETER Body
The comment text body. Must not be empty or whitespace.

.PARAMETER Visibility
Optional hashtable defining comment visibility restrictions.
Example: @{type='role'; value='Developers'}

.EXAMPLE
.\Add-JiraComment.ps1 -IssueKey 'MYPROJ-123' -Body 'This is a comment.'

.EXAMPLE
.\Add-JiraComment.ps1 -IssueKey 'MYPROJ-123' -Body 'Internal note' -Visibility @{type='role'; value='Developers'}
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$IssueKey,

    [Parameter(Mandatory = $true)]
    [string]$Body,

    [Parameter()]
    [hashtable]$Visibility
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'shared.psm1') -Force

if ($MyInvocation.InvocationName -ne '.') {
    try {
        # Validate issue key
        if (-not (Test-JiraIssueKey -IssueKey $IssueKey)) {
            throw "Invalid issue key '$IssueKey'. Expected format: PROJ-123."
        }

        # Validate body is not empty/whitespace
        if ([string]::IsNullOrWhiteSpace($Body)) {
            throw "Comment body must not be empty or whitespace."
        }

        # Load credentials
        $creds = Get-JiraCredentials

        # Build comment body hashtable
        $commentBody = @{
            body = $Body
        }

        if ($PSBoundParameters.ContainsKey('Visibility') -and $Visibility) {
            $commentBody['visibility'] = $Visibility
        }

        $jsonBody = $commentBody | ConvertTo-Json -Depth 10

        $escapedKey = [Uri]::EscapeDataString($IssueKey)
        $endpoint = "/rest/api/2/issue/$escapedKey/comment"

        Write-SkillOutput -Title 'AddComment' -Message "Adding comment to $IssueKey..."

        $response = Invoke-JiraApi -Credentials $creds -Endpoint $endpoint -Method 'Post' -Body $jsonBody

        $commentId = $response.id
        Write-AuditLog -Operation 'AddComment' -IssueKey $IssueKey -Details "Added comment ID: $commentId"
        Write-SkillOutput -Title 'AddComment' -Message "Successfully added comment to $IssueKey (comment ID: $commentId)."

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
