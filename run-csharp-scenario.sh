#!/bin/bash

# Script to run the C# Build Fix scenario in Docker

set -e

# Parse command line arguments
SKIP_BUILD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --skip-build    Skip building Docker image and only run existing image"
            echo "  --help, -h      Show this help message"
            echo ""
            echo "This script runs the C# Build Fix scenario in Docker."
            echo "Requires GitHub authentication token (GITHUB_OAUTH_TOKEN or GITHUB_PAT)."
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "Running C# Build Fix Scenario..."

# Check for GitHub authentication token
if [ -z "$GITHUB_OAUTH_TOKEN" ] && [ -z "$GITHUB_PAT" ]; then
    echo "⚠️  No GitHub authentication token found."
    echo "You need either GITHUB_OAUTH_TOKEN or GITHUB_PAT to run simulations."
    echo ""

    # Check if .env file exists and has token
    if [ -f ".env" ]; then
        echo "Checking .env file for tokens..."
        if grep -q "GITHUB_OAUTH_TOKEN\|GITHUB_PAT" .env; then
            echo "✅ Found token in .env file. Loading..."
            set -a # automatically export variables
            source .env
            set +a
        else
            echo "❌ No token found in .env file."
        fi
    fi

    # If still no token, offer to generate one
    if [ -z "$GITHUB_OAUTH_TOKEN" ] && [ -z "$GITHUB_PAT" ]; then
        echo ""
        echo "Would you like to generate a GitHub OAuth token? (y/n)"
        read -r response
        if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
            echo "Running token generator..."
            npx tsx script/setup/getToken.mts

            # Load the newly created token
            if [ -f ".env" ]; then
                set -a
                source .env
                set +a
                echo "✅ Token loaded from .env"
            else
                echo "❌ Token generation may have failed. Please check .env file."
                exit 1
            fi
        else
            echo "❌ Cannot run simulation without authentication token."
            echo "   Run: npx tsx script/setup/getToken.mts"
            echo "   Or set: export GITHUB_OAUTH_TOKEN=your_token_here"
            exit 1
        fi
    fi
fi

echo "✅ GitHub authentication token available"

# Check if simulationMain.js exists
if [ ! -f "dist/simulationMain.js" ]; then
    echo "❌ simulationMain.js not found. Please build the project first:"
    echo "   npm run compile"
    echo "   or run: ./setup-and-run-csharp-scenario.sh"
    exit 1
fi

# Build Docker image with .NET SDK (unless skipped)
if [ "$SKIP_BUILD" = true ]; then
    echo "⏭️  Skipping Docker image build (--skip-build flag used)"
    echo "Using existing vscode-copilot-simulation image..."

    # Verify the image exists
    if ! docker images vscode-copilot-simulation | grep -q vscode-copilot-simulation; then
        echo "❌ Docker image 'vscode-copilot-simulation' not found!"
        echo "   You need to build it first by running this script without --skip-build"
        echo "   or run: docker build -f Dockerfile.simulation -t vscode-copilot-simulation ."
        exit 1
    fi
    echo "✅ Found existing Docker image"
else
    echo "Building Docker image with .NET support..."
    docker build -f Dockerfile.simulation -t vscode-copilot-simulation .
fi

# Clean and create output directory
OUTPUT_DIR="./csharp-simulation-output-ext"
echo "Preparing output directory: $OUTPUT_DIR"

# Force clean approach - remove anything that might exist there
echo "Cleaning output directory..."
rm -rf "$OUTPUT_DIR" 2>/dev/null || true
mkdir -p "$OUTPUT_DIR"

# Verify it was created successfully
if [ -d "$OUTPUT_DIR" ]; then
    echo "✅ Successfully created $OUTPUT_DIR"
else
    echo "❌ Failed to create $OUTPUT_DIR"
    exit 1
fi

# Run the scenario
echo "Running C# build fix scenario..."
docker run --rm -it \
    -v "$(pwd)/$OUTPUT_DIR:/workspace/output" \
    -v "$(pwd)/myscenarios:/workspace/myscenarios" \
    -e GITHUB_OAUTH_TOKEN="$GITHUB_OAUTH_TOKEN" \
    -e GITHUB_PAT="$GITHUB_PAT" \
    vscode-copilot-simulation \
    bash -c "
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
            --in-extension-host \
            --skip-model-cache \
        2>&1 | tee console.log

    "

echo ""
echo "Scenario complete! Results are in: $OUTPUT_DIR"
echo ""
echo "To view results:"
echo "  ls $OUTPUT_DIR"