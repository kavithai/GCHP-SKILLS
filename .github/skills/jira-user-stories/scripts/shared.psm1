# Shared utilities for Jira user stories skill scripts.
# Compatible with PowerShell 5.1+ (no #Requires -Version 7.0).

<#
.SYNOPSIS
Shared utilities for Jira user stories skill scripts.

.DESCRIPTION
Provides common functions used across all Jira user stories scripts:
credential loading, API invocation, input validation, output formatting,
and security controls (DELETE blocking, HTTPS enforcement, TLS 1.2 pinning).
#>

$script:LastRequestTime = [datetime]::MinValue
$script:MinRequestIntervalMs = 200

function Get-RepositoryRoot {
    <#
.SYNOPSIS
Gets the repository root path.
.DESCRIPTION
Runs git rev-parse --show-toplevel to locate the repository root.
In default mode, falls back to the current directory when git fails.
With -Strict, throws a terminating error instead.
.PARAMETER Strict
When set, throws instead of falling back to the current directory.
.OUTPUTS
System.String
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [switch]$Strict
    )

    if ($Strict) {
        $repoRoot = (& git rev-parse --show-toplevel 2>$null)
        if (-not $repoRoot) {
            throw "Unable to determine repository root."
        }
        return $repoRoot.Trim()
    }

    $root = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and $root) {
        return $root.Trim()
    }
    return $PWD.Path
}

function Write-SkillOutput {
    <#
.SYNOPSIS
Writes formatted output for skill script results.
.PARAMETER Title
Output section title.
.PARAMETER Message
Output message text.
#>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host "[$Title] $Message"
}

function Get-SanitizedErrorMessage {
    <#
.SYNOPSIS
Redacts sensitive data from error messages.
.DESCRIPTION
Replaces Bearer tokens, Basic auth headers, and long Base64-like
strings with [REDACTED] placeholders to prevent credential leakage.
.PARAMETER Message
The error message to sanitize.
.OUTPUTS
System.String
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    # Redact Bearer tokens
    $sanitized = $Message -replace 'Bearer \S+', 'Bearer [REDACTED]'

    # Redact Basic auth tokens
    $sanitized = $sanitized -replace 'Basic \S+', 'Basic [REDACTED]'

    # Redact Base64-like strings (20+ alphanumeric/+/=/_ chars)
    $sanitized = $sanitized -replace '[A-Za-z0-9+/=_]{20,}', '[REDACTED]'

    return $sanitized
}

function Get-JiraCredentials {
    <#
.SYNOPSIS
Loads Jira credentials from a .env or credentials.env file at the repo root.
.DESCRIPTION
Parses key=value lines from .env or credentials.env for jirapat, jiraurl,
jiraemail, and jiraauthtype. Defaults jiraauthtype to Bearer.
Throws if jirapat or jiraurl are missing.
.OUTPUTS
System.Collections.Hashtable
#>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $repoRoot = Get-RepositoryRoot

    $envFile = $null
    $candidateFiles = @(
        (Join-Path $repoRoot '.env'),
        (Join-Path $repoRoot 'credentials.env')
    )

    foreach ($candidate in $candidateFiles) {
        if (Test-Path $candidate) {
            $envFile = $candidate
            break
        }
    }

    if (-not $envFile) {
        throw "No .env or credentials.env file found at repository root '$repoRoot'."
    }

    $credentials = @{
        jirapat      = $null
        jiraurl      = $null
        jiraemail    = $null
        jiraauthtype = 'Bearer'
    }

    $lines = Get-Content -Path $envFile -ErrorAction Stop
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        # Skip empty lines and comments
        if (-not $trimmed -or $trimmed.StartsWith('#')) {
            continue
        }
        $eqIndex = $trimmed.IndexOf('=')
        if ($eqIndex -lt 1) {
            continue
        }
        $key = $trimmed.Substring(0, $eqIndex).Trim().ToLowerInvariant()
        $value = $trimmed.Substring($eqIndex + 1).Trim()

        if ($credentials.ContainsKey($key)) {
            $credentials[$key] = $value
        }
    }

    if (-not $credentials['jirapat']) {
        throw "Missing required 'jirapat' in '$envFile'."
    }
    if (-not $credentials['jiraurl']) {
        throw "Missing required 'jiraurl' in '$envFile'."
    }

    Write-SkillOutput -Title 'Credentials' -Message "Loaded Jira credentials from '$envFile'."
    return $credentials
}

function Get-JiraCurrentUser {
    <#
.SYNOPSIS
Retrieves the current authenticated Jira user's account information.
.DESCRIPTION
Calls the /rest/api/2/myself endpoint to resolve the current user's
account ID and display name. Useful for "assign to me" workflows where
the caller does not know their Jira account ID.
.PARAMETER Credentials
Hashtable containing Jira credentials from Get-JiraCredentials.
.OUTPUTS
System.Collections.Hashtable with keys: accountId, displayName, emailAddress
#>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Credentials
    )

    $response = Invoke-JiraApi -Credentials $Credentials -Endpoint '/rest/api/2/myself' -Method 'Get'

    return @{
        accountId    = $response.accountId
        displayName  = $response.displayName
        emailAddress = $response.emailAddress
    }
}

function New-JiraAuthHeaders {
    <#
.SYNOPSIS
Builds HTTP authorization headers for Jira API requests.
.DESCRIPTION
Creates Bearer headers for Data Center or Basic headers for Cloud,
based on the jiraauthtype credential value.
.PARAMETER Credentials
Hashtable containing jirapat, jiraurl, jiraemail, and jiraauthtype.
.OUTPUTS
System.Collections.Hashtable
#>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Credentials
    )

    $headers = @{
        'Content-Type' = 'application/json'
    }

    $authType = $Credentials['jiraauthtype']

    if ($authType -ieq 'Basic') {
        $email = $Credentials['jiraemail']
        $pat = $Credentials['jirapat']
        if (-not $email) {
            throw "Basic auth requires 'jiraemail' in credentials."
        }
        $pair = "${email}:${pat}"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($pair)
        $encoded = [System.Convert]::ToBase64String($bytes)
        $headers['Authorization'] = "Basic $encoded"
    }
    else {
        # Default to Bearer (Data Center)
        $headers['Authorization'] = "Bearer $($Credentials['jirapat'])"
    }

    return $headers
}

function Test-JiraIssueKey {
    <#
.SYNOPSIS
Validates that a string is a well-formed Jira issue key.
.DESCRIPTION
Returns true if the issue key matches the pattern: 1-10 uppercase
alphanumeric/underscore characters starting with a letter, followed
by a dash and 1-7 digits.
.PARAMETER IssueKey
The issue key string to validate.
.OUTPUTS
System.Boolean
#>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$IssueKey
    )

    return $IssueKey -cmatch '^[A-Z][A-Z0-9_]{0,9}-\d{1,7}$'
}

function ConvertTo-SafeJqlValue {
    <#
.SYNOPSIS
Escapes a string value for safe use in JQL queries.
.DESCRIPTION
Escapes backslashes and double quotes, strips carriage returns and
newlines, and wraps the result in double quotes.
.PARAMETER Value
The raw string value to escape.
.OUTPUTS
System.String
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    # Escape backslashes first, then double quotes
    $escaped = $Value -replace '\\', '\\\\'
    $escaped = $escaped -replace '"', '\"'

    # Strip carriage returns and newlines
    $escaped = $escaped -replace '\r', ''
    $escaped = $escaped -replace '\n', ''

    return "`"$escaped`""
}

function Test-JiraUrl {
    <#
.SYNOPSIS
Validates that a URL is safe for Jira API requests.
.DESCRIPTION
Returns false for non-HTTPS URLs and URLs pointing to localhost,
loopback addresses, or private IP ranges. Returns true otherwise.
.PARAMETER Url
The URL to validate.
.OUTPUTS
System.Boolean
#>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    # Must be HTTPS
    if (-not $Url.StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    try {
        $uri = [System.Uri]::new($Url)
    }
    catch {
        return $false
    }

    $uriHost = $uri.Host.ToLowerInvariant()

    # Block localhost and loopback
    if ($uriHost -eq 'localhost' -or $uriHost -eq '127.0.0.1' -or $uriHost -eq '::1') {
        return $false
    }

    # Block private IP ranges
    # 10.x.x.x
    if ($uriHost -match '^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
        return $false
    }

    # 172.16.0.0 - 172.31.255.255
    if ($uriHost -match '^172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}$') {
        return $false
    }

    # 192.168.x.x
    if ($uriHost -match '^192\.168\.\d{1,3}\.\d{1,3}$') {
        return $false
    }

    # 169.254.x.x (link-local)
    if ($uriHost -match '^169\.254\.\d{1,3}\.\d{1,3}$') {
        return $false
    }

    return $true
}

function Invoke-JiraApi {
    <#
.SYNOPSIS
Invokes a Jira REST API endpoint with retry and rate limiting.
.DESCRIPTION
Generic REST wrapper with three-layer DELETE blocking, HTTPS enforcement,
TLS 1.2 pinning, rate limiting (200ms minimum between requests), and
exponential backoff for 429/5xx responses.
.PARAMETER Credentials
Hashtable containing Jira credentials from Get-JiraCredentials.
.PARAMETER Endpoint
The API endpoint path (appended to jiraurl).
.PARAMETER Method
HTTP method. Only Get, Post, and Put are allowed.
.PARAMETER Body
Optional JSON body for Post/Put requests.
.OUTPUTS
System.Object
#>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Credentials,

        [Parameter(Mandatory = $true)]
        [string]$Endpoint,

        [Parameter()]
        [ValidateSet('Get', 'Post', 'Put')]
        [string]$Method = 'Get',

        [Parameter()]
        [string]$Body
    )

    # Layer 2: Runtime DELETE block (defense in depth)
    if ($Method -ieq 'Delete') {
        throw "BLOCKED: DELETE operations are not permitted by this skill."
    }

    # Build full URL
    $baseUrl = $Credentials['jiraurl'].TrimEnd('/')
    $fullUrl = "$baseUrl/$($Endpoint.TrimStart('/'))"

    # HTTPS enforcement
    if (-not $fullUrl.StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "HTTPS is required. Refusing to send credentials over non-HTTPS URL: $(Get-SanitizedErrorMessage -Message $fullUrl)"
    }

    # TLS 1.2 pinning
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Rate limiting
    $now = [datetime]::UtcNow
    $elapsed = ($now - $script:LastRequestTime).TotalMilliseconds
    if ($elapsed -lt $script:MinRequestIntervalMs) {
        $sleepMs = [int]($script:MinRequestIntervalMs - $elapsed)
        Start-Sleep -Milliseconds $sleepMs
    }

    # Build headers
    $headers = New-JiraAuthHeaders -Credentials $Credentials

    # Retry loop with exponential backoff
    $maxRetries = 3
    $attempt = 0

    while ($true) {
        $attempt++
        $script:LastRequestTime = [datetime]::UtcNow

        try {
            $params = @{
                Uri             = $fullUrl
                Method          = $Method
                Headers         = $headers
                ContentType     = 'application/json'
                UseBasicParsing = $true
                ErrorAction     = 'Stop'
            }

            if ($Body -and ($Method -ieq 'Post' -or $Method -ieq 'Put')) {
                $params['Body'] = $Body
            }

            $response = Invoke-RestMethod @params
            return $response
        }
        catch {
            $statusCode = 0
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Handle 429 Too Many Requests
            if ($statusCode -eq 429) {
                $retryAfter = $null
                try {
                    $retryAfter = $_.Exception.Response.Headers['Retry-After']
                }
                catch {
                    # Header may not be present
                }

                $waitSeconds = 5
                if ($retryAfter) {
                    $parsedSeconds = 0
                    if ([int]::TryParse($retryAfter, [ref]$parsedSeconds)) {
                        $waitSeconds = $parsedSeconds
                    }
                }

                Write-SkillOutput -Title 'RateLimit' -Message "429 received. Waiting $waitSeconds seconds before retry."
                Start-Sleep -Seconds $waitSeconds
                continue
            }

            # Handle 5xx with retry
            if ($statusCode -ge 500 -and $statusCode -lt 600 -and $attempt -lt $maxRetries) {
                $backoffSeconds = [math]::Pow(2, $attempt)
                $sanitizedError = Get-SanitizedErrorMessage -Message $_.Exception.Message
                Write-SkillOutput -Title 'Retry' -Message "Attempt $attempt/$maxRetries failed ($statusCode). Retrying in $backoffSeconds seconds. Error: $sanitizedError"
                Start-Sleep -Seconds $backoffSeconds
                continue
            }

            # All other errors or retries exhausted
            $sanitizedError = Get-SanitizedErrorMessage -Message $_.Exception.Message
            throw "Jira API request failed: $Method $Endpoint - $sanitizedError"
        }
    }
}

function Write-AuditLog {
    <#
.SYNOPSIS
Writes an audit log entry in JSON Lines format.
.DESCRIPTION
Appends a JSON-formatted log entry to the file specified by the
JIRA_AUDIT_LOG environment variable. Silently skips if the variable
is not set.
.PARAMETER Operation
The operation being performed (e.g., 'CreateIssue', 'UpdateIssue').
.PARAMETER IssueKey
The Jira issue key involved in the operation.
.PARAMETER Details
Additional details about the operation.
#>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [Parameter()]
        [string]$IssueKey,

        [Parameter()]
        [string]$Details
    )

    $logPath = $env:JIRA_AUDIT_LOG
    if (-not $logPath) {
        return
    }

    $entry = @{
        timestamp = (Get-Date -Format 'o')
        operation = $Operation
        issueKey  = $IssueKey
        details   = $Details
    }

    $jsonLine = $entry | ConvertTo-Json -Compress
    Add-Content -Path $logPath -Value $jsonLine -ErrorAction SilentlyContinue
}

function Format-JiraIssueSummary {
    <#
.SYNOPSIS
Formats a Jira issue object into a concise, human-readable summary.
.DESCRIPTION
Extracts key fields from a raw Jira API issue response and returns
a clean markdown-formatted string suitable for agent output.
Optionally includes comments when provided.
.PARAMETER Issue
The raw Jira issue object from the API response.
.PARAMETER Comments
Optional comments object from a separate /comment API call.
.OUTPUTS
System.String
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Issue,

        [Parameter()]
        [object]$Comments
    )

    $f = $Issue.fields
    $lines = @()

    # Header
    $typeName = if ($f.issuetype) { $f.issuetype.name } else { 'Issue' }
    $lines += ('## {0} - {1}' -f $Issue.key, $f.summary)
    $lines += ''

    # Key fields table
    $lines += '| Field | Value |'
    $lines += '|-------|-------|'
    $lines += ('| Type | {0} |' -f $typeName)
    if ($f.status) { $lines += ('| Status | {0} |' -f $f.status.name) }
    if ($f.priority) { $lines += ('| Priority | {0} |' -f $f.priority.name) }
    if ($f.reporter) { $lines += ('| Reporter | {0} |' -f $f.reporter.displayName) }
    if ($f.assignee) { $lines += ('| Assignee | {0} |' -f $f.assignee.displayName) }
    else { $lines += '| Assignee | Unassigned |' }
    if ($f.labels -and $f.labels.Count -gt 0) { $lines += ('| Labels | {0} |' -f ($f.labels -join ', ')) }
    if ($f.created) { $lines += ('| Created | {0} |' -f $f.created) }
    if ($f.updated) { $lines += ('| Updated | {0} |' -f $f.updated) }
    if ($f.resolution) { $lines += ('| Resolution | {0} |' -f $f.resolution.name) }

    # Description
    if ($f.description) {
        $lines += ''
        $lines += '### Description'
        $lines += ''
        $lines += $f.description
    }

    # Comments - from embedded or separate source
    $commentList = $null
    if ($Comments -and $Comments.comments) {
        $commentList = $Comments.comments
    }
    elseif ($f.comment -and $f.comment.comments) {
        $commentList = $f.comment.comments
    }

    if ($commentList -and $commentList.Count -gt 0) {
        $lines += ''
        $commentCount = $commentList.Count
        $lines += ('### Comments ({0})' -f $commentCount)
        $lines += ''
        $index = 0
        foreach ($c in $commentList) {
            $index++
            $author = if ($c.author) { $c.author.displayName } else { 'Unknown' }
            $date = if ($c.created) { $c.created.Substring(0, 10) } else { '' }
            $lines += ('{0}. **{1}** ({2}): {3}' -f $index, $author, $date, $c.body)
        }
    }

    return ($lines -join "`n")
}

function Format-JiraSearchSummary {
    <#
.SYNOPSIS
Formats Jira search results into a concise markdown table.
.PARAMETER SearchResult
The raw Jira search API response object.
.OUTPUTS
System.String
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$SearchResult
    )

    $lines = @()
    $total = if ($SearchResult.total) { $SearchResult.total } else { 0 }
    $count = 0
    if ($SearchResult.issues) { $count = $SearchResult.issues.Count }

    $lines += ('**Found {0} of {1} matching issues.**' -f $count, $total)
    $lines += ''

    if ($count -gt 0) {
        $lines += '| Key | Summary | Status | Priority | Assignee |'
        $lines += '|-----|---------|--------|----------|----------|'
        foreach ($issue in $SearchResult.issues) {
            $f = $issue.fields
            $status = if ($f.status) { $f.status.name } else { '-' }
            $priority = if ($f.priority) { $f.priority.name } else { '-' }
            $assignee = if ($f.assignee) { $f.assignee.displayName } else { 'Unassigned' }
            $summary = if ($f.summary) { $f.summary } else { '-' }
            # Truncate long summaries for table readability
            if ($summary.Length -gt 60) { $summary = $summary.Substring(0, 57) + '...' }
            $lines += ('| {0} | {1} | {2} | {3} | {4} |' -f $issue.key, $summary, $status, $priority, $assignee)
        }
    }

    return ($lines -join "`n")
}

Export-ModuleMember -Function @(
    'Get-RepositoryRoot',
    'Write-SkillOutput',
    'Get-SanitizedErrorMessage',
    'Get-JiraCredentials',
    'Get-JiraCurrentUser',
    'New-JiraAuthHeaders',
    'Test-JiraIssueKey',
    'ConvertTo-SafeJqlValue',
    'Test-JiraUrl',
    'Invoke-JiraApi',
    'Write-AuditLog',
    'Format-JiraIssueSummary',
    'Format-JiraSearchSummary'
)
