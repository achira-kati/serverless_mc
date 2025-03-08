$envFile = "env"

# Check if the .env file exists and create it if not
if (-not (Test-Path $envFile)) {
    Write-Host "The $envFile file was not found. Creating it now..."
    New-Item -Path $envFile -ItemType File | Out-Null
}

# Read the contents of the .env file
$envContent = Get-Content $envFile -ErrorAction SilentlyContinue

# Check for REPO_URL and prompt if missing
if (-not ($envContent -match "^REPO_URL=")) {
    $repoUrl = Read-Host "Enter REPO_URL"
    Add-Content -Path $envFile -Value "REPO_URL=$repoUrl"
}

# Re-read the file to ensure the latest content is loaded
$envContent = Get-Content $envFile

# Check for GIT_TOKEN and prompt if missing
if (-not ($envContent -match "^GIT_TOKEN=")) {
    $gitToken = Read-Host "Enter GIT_TOKEN"
    Add-Content -Path $envFile -Value "GIT_TOKEN=$gitToken"
}

try {
    Write-Host "Running docker-compose build..."
    docker-compose build -q

    Write-Host "Running docker-compose up -d..."
    docker-compose up -d --remove-orphans

    Write-Host "Deployment complete!"
    Write-Host "Check http://localhost:4000/"
    Write-Host "Press Ctrl+C to stop the containers"

    # Keep the script running to capture Ctrl+C events
    while ($true) {
        Start-Sleep -Seconds 1
    }
}
finally {
    Write-Host "`nProcess interrupted or completed. Stopping containers..."
    docker-compose down | Out-Null
    Write-Host "Containers stopped."
}
