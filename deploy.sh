#!/bin/bash

ENV_FILE="env"

# Handle Ctrl+C
trap 'echo -e "\nProcess interrupted. Stopping containers..."; docker-compose down; echo "Containers stopped."; exit 1' INT

# Create .env file if it doesn't exist
if [ ! -f "$ENV_FILE" ]; then
  echo "The $ENV_FILE file was not found. Creating it now..."
  touch "$ENV_FILE"
fi

# Check if REPO_URL exists in .env file
if ! grep -q "^REPO_URL=" "$ENV_FILE"; then
  echo -n "Enter REPO_URL: "
  read repo_url
  echo "REPO_URL=$repo_url" >> "$ENV_FILE"
fi

# Check if GIT_TOKEN exists in .env file
if ! grep -q "^GIT_TOKEN=" "$ENV_FILE"; then
  echo -n "Enter GIT_TOKEN: "
  read git_token
  echo "GIT_TOKEN=$git_token" >> "$ENV_FILE"
fi

# Run Docker commands
echo "Running docker-compose build..."
docker-compose build -q

echo "Running docker-compose up -d..."
docker-compose up -d --remove-orphans

echo "Deployment complete!"
echo "Check http://localhost:4000/"
echo "Press Ctrl+C to stop the containers"

# Keep script running to allow Ctrl+C to work
while true; do
  sleep 1
done
