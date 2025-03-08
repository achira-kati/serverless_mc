#!/bin/bash
set -e

# Check if REPO_URL and GIT_TOKEN are set
if [ -n "$REPO_URL" ] && [ -n "$GIT_TOKEN" ]; then
  echo "REPO_URL and GIT_TOKEN are set, attempting to download env_config.json"

  # Extract owner and repo from REPO_URL if it's a GitHub repo
  if [[ "$REPO_URL" =~ github.com/([^/]+)/([^/]+) ]]; then
    OWNER=${BASH_REMATCH[1]}
    REPO=${BASH_REMATCH[2]}

    # Remove trailing .git if present
    REPO=${REPO%.git}

    # Use GitHub API with proper token authentication
    if curl -f -o /minecraft/env_config.json -H "Authorization: token $GIT_TOKEN" \
       "https://raw.githubusercontent.com/$OWNER/$REPO/main/env_config.json"; then
      echo "Successfully downloaded env_config.json to /minecraft directory"
    else
      echo "Failed to download env_config.json"
    fi
  else
    echo "ERROR: REPO_URL does not appear to be a GitHub repository URL"
    exit 1
  fi
else
  echo "REPO_URL or GIT_TOKEN not set, skipping env_config.json download"
fi

# Execute the main command
exec "$@"
