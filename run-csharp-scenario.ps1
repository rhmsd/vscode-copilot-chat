# PowerShell script to run the C# Build Fix scenario in Docker

param(
    [switch]$SkipBuild,
    [switch]$Help
)

if ($Help) {
    Write-Host "Usage: .\run-csharp-scenario.ps1 [options]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -SkipBuild    Skip building Docker image and only run existing image"
    Write-Host "  -Help         Show this help message"
    Write-Host ""
    Write-Host "This script runs the C# Build Fix scenario in Docker."
    Write-Host "Requires GitHub authentication token (GITHUB_OAUTH_TOKEN or GITHUB_PAT)."
    exit 0
}

Write-Host "Running C# Build Fix Scenario..." -ForegroundColor Green

# Check for GitHub authentication token
if (!$env:GITHUB_OAUTH_TOKEN -and !$env:GITHUB_PAT) {
    Write-Host "⚠️  No GitHub authentication token found." -ForegroundColor Yellow
    Write-Host "You need either GITHUB_OAUTH_TOKEN or GITHUB_PAT to run simulations."
    Write-Host ""

    # Check if .env file exists and has token
    if (Test-Path ".env") {
        Write-Host "Checking .env file for tokens..."
        $envContent = Get-Content ".env" -Raw
        if ($envContent -match "GITHUB_OAUTH_TOKEN|GITHUB_PAT") {
            Write-Host "✅ Found token in .env file. Loading..." -ForegroundColor Green
            Get-Content ".env" | ForEach-Object {
                if ($_ -match "^([^=]+)=(.*)$") {
                    [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
                }
            }
        } else {
            Write-Host "❌ No token found in .env file." -ForegroundColor Red
        }
    }

    # If still no token, offer to generate one
    if (!$env:GITHUB_OAUTH_TOKEN -and !$env:GITHUB_PAT) {
        Write-Host ""
        $response = Read-Host "Would you like to generate a GitHub OAuth token? (y/n)"
        if ($response -eq "y" -or $response -eq "Y") {
            Write-Host "Running token generator..."
            npx tsx script/setup/getToken.mts

            # Load the newly created token
            if (Test-Path ".env") {
                Get-Content ".env" | ForEach-Object {
                    if ($_ -match "^([^=]+)=(.*)$") {
                        [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
                    }
                }
                Write-Host "✅ Token loaded from .env" -ForegroundColor Green
            } else {
                Write-Host "❌ Token generation may have failed. Please check .env file." -ForegroundColor Red
                exit 1
            }
        } else {
            Write-Host "❌ Cannot run simulation without authentication token." -ForegroundColor Red
            Write-Host "   Run: npx tsx script/setup/getToken.mts"
            Write-Host "   Or set: `$env:GITHUB_OAUTH_TOKEN = 'your_token_here'"
            exit 1
        }
    }
}

Write-Host "✅ GitHub authentication token available" -ForegroundColor Green

# Check if simulationMain.js exists
if (-not (Test-Path "dist/simulationMain.js")) {
    Write-Host "❌ simulationMain.js not found. Please build the project first:" -ForegroundColor Red
    Write-Host "   npm run compile" -ForegroundColor Yellow
    Write-Host "   or run: .\setup-and-run-csharp-scenario.sh" -ForegroundColor Yellow
    exit 1
}

# Build Docker image with .NET SDK (unless skipped)
if ($SkipBuild) {
    Write-Host "⏭️  Skipping Docker image build (-SkipBuild flag used)" -ForegroundColor Yellow
    Write-Host "Using existing vscode-copilot-simulation image..."

    # Verify the image exists
    $imageCheck = docker images vscode-copilot-simulation --format "{{.Repository}}"
    if ($imageCheck -notcontains "vscode-copilot-simulation") {
        Write-Host "❌ Docker image 'vscode-copilot-simulation' not found!" -ForegroundColor Red
        Write-Host "   You need to build it first by running this script without -SkipBuild" -ForegroundColor Yellow
        Write-Host "   or run: docker build -f Dockerfile.simulation -t vscode-copilot-simulation ." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "✅ Found existing Docker image" -ForegroundColor Green
} else {
    Write-Host "Building Docker image with .NET support..."
    docker build -f Dockerfile.simulation -t vscode-copilot-simulation .

    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to build Docker image" -ForegroundColor Red
        exit 1
    }
}

# Clean and create output directory
$OutputDir = "./csharp-simulation-output"
Write-Host "Preparing output directory: $OutputDir"

# Force clean approach - remove anything that might exist there
Write-Host "Cleaning output directory..."
if (Test-Path $OutputDir) {
    Remove-Item -Recurse -Force $OutputDir -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

# Verify it was created successfully
if (Test-Path $OutputDir) {
    Write-Host "✅ Successfully created $OutputDir" -ForegroundColor Green
} else {
    Write-Host "❌ Failed to create $OutputDir" -ForegroundColor Red
    exit 1
}

# Run the scenario
Write-Host "Running C# build fix scenario..."

try {
    # Prepare Docker arguments
    $dockerArgs = @(
        "run", "--rm", "-it",
        "-v", "$($(Get-Location).Path)/$OutputDir" + ":/workspace/output",
        "-v", "$($(Get-Location).Path)/myscenarios:/workspace/myscenarios"
    )

    # Add GitHub token environment variables
    if ($env:GITHUB_OAUTH_TOKEN) {
        $dockerArgs += @("-e", "GITHUB_OAUTH_TOKEN=$env:GITHUB_OAUTH_TOKEN")
    }
    if ($env:GITHUB_PAT) {
        $dockerArgs += @("-e", "GITHUB_PAT=$env:GITHUB_PAT")
    }

    # Build simulation command
    $simCmd = @"
        # Verify .NET is available
        dotnet --version
        echo 'Starting simulation...'

        # Clean and prepare output directory inside container
        cd /workspace
        echo 'Cleaning output directory inside container...'
        rm -rf /workspace/output/csharp-results
        mkdir -p /workspace/output/csharp-results

        # Run the external scenario
        node dist/simulationMain.js \
            --verbose \
            --sidebar \
            --model claude-sonnet-4 \
            -n 1 \
            --external-scenarios ./myscenarios/fix-build \
            --output /workspace/output/csharp-results \
            --skip-model-cache
"@

    # Add final arguments
    $dockerArgs += @("vscode-copilot-simulation", "bash", "-c", $simCmd)

    # Run the Docker command
    & docker @dockerArgs

    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "Scenario complete! Results are in: $OutputDir" -ForegroundColor Green
        Write-Host ""
        Write-Host "To view results:"
        Write-Host "  ls $OutputDir" -ForegroundColor Yellow
    } else {
        Write-Host "❌ Scenario failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "❌ Error running scenario: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}