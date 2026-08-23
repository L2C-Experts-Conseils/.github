<#
.SYNOPSIS
    Synchronizes organization labels, the Epic issue form, and Epic issues in Projects v2.
.DESCRIPTION
    Labels are always synchronized. Use -SyncEpicTemplate to copy the Epic issue form to
    every repository. Use -ProjectNumbers to add open issues with the epic label to Projects v2.
.EXAMPLE
    .\scripts\sync-labels.ps1 -SyncEpicTemplate -ProjectNumbers 1,2 -DryRun
.EXAMPLE
    .\scripts\sync-labels.ps1 -SyncEpicTemplate -ProjectNumbers 1
#>
[CmdletBinding()]
param(
    [switch]$SyncEpicTemplate,
    [ValidateRange(1, 2147483647)]
    [int[]]$ProjectNumbers = @(),
    [switch]$DryRun
)

$org = "L2C-Experts-Conseils"
$epicTemplateRelativePath = ".github/ISSUE_TEMPLATE/00-epic-template.yml"
$epicTemplatePath = Join-Path $PSScriptRoot "..\$epicTemplateRelativePath"

$labels = @(
    @{ name = "feature";   color = "99632F"; description = "Feature" },
    @{ name = "task";      color = "5BC340"; description = "Task (should have a parent feature)" },
    @{ name = "tech-debt"; color = "5C94CE"; description = "Technical debt" },
    @{ name = "bug";       color = "d73a4a"; description = "Something isn't working" },
    @{ name = "epic";      color = "7057ff"; description = "Epic" }
)

if ($SyncEpicTemplate -and -not (Test-Path -LiteralPath $epicTemplatePath)) {
    throw "Epic issue template was not found at $epicTemplatePath"
}

if ($ProjectNumbers.Count -gt 0 -and -not $SyncEpicTemplate) {
    Write-Host "Project synchronization will use the existing epic label and open Epic issues."
}

$repoDataJson = gh repo list $org --limit 1000 --json name,isArchived,hasIssuesEnabled
if ($LASTEXITCODE -ne 0) {
    throw "Unable to list repositories in $org"
}
$repos = @($repoDataJson | ConvertFrom-Json)

Write-Host "Found $($repos.Count) repos in $org"
if ($DryRun) {
    Write-Host "Dry run: no GitHub changes will be made."
}
Write-Host ""

$projectIssueUrls = @{}
if ($ProjectNumbers.Count -gt 0 -and -not $DryRun) {
    foreach ($projectNumber in $ProjectNumbers) {
        $projectItemsJson = gh project item-list $projectNumber --owner $org --limit 1000 --format json
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to read organization Project #$projectNumber. Refresh gh auth with the project scope (gh auth refresh -s project)."
        }

        $projectItems = @($projectItemsJson | ConvertFrom-Json)
        $projectIssueUrls[$projectNumber] = @(
            $projectItems |
                ForEach-Object { $_.content.url } |
                Where-Object { $_ }
        )
    }
}

$templateContent = $null
$templateBase64 = $null
if ($SyncEpicTemplate) {
    $templateContent = Get-Content -LiteralPath $epicTemplatePath -Raw
    $templateBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($templateContent))
}

foreach ($repoInfo in $repos) {
    $repo = $repoInfo.name
    $fullRepo = "$org/$repo"

    if ($repoInfo.isArchived) {
        Write-Host "Skipping archived repository $fullRepo"
        continue
    }

    Write-Host "Processing $fullRepo ..."

    foreach ($label in $labels) {
        if ($DryRun) {
            Write-Host "  [DRY-RUN] label $($label.name)"
            continue
        }

        $createOutput = gh label create $label.name `
            --repo $fullRepo `
            --color $label.color `
            --description $label.description `
            --force 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] $($label.name)"
        } else {
            Write-Host "  [FAIL] $($label.name): $createOutput" -ForegroundColor Red
        }
    }

    if ($SyncEpicTemplate) {
        if ($DryRun) {
            Write-Host "  [DRY-RUN] template $epicTemplateRelativePath"
        } else {
            $templateEndpoint = "repos/$fullRepo/contents/$epicTemplateRelativePath"
            $existingSha = gh api $templateEndpoint --jq '.sha' 2>$null
            $templateArgs = @(
                "api", "--method", "PUT", $templateEndpoint,
                "--field", "message=chore: sync Epic issue template",
                "--field", "content=$templateBase64"
            )
            if ($LASTEXITCODE -eq 0 -and $existingSha) {
                $templateArgs += @("--field", "sha=$existingSha")
            }

            $templateOutput = & gh @templateArgs 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [OK] $epicTemplateRelativePath"
            } else {
                Write-Host "  [FAIL] $epicTemplateRelativePath`: $templateOutput" -ForegroundColor Red
            }
        }
    }

    if ($ProjectNumbers.Count -gt 0) {
        if (-not $repoInfo.hasIssuesEnabled) {
            Write-Host "  [SKIP] issues are disabled"
            continue
        }

        $epicIssues = @()
        if (-not $DryRun) {
            $epicIssues = @(gh issue list --repo $fullRepo --label epic --state open --limit 1000 --json url -q '.[].url')
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  [FAIL] unable to list open Epic issues" -ForegroundColor Red
                continue
            }
        }

        foreach ($projectNumber in $ProjectNumbers) {
            if ($DryRun) {
                Write-Host "  [DRY-RUN] add open Epic issues to project #$projectNumber"
                continue
            }

            foreach ($issueUrl in $epicIssues) {
                if ($projectIssueUrls[$projectNumber] -contains $issueUrl) {
                    Write-Host "  [SKIP] project #$projectNumber already contains $issueUrl"
                    continue
                }

                $projectOutput = gh project item-add $projectNumber --owner $org --url $issueUrl 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  [OK] project #$projectNumber <- $issueUrl"
                } else {
                    Write-Host "  [FAIL] project #$projectNumber <- $issueUrl`: $projectOutput" -ForegroundColor Red
                }
            }
        }
    }
}

Write-Host ""
Write-Host "Done."
