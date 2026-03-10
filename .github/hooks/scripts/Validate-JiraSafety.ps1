try {
    # Read JSON from stdin (PowerShell 5.1 compatible)
    $inputJson = [Console]::In.ReadToEnd()
    $hookInput = $inputJson | ConvertFrom-Json

    $toolName  = $hookInput.tool_name
    $toolInput = $hookInput.tool_input

    # Protected files that must not be modified or deleted
    $protectedFiles = @(
        'shared.psm1',
        'Validate-JiraSafety.ps1',
        'jira-safety.json',
        'jira-safety.instructions.md'
    )

    function Write-HookResult {
        param(
            [string]$Decision,
            [string]$Reason = ''
        )
        @{
            hookSpecificOutput = @{
                hookEventName            = 'PreToolUse'
                permissionDecision       = $Decision
                permissionDecisionReason = $Reason
            }
        } | ConvertTo-Json -Depth 5 -Compress
    }

    function Test-ProtectedFile {
        param([string]$FilePath)
        foreach ($name in $protectedFiles) {
            if ($FilePath -like "*$name") {
                return $name
            }
        }
        return $null
    }

    switch ($toolName) {
        'run_in_terminal' {
            $command = $toolInput.command

            # Category 1 â€” DELETE method patterns
            if ($command -imatch '-Method\s+[''"]?Delete[''"]?') {
                Write-HookResult -Decision 'deny' -Reason 'DELETE HTTP method detected. DELETE operations are blocked by security policy.'
                exit 0
            }
            if ($command -imatch 'curl.*-X\s*DELETE') {
                Write-HookResult -Decision 'deny' -Reason 'curl DELETE request detected. DELETE operations are blocked by security policy.'
                exit 0
            }
            if ($command -imatch 'curl.*--request\s*DELETE') {
                Write-HookResult -Decision 'deny' -Reason 'curl DELETE request detected. DELETE operations are blocked by security policy.'
                exit 0
            }
            if ($command -imatch '-CustomMethod\s+[''"]?Delete[''"]?') {
                Write-HookResult -Decision 'deny' -Reason 'DELETE via CustomMethod detected. DELETE operations are blocked by security policy.'
                exit 0
            }

            # Category 5 â€” Protected file deletion/overwrite via terminal
            foreach ($name in $protectedFiles) {
                $escapedName = [regex]::Escape($name)
                if ($command -imatch "Remove-Item.*$escapedName") {
                    Write-HookResult -Decision 'deny' -Reason "Blocked attempt to delete protected file: $name"
                    exit 0
                }
                if ($command -imatch "del\s+.*$escapedName") {
                    Write-HookResult -Decision 'deny' -Reason "Blocked attempt to delete protected file: $name"
                    exit 0
                }
                if ($command -imatch "Set-Content.*$escapedName") {
                    Write-HookResult -Decision 'deny' -Reason "Blocked attempt to overwrite protected file: $name"
                    exit 0
                }
            }

            Write-HookResult -Decision 'allow'
            exit 0
        }

        'replace_string_in_file' {
            # Category 3 â€” Script tampering
            $matched = Test-ProtectedFile -FilePath $toolInput.filePath
            if ($matched) {
                Write-HookResult -Decision 'deny' -Reason "Blocked attempt to modify protected file: $matched"
                exit 0
            }
            Write-HookResult -Decision 'allow'
            exit 0
        }

        'multi_replace_string_in_file' {
            # Category 3 â€” Script tampering (check each replacement)
            if ($toolInput.replacements) {
                foreach ($replacement in $toolInput.replacements) {
                    $matched = Test-ProtectedFile -FilePath $replacement.filePath
                    if ($matched) {
                        Write-HookResult -Decision 'deny' -Reason "Blocked attempt to modify protected file: $matched"
                        exit 0
                    }
                }
            }
            Write-HookResult -Decision 'allow'
            exit 0
        }

        'create_file' {
            # Category 3 â€” Protected file overwrite via create
            $matched = Test-ProtectedFile -FilePath $toolInput.filePath
            if ($matched) {
                Write-HookResult -Decision 'deny' -Reason "Blocked attempt to overwrite protected file: $matched"
                exit 0
            }

            # Category 4 — Bypass script creation (narrow patterns targeting actual HTTP DELETE calls)
            $content = $toolInput.content
            if ($content) {
                if ($content -imatch 'Invoke-RestMethod.*-Method\s+[''"]?Delete') {
                    Write-HookResult -Decision 'deny' -Reason 'Blocked creation of file containing Invoke-RestMethod with Delete method (potential bypass script).'
                    exit 0
                }
                if ($content -imatch 'Invoke-WebRequest.*-Method\s+[''"]?Delete') {
                    Write-HookResult -Decision 'deny' -Reason 'Blocked creation of file containing Invoke-WebRequest with Delete method (potential bypass script).'
                    exit 0
                }
                if ($content -imatch 'curl.*-X\s*DELETE.*rest/api') {
                    Write-HookResult -Decision 'deny' -Reason 'Blocked creation of file containing curl DELETE against Jira API (potential bypass script).'
                    exit 0
                }
                if ($content -imatch 'curl.*--request\s*DELETE.*rest/api') {
                    Write-HookResult -Decision 'deny' -Reason 'Blocked creation of file containing curl DELETE against Jira API (potential bypass script).'
                    exit 0
                }
            }

            Write-HookResult -Decision 'allow'
            exit 0
        }

        default {
            Write-HookResult -Decision 'allow'
            exit 0
        }
    }
}
catch {
    Write-Error "Validate-JiraSafety hook error: $_"
    exit 2
}
