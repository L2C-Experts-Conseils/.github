# sync-labels.ps1
#
# Applies a standardized set of custom labels to all existing repositories in the
# L2C-Experts-Conseils GitHub organization. Uses the GitHub CLI (`gh`).
#
# Prerequisites:
#   - GitHub CLI installed: https://cli.github.com
#   - Authenticated with sufficient permissions: gh auth login
#
# Usage (from any terminal in the repo):
#   .\scripts\sync-labels.ps1
#
# The script is idempotent — safe to re-run. It will create labels that are missing
# and update existing ones if the color or description differs (via --force).

$org = "L2C-Experts-Conseils"

$labels = @(
    @{ name = "feature";   color = "99632F"; description = "Feature" },
    @{ name = "task";      color = "5BC340"; description = "Task (should have a parent feature)" },
    @{ name = "tech-debt"; color = "5C94CE"; description = "Technical debt" },
    @{ name = "bug";       color = "d73a4a"; description = "Something isn't working" }
)

# Get all repos in the org (handles pagination automatically)
$repos = gh repo list $org --limit 1000 --json name -q '.[].name' | ForEach-Object { $_.Trim() }

Write-Host "Found $($repos.Count) repos in $org"
Write-Host ""

foreach ($repo in $repos) {
    $fullRepo = "$org/$repo"
    Write-Host "Processing $fullRepo ..."

    foreach ($label in $labels) {
        # Try to create; if it already exists, update it instead
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
}

Write-Host ""
Write-Host "Done."
