#!/bin/bash

# Server tmux session name
SESSION_NAME="gameserver"

# Base directory for server files
SERVER_DIR="/minecraft"

# Make sure we're in the right directory
cd "$SERVER_DIR" || {
    echo "Failed to change to $SERVER_DIR directory!"
    exit 1
}

# Check if this is a fresh server installation by looking for startup script
is_fresh_install() {
    # Check if there's a startup script in the directory
    if find "$SERVER_DIR" -name "start*.sh" -type f | grep -q .; then
        # Startup script exists, so this is NOT a fresh install
        return 1
    fi

    # No startup script found, consider this a fresh install
    echo "Detected fresh server installation (no startup script found)"
    return 0
}

# Find the startup script in the server directory
find_startup_script() {
    # Find the first script matching start*.sh pattern
    STARTUP_SCRIPT=$(find "$SERVER_DIR" -name "start*.sh" -type f | head -n 1)

    if [ -z "$STARTUP_SCRIPT" ]; then
        echo "No startup script (start*.sh) found in $SERVER_DIR!"
        return 1
    fi

    echo "Found startup script: $(basename "$STARTUP_SCRIPT")"
    return 0
}

# Check required dependencies
check_dependencies() {
    local missing_deps=0

    for cmd in tmux curl unzip git; do
        if ! command -v $cmd &> /dev/null; then
            echo "$cmd is not installed. Please install it first."
            missing_deps=1
        fi
    done

    if [ $missing_deps -eq 1 ]; then
        return 1
    fi

    return 0
}

# Function to download server files
download_server_files() {
    if [ -z "$DOWNLOAD_SERVER_URL" ]; then
        echo "DOWNLOAD_SERVER_URL environment variable is not set. Skipping download."
        return 0
    fi

    echo "Downloading server files from $DOWNLOAD_SERVER_URL to $SERVER_DIR..."

    # Create a temporary directory for the download
    TEMP_DIR=$(mktemp -d)
    SERVER_ZIP="$TEMP_DIR/server.zip"

    # Download the server files
    if ! curl -L -o "$SERVER_ZIP" "$DOWNLOAD_SERVER_URL"; then
        echo "Failed to download server files!"
        rm -rf "$TEMP_DIR"
        return 1
    fi

    echo "Download completed. Extracting files to $SERVER_DIR..."

    # Extract the zip file to a temporary extraction directory
    EXTRACT_DIR="$TEMP_DIR/extract"
    mkdir -p "$EXTRACT_DIR"

    if ! unzip -o "$SERVER_ZIP" -d "$EXTRACT_DIR"; then
        echo "Failed to extract server files!"
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # Check if extraction created a single directory with all contents
    EXTRACTED_DIRS=($(ls -d "$EXTRACT_DIR"/*/ 2>/dev/null))
    if [ ${#EXTRACTED_DIRS[@]} -eq 1 ] && [ -d "${EXTRACTED_DIRS[0]}" ]; then
        echo "Detected single parent directory: $(basename "${EXTRACTED_DIRS[0]}")"
        echo "Moving contents up one level..."
        mv "${EXTRACTED_DIRS[0]}"/* "$SERVER_DIR/"
    else
        # Multiple directories or files at root level, just copy everything
        cp -r "$EXTRACT_DIR"/* "$SERVER_DIR/"
    fi

    # Clean up
    rm -rf "$TEMP_DIR"
    echo "Server files downloaded and extracted successfully!"
    return 0
}

# Function to check if repository is configured
is_repo_configured() {
    if [ -z "$REPO_URL" ] || [ -z "$GIT_TOKEN" ]; then
        return 1  # Not configured
    fi
    return 0  # Configured
}

# Function to pull configuration from Git repository
pull_config() {
    if ! is_repo_configured; then
        echo "Repository not configured (REPO_URL or GIT_TOKEN not set). Skipping config pull."
        return 0
    fi

    echo "Pulling configuration from $REPO_URL to $SERVER_DIR..."

    # Create a temporary directory for cloning
    TEMP_DIR=$(mktemp -d)

    # Clone the repository with the token
    REPO_URL_WITH_TOKEN=$(echo "$REPO_URL" | sed "s|https://|https://$GIT_TOKEN@|")
    if ! git clone "$REPO_URL_WITH_TOKEN" "$TEMP_DIR"; then
        echo "Failed to clone configuration repository!"
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # Copy all files from repository to server
    echo "Copying all files from repository to server..."

    # Find all files in the temp directory (excluding .git directory)
    find "$TEMP_DIR" -type f -not -path "*/\.git/*" | while read file; do
        # Get relative path to TEMP_DIR
        rel_path=${file#"$TEMP_DIR/"}

        # Create directory in server if it doesn't exist
        mkdir -p "$SERVER_DIR/$(dirname "$rel_path")"

        # Copy the file to the server
        cp "$file" "$SERVER_DIR/$rel_path"

        echo "Copying: $rel_path"
    done

    # # Copy only world/ and config/ directories if they exist in the repo
    # for dir in "world" "config"; do
    #     if [ -d "$TEMP_DIR/$dir" ]; then
    #         echo "Copying $dir from repository to server..."

    #         # Create directory in server if it doesn't exist
    #         mkdir -p "$SERVER_DIR/$dir"

    #         # Copy directory contents from repo to server
    #         cp -r "$TEMP_DIR/$dir"/* "$SERVER_DIR/$dir/"
    #     else
    #         echo "Directory $dir not found in repository"
    #     fi
    # done

    # Clean up
    rm -rf "$TEMP_DIR"
    echo "Configuration pulled successfully!"
    return 0
}

# Function to push configuration changes back to the repository
push_config() {
    if ! is_repo_configured; then
        echo "Repository not configured. Skipping config push."
        return 0
    fi

    echo "Preparing to push configuration changes to $REPO_URL..."

    # Create a temporary directory for the repo
    TEMP_DIR=$(mktemp -d)

    # Clone the repository with the token
    REPO_URL_WITH_TOKEN=$(echo "$REPO_URL" | sed "s|https://|https://$GIT_TOKEN@|")
    if ! git clone "$REPO_URL_WITH_TOKEN" "$TEMP_DIR"; then
        echo "Failed to clone configuration repository for pushing!"
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # Set up git config
    git config --global user.email "minecraft-server@example.com"
    git config --global user.name "Minecraft Server Automation"

    # Track all files and directories in $SERVER_DIR
    echo "Syncing all files from $SERVER_DIR..."

    # Copy all files to the repo
    find "$SERVER_DIR" -type f -size -45M | while read file; do
        # Get relative path to SERVER_DIR
        rel_path=${file#"$SERVER_DIR/"}

        # Create directory in repo if it doesn't exist
        mkdir -p "$TEMP_DIR/$(dirname "$rel_path")"

        # Copy the file to the repo
        cp "$file" "$TEMP_DIR/$rel_path"

        echo "Adding: $rel_path"
    done

    # echo "Finding world and config directories for syncing..."

    # # Only track world/ and config/ and ts-authkey-test/ directories
    # for dir in "world" "config" "ts-authkey-test"; do
    #     if [ -d "$SERVER_DIR/$dir" ]; then
    #         echo "Syncing $dir directory..."

    #         # Create directory in repo if it doesn't exist
    #         mkdir -p "$TEMP_DIR/$dir"

    #         # Copy directory contents to the repo (excluding large files)
    #         find "$SERVER_DIR/$dir" -type f -size -200k | while read file; do
    #             # Get relative path to SERVER_DIR
    #             rel_path=${file#"$SERVER_DIR/"}

    #             # Create directory in repo if it doesn't exist
    #             mkdir -p "$TEMP_DIR/$(dirname "$rel_path")"

    #             # Copy the file to the repo
    #             cp "$file" "$TEMP_DIR/$rel_path"

    #             echo "Adding: $rel_path"
    #         done
    #     else
    #         echo "Directory $dir not found in $SERVER_DIR"
    #     fi
    # done

    # Go to the repo directory
    cd "$TEMP_DIR" || {
        echo "Failed to change to temp directory for git operations!"
        rm -rf "$TEMP_DIR"
        return 1
    }

    # Check if there are changes to commit
    if git status --porcelain | grep -q .; then
        # Add all changes
        git add -A

        # Commit the changes
        git commit -m "Automatic config update on $(date)"

        # Push the changes
        if git push origin main || git push origin master; then
            echo "Successfully pushed configuration changes to repository!"
        else
            echo "Failed to push changes to repository!"
            cd "$SERVER_DIR"
            rm -rf "$TEMP_DIR"
            return 1
        fi
    else
        echo "No configuration changes to push."
    fi

    # Return to the server directory and clean up
    cd "$SERVER_DIR"
    rm -rf "$TEMP_DIR"
    return 0
}

# Initialize the server (first-time setup)
init_server() {
    echo "Initializing server..."

    # Check dependencies before proceeding
    if ! check_dependencies; then
        echo "Missing required dependencies. Cannot initialize server."
        return 1
    fi

    # Download server files if needed
    if ! download_server_files; then
        echo "Failed to prepare server files. Initialization failed."
        return 1
    fi

    # Find the startup script
    if ! find_startup_script; then
        echo "Failed to find startup script. Initialization failed."
        return 1
    fi

    # Determine the port to check
    MINECRAFT_PORT=25565  # Default Minecraft port
    if [ -f "$SERVER_DIR/server.properties" ] && grep -q "^server-port=" "$SERVER_DIR/server.properties"; then
        # Extract port from server.properties if it exists
        MINECRAFT_PORT=$(grep "^server-port=" "$SERVER_DIR/server.properties" | cut -d'=' -f2)
    fi

    # Accept EULA
    echo "Accept EULA"
    echo 'eula=true' > "$SERVER_DIR/eula.txt"

    echo "Starting server temporarily to generate configuration files..."

    # Create a temporary tmux session for initialization
    INIT_SESSION="init_minecraft"
    tmux new-session -d -s $INIT_SESSION -c "$SERVER_DIR" "bash $STARTUP_SCRIPT"

    echo "Waiting for server to become available on port $MINECRAFT_PORT..."

    # Wait a moment for the server to begin
    sleep 10

    # Send "I agree" command to the server (just in case)
    echo "Send "I agree" command to the server (just in case)"
    tmux send-keys -t $INIT_SESSION "I agree" C-m

    # Wait for server to be pingable (maximum 5 minutes)
    MAX_WAIT=300
    for ((i=1; i<=MAX_WAIT; i++)); do
        # Check if port is open using netcat or curl
        if command -v nc &> /dev/null; then
            if nc -z localhost $MINECRAFT_PORT &> /dev/null; then
                echo "Server is now available (detected after $i seconds)"
                break
            fi
        elif command -v curl &> /dev/null; then
            if curl -s localhost:$MINECRAFT_PORT -m 1 &> /dev/null; then
                echo "Server is now available (detected after $i seconds)"
                break
            fi
        else
            # Fall back to a longer wait if we can't check
            echo "Neither netcat nor curl available to check server status. Waiting 60 seconds..."
            sleep 60
            break
        fi

        # If we've waited the maximum time, assume server is ready
        if [ $i -eq $MAX_WAIT ]; then
            echo "Maximum wait time reached. Assuming server is ready."
            break
        fi

        sleep 1
        echo -n "."
        if [ $((i % 10)) -eq 0 ]; then
            echo " $i seconds"
        fi
    done

    echo "Stopping temporary server..."
    # Send stop command to the server
    tmux send-keys -t $INIT_SESSION "/stop" C-m

    # Wait a moment for the server to begin shutdown process
    sleep 10

    # Send Ctrl+C twice to ensure the server process terminates
    tmux send-keys -t $INIT_SESSION C-c
    sleep 1
    tmux send-keys -t $INIT_SESSION C-c

    # Wait for server to shut down
    sleep 10

    # Kill the tmux session if it's still running
    tmux kill-session -t $INIT_SESSION 2>/dev/null


    # Now the server should have generated all necessary files
    echo "Server files generated successfully."

    # Modify server.properties for cracked clients if needed
    if [ "${ALLOW_CRACK_CLIENT}" = "true" ]; then
        echo "Configuring server for offline mode (cracked clients)"
        if [ -f "$SERVER_DIR/server.properties" ]; then
            # Replace online-mode=true with online-mode=false
            sed -i 's/^online-mode=.*/online-mode=false/' "$SERVER_DIR/server.properties"

            # Verify the change was made
            if grep -q "^online-mode=false" "$SERVER_DIR/server.properties"; then
                echo "Successfully set online-mode=false"
            else
                echo "Failed to set online-mode=false, adding it manually"
                echo "online-mode=false" >> "$SERVER_DIR/server.properties"
            fi
        else
            echo "Warning: server.properties not found after initialization"
        fi
    fi

    # Pull configuration AFTER server has generated default files
    if is_repo_configured; then
        echo "Pulling configuration from repository to override default settings..."
        if ! pull_config; then
            echo "Failed to pull configuration, but will continue with initialization."
        fi
    fi

    echo "Server initialization completed successfully!"
    sleep 10
    return 0
}

# Start the server in a tmux session
start_server() {
    # Check if session already exists
    if tmux has-session -t $SESSION_NAME 2>/dev/null; then
        echo "Server is already running in tmux session '$SESSION_NAME'"
        echo "Connect to it using: tmux attach -t $SESSION_NAME"
        return 1
    fi

    # Check if initialization is needed
    if is_fresh_install; then
        echo "Fresh installation detected, initializing server..."
        if ! init_server; then
            echo "Server initialization failed. Not starting server."
            return 1
        fi
    else
        # For existing installations, pull the latest config before starting
        echo "Pulling latest configuration from repository..."
        pull_config
    fi

    # Find the startup script
    if ! find_startup_script; then
        echo "Failed to find startup script. Not starting server."
        return 1
    fi

    echo "Starting server in tmux session '$SESSION_NAME'..."
    # Create new tmux session, running from SERVER_DIR
    tmux new-session -d -s $SESSION_NAME -c "$SERVER_DIR" "bash $STARTUP_SCRIPT"
    echo "Server started successfully!"
    echo "To view the server console: tmux attach -t $SESSION_NAME"
    echo "To detach from the console without stopping the server: Press Ctrl+B then D"

    # Send "I agree" command to the server (just in case)
    sleep 10
    echo "Send "I agree" command to the server (just in case)"
    tmux send-keys -t $SESSION_NAME "I agree" C-m
}

# Stop the server gracefully
stop_server() {
    # Check if session exists
    if ! tmux has-session -t $SESSION_NAME 2>/dev/null; then
        echo "Server is not running."
        return 1
    fi

    echo "Stopping server..."
    # Send /stop command to the tmux session
    tmux send-keys -t $SESSION_NAME "/stop" C-m

    # Wait a moment for the server to begin shutdown process
    sleep 10

    # Send Ctrl+C twice to ensure the server process terminates
    tmux send-keys -t $SESSION_NAME C-c
    sleep 1
    tmux send-keys -t $SESSION_NAME C-c

    # Push config changes before killing the session
    push_config

    # Kill the tmux session
    tmux kill-session -t $SESSION_NAME
    echo "Server stopped successfully!"
}

# Restart the server
restart_server() {
    echo "Restarting server..."
    stop_server
    sleep 2
    start_server
}

# Get server status
status_server() {
    if tmux has-session -t $SESSION_NAME 2>/dev/null; then
        echo "Server is running in tmux session '$SESSION_NAME'"
        echo "Connect to it using: tmux attach -t $SESSION_NAME"
    else
        echo "Server is not running."
    fi
}

# Sync configuration without stopping
sync_config() {
    echo "Syncing configuration with repository..."

    # First pull any updates
    pull_config

    # Then push local changes
    push_config

    echo "Configuration sync completed."
}

# Function to download specific files from GitHub raw content
download_from_github() {
    local target_path="$1"

    if [ -z "$target_path" ]; then
        echo "No target path specified for GitHub download."
        return 1
    fi

    if [ -z "$REPO_URL" ] || [ -z "$GIT_TOKEN" ]; then
        echo "Repository not configured (REPO_URL or GIT_TOKEN not set). Skipping download."
        return 1
    fi

    # Extract owner and repo from the REPO_URL
    # Format should be https://github.com/owner/repo.git
    local repo_path=$(echo "$REPO_URL" | sed -E 's|https://github.com/||' | sed -E 's/\.git$//')
    local owner=$(echo "$repo_path" | cut -d '/' -f1)
    local repo=$(echo "$repo_path" | cut -d '/' -f2)

    if [ -z "$owner" ] || [ -z "$repo" ]; then
        echo "Failed to parse owner/repo from REPO_URL: $REPO_URL"
        return 1
    fi

    # Create target directory
    mkdir -p "$SERVER_DIR/$(dirname "$target_path")"

    # Construct raw content URL
    local branch="main" # Default branch
    local raw_url="https://raw.githubusercontent.com/$owner/$repo/$branch/$target_path"

    echo "Downloading from GitHub: $target_path"

    # Download the file
    if curl -f -s -H "Authorization: token $GIT_TOKEN" -o "$SERVER_DIR/$target_path" "$raw_url"; then
        echo "Successfully downloaded $target_path"
        return 0
    else
        echo "Failed to download $target_path"
        return 1
    fi
}

# Usage instructions
usage() {
    echo "Usage: $0 {init|start|stop|restart|status|attach|sync|get_file FILE}"
    echo ""
    echo "  init         - Initialize the server (first-time setup)"
    echo "  start        - Start the server in a tmux session"
    echo "  stop         - Stop the server gracefully"
    echo "  restart      - Restart the server"
    echo "  status       - Check if the server is running"
    echo "  attach       - Connect to the server console"
    echo "  sync         - Sync all configuration files with repository without stopping"
    echo "  get_file FILE - Download only the specified file from the repository"
    echo ""
}

# Parse command line arguments
case "$1" in
    init)
        init_server
        ;;
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    restart)
        restart_server
        ;;
    status)
        status_server
        ;;
    attach)
        tmux attach -t $SESSION_NAME
        ;;
    get_file)
        if [ -z "$2" ]; then
            echo "Error: No file specified for download."
            usage
            exit 1
        fi
        download_from_github "$2"
        ;;
    sync)
        sync_config
        ;;
    *)
        usage
        exit 1
        ;;
esac

exit 0
