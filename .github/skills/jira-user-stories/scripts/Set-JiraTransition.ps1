<#
.SYNOPSIS
Transitions a Jira issue to a new status or lists available transitions.

.DESCRIPTION
Moves a Jira issue through its workflow by executing a transition. Can look
up transitions by name or ID. Use -ListTransitions to display available
transitions without executing one. Optionally adds a comment during the
transition.

.PARAMETER IssueKey
The Jira issue key to transition (e.g. MYPROJ-123).

.PARAMETER TransitionId
Optional transition ID to execute directly.

.PARAMETER TransitionName
Optional transition name to resolve to an ID automatically. If not found,
the error message lists all available transitions.

.PARAMETER ListTransitions
Switch to list available transitions for the issue without executing one.

.PARAMETER Comment
Optional comment text to add with the transition.

.EXAMPLE
.\Set-JiraTransition.ps1 -IssueKey 'MYPROJ-123' -ListTransitions

.EXAMPLE
.\Set-JiraTransition.ps1 -IssueKey 'MYPROJ-123' -TransitionName 'In Progress'

.EXAMPLE
.\Set-JiraTransition.ps1 -IssueKey 'MYPROJ-123' -TransitionId '31' -Comment 'Moving to done'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$IssueKey,

    [Parameter()]
    [string]$TransitionId,

    [Parameter()]
    [string]$TransitionName,

    [Parameter()]
    [switch]$ListTransitions,

    [Parameter()]
    [string]$Comment
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'shared.psm1') -Force

if ($MyInvocation.InvocationName -ne '.') {
    try {
        # Validate issue key
        if (-not (Test-JiraIssueKey -IssueKey $IssueKey)) {
            throw "Invalid issue key '$IssueKey'. Expected format: PROJ-123."
        }

        # Load credentials
        $creds = Get-JiraCredentials

        $escapedKey = [Uri]::EscapeDataString($IssueKey)
        $transitionsEndpoint = "/rest/api/2/issue/$escapedKey/transitions"

        # List mode: display available transitions
        if ($ListTransitions) {
            Write-SkillOutput -Title 'Transitions' -Message "Fetching available transitions for $IssueKey..."

            $response = Invoke-JiraApi -Credentials $creds -Endpoint $transitionsEndpoint -Method 'Get'
            $transitions = $response.transitions

            if (-not $transitions -or $transitions.Count -eq 0) {
                Write-SkillOutput -Title 'Transitions' -Message "No transitions available for $IssueKey."
            }
            else {
                Write-SkillOutput -Title 'Transitions' -Message "Available transitions for ${IssueKey}:"
                foreach ($t in $transitions) {
                    $toStatus = ''
                    if ($t.to -and $t.to.name) {
                        $toStatus = " -> $($t.to.name)"
                    }
                    Write-Host "  ID: $($t.id)  Name: $($t.name)$toStatus"
                }
            }

            Write-AuditLog -Operation 'ListTransitions' -IssueKey $IssueKey -Details "Listed $($transitions.Count) transitions"
            exit 0
        }

        # Execute mode: require either TransitionId or TransitionName
        if (-not $PSBoundParameters.ContainsKey('TransitionId') -and -not $PSBoundParameters.ContainsKey('TransitionName')) {
            throw "Either -TransitionId or -TransitionName must be specified (or use -ListTransitions to see available options)."
        }

        # Resolve TransitionName to TransitionId if needed
        $resolvedId = $TransitionId
        if ($PSBoundParameters.ContainsKey('TransitionName') -and $TransitionName) {
            Write-SkillOutput -Title 'Transitions' -Message "Looking up transition '$TransitionName' for $IssueKey..."

            $response = Invoke-JiraApi -Credentials $creds -Endpoint $transitionsEndpoint -Method 'Get'
            $transitions = $response.transitions

            $match = $transitions | Where-Object { $_.name -ieq $TransitionName }

            if (-not $match) {
                $availableNames = ($transitions | ForEach-Object { "'$($_.name)' (ID: $($_.id))" }) -join ', '
                throw "Transition '$TransitionName' not found for $IssueKey. Available transitions: $availableNames"
            }

            # Handle single or multiple matches (take first)
            if ($match -is [System.Array]) {
                $resolvedId = $match[0].id
            }
            else {
                $resolvedId = $match.id
            }

            Write-SkillOutput -Title 'Transitions' -Message "Resolved '$TransitionName' to transition ID: $resolvedId"
        }

        if (-not $resolvedId) {
            throw "Unable to determine transition ID. Provide -TransitionId or a valid -TransitionName."
        }

        # Build transition request body
        $transitionBody = @{
            transition = @{
                id = $resolvedId
            }
        }

        # Add optional comment with transition
        if ($PSBoundParameters.ContainsKey('Comment') -and $Comment) {
            $transitionBody['update'] = @{
                comment = @(
                    @{
                        add = @{
                            body = $Comment
                        }
                    }
                )
            }
        }

        $jsonBody = $transitionBody | ConvertTo-Json -Depth 10

        Write-SkillOutput -Title 'Transition' -Message "Transitioning $IssueKey (transition ID: $resolvedId)..."

        Invoke-JiraApi -Credentials $creds -Endpoint $transitionsEndpoint -Method 'Post' -Body $jsonBody

        Write-AuditLog -Operation 'Transition' -IssueKey $IssueKey -Details "Executed transition ID: $resolvedId"
        Write-SkillOutput -Title 'Transition' -Message "Successfully transitioned issue $IssueKey."

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
