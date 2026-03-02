#!/bin/bash
# Script to create GitHub repository and push changes
# Run this after authenticating with GitHub CLI

set -e

# Check if gh is authenticated
if ! gh auth status &>/dev/null; then
    echo "Error: GitHub CLI is not authenticated."
    echo "Please run: gh auth login"
    echo ""
    echo "Then re-run this script."
    exit 1
fi

REPO_NAME="rag-nvidia-hosted-cuvs"
ORG="Polypod"
DESCRIPTION="NVIDIA RAG Blueprint with NVIDIA API Catalog NIMs and cuVS Vector DB"

echo "Creating GitHub repository: $ORG/$REPO_NAME"

# Create the repository
gh repo create $ORG/$REPO_NAME \
    --private \
    --description "$DESCRIPTION" \
    --source . \
    --push

echo ""
echo "Repository created and pushed successfully!"
echo "URL: https://github.com/$ORG/$REPO_NAME"
