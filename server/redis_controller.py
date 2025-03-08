#!/usr/bin/env python3
import json
import os
import re
import signal
import socket
import subprocess
import sys
import threading
import time

import redis
from mcstatus import JavaServer

# Redis connection
redis_client = redis.Redis(host="redis", port=6379, decode_responses=True)
pubsub = redis_client.pubsub()

# Server script path
SERVER_SCRIPT = "/usr/local/bin/server.sh"
# Minecraft directory
MINECRAFT_DIR = "/minecraft"
# Environment variables file
ENV_CONFIG_FILE = "/minecraft/env_config.json"

# Terminal monitoring related
TERMINAL_MONITOR_ACTIVE = False
TERMINAL_MONITOR_THREAD = None

# Redis channels
CONTROL_CHANNEL = "minecraft:control"
STATUS_CHANNEL = "minecraft:status"
LOGS_CHANNEL = "minecraft:logs"
XTERM_CHANNEL = "minecraft:xterm"
ERROR_CHANNEL = "minecraft:error"
DETAILS_CHANNEL = "minecraft:details"
EXTERNAL_CHANNEL = "minecraft:external_server"


# Signal handling for graceful shutdown
def signal_handler(sig, frame):
    print("Shutting down...")
    if TERMINAL_MONITOR_THREAD and TERMINAL_MONITOR_THREAD.is_alive():
        global TERMINAL_MONITOR_ACTIVE
        TERMINAL_MONITOR_ACTIVE = False
        TERMINAL_MONITOR_THREAD.join(timeout=2)
    sys.exit(0)


signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)


# Helper functions
def publish_status(status):
    redis_client.publish(STATUS_CHANNEL, status)
    print(f"Published status: {status}")


def publish_error(error):
    redis_client.publish(ERROR_CHANNEL, error)
    print(f"Published error: {error}")


def publish_log(log):
    redis_client.publish(LOGS_CHANNEL, log)


def publish_xterm_log(log):
    redis_client.publish(XTERM_CHANNEL, log)


def publish_details(details):
    if details is not None:
        redis_client.publish(DETAILS_CHANNEL, details)


def publish_external_server(message):
    redis_client.publish(EXTERNAL_CHANNEL, message)


def load_environment_variables():
    try:
        if os.path.exists(ENV_CONFIG_FILE):
            with open(ENV_CONFIG_FILE, "r") as f:
                env_vars = json.load(f)
                for key, value in env_vars.items():
                    os.environ[key] = value
                print(f"Loaded environment variables from {ENV_CONFIG_FILE}")
                return True
        else:
            print(f"Environment config file not found: {ENV_CONFIG_FILE}")
            sys.exit(0)
            return False
    except Exception as e:
        print(f"Error loading environment variables: {e}")
        sys.exit(0)
        return False


def save_environment_variables(variables):
    try:
        os.makedirs(os.path.dirname(ENV_CONFIG_FILE), exist_ok=True)
        with open(ENV_CONFIG_FILE, "w") as f:
            json.dump(variables, f, indent=2)
        print(f"Saved environment variables to {ENV_CONFIG_FILE}")
        return True
    except Exception as e:
        print(f"Error saving environment variables: {e}")
        return False


def execute_server_command(command, *args, timeout=600):
    try:
        # Update environment variables before executing command
        load_environment_variables()

        cmd = [SERVER_SCRIPT, command]
        cmd.extend(args)
        print(f"Executing: {' '.join(cmd)}")

        # Start the process with pipes for stdout and stderr
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            cwd=MINECRAFT_DIR,
            bufsize=1,  # Line buffered
        )

        # Collect output in these lists
        stdout_lines = []
        stderr_lines = []

        # Function to read from a stream and publish to xterm
        def read_stream(stream, lines_list, is_error=False):
            prefix = "[server.sh] E: " if is_error else "[server.sh] "
            for line in iter(stream.readline, ""):
                line = line.strip()
                if line:
                    lines_list.append(line)
                    # Skip certain lines if needed
                    if not is_error and (
                        line.startswith("Copying:")
                        or line.startswith("Adding:")
                    ):
                        continue
                    publish_xterm_log(prefix + line)
            stream.close()

        # Create and start threads for stdout and stderr
        stdout_thread = threading.Thread(
            target=read_stream, args=(process.stdout, stdout_lines)
        )
        stderr_thread = threading.Thread(
            target=read_stream, args=(process.stderr, stderr_lines, True)
        )

        stdout_thread.daemon = True
        stderr_thread.daemon = True
        stdout_thread.start()
        stderr_thread.start()

        # Wait for the process to complete with timeout
        try:
            return_code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.kill()
            publish_error(
                f"Command '{command}' timed out after {timeout} seconds"
            )
            return None

        # Wait for threads to finish processing output
        stdout_thread.join(timeout=5)  # Add timeout to thread joins
        stderr_thread.join(timeout=5)

        if return_code == 0:
            output = "\n".join(stdout_lines)
            print(f"Command executed successfully: {output}")
            return output
        else:
            error = "\n".join(stderr_lines)
            print(f"Command failed: {error}")
            publish_error(f"Command '{command}' failed: {error}")
            return None
    except Exception as e:
        error_msg = f"Failed to execute command '{command}': {str(e)}"
        print(error_msg)
        publish_error(error_msg)
        publish_xterm_log(f"[server.sh] EXCEPTION: {error_msg}")
        return None


def is_server_running():
    output = execute_server_command("status")
    if output:
        return "running" in output.lower()
    return False


def monitor_tmux_session():
    global TERMINAL_MONITOR_ACTIVE
    TERMINAL_MONITOR_ACTIVE = True
    last_content = ""

    while TERMINAL_MONITOR_ACTIVE:
        try:
            # Get tmux content with full ANSI colors preserved
            result = subprocess.run(
                ["tmux", "capture-pane", "-p", "-e", "-t", "gameserver"],
                capture_output=True,
                text=True,
            )

            if result.returncode == 0:
                current_content = result.stdout

                # Format the content nicely with proper line breaks
                formatted_content = format_terminal_output(current_content)

                # Only send if the content has changed
                if formatted_content != last_content:
                    publish_xterm_log(formatted_content)
                    last_content = formatted_content

            # Other code remains the same...
            time.sleep(1)  # Slightly faster refresh
        except Exception as e:
            print(f"Error in tmux monitor: {str(e)}")
            time.sleep(5)

    print("Terminal monitor stopped")


def format_terminal_output(content):
    """Format terminal output to make it more readable by treating lines with brackets as new log entries"""
    # Remove ANSI escape codes
    ansi_escape = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")
    content = ansi_escape.sub("", content)

    # Remove color codes like [32m, [39m
    color_codes = re.compile(r"\[\d{1,2}(?:;\d{1,2})*m")
    content = color_codes.sub("", content)

    # Split into lines
    lines = content.splitlines()
    formatted_lines = []
    buffer = ""

    # Simple pattern - any line starting with brackets is a new log entry
    bracket_pattern = re.compile(r"^\s*\[")

    for line in lines:
        stripped = line.strip()

        # Skip if line is empty
        if not stripped:
            if buffer:
                formatted_lines.append(buffer)
                buffer = ""
            formatted_lines.append("")
            continue

        # If this line starts with brackets or buffer is empty, it's a new log entry
        if bracket_pattern.match(stripped) or not buffer:
            if buffer:
                formatted_lines.append(buffer)
            buffer = stripped
        else:
            # This appears to be a continuation of a wrapped line
            buffer += " " + stripped

    # Add the last buffered line
    if buffer:
        formatted_lines.append(buffer)

    # Remove duplicate empty lines
    result_lines = []
    prev_empty = False

    for line in formatted_lines:
        if not line:
            if not prev_empty:
                result_lines.append(line)
                prev_empty = True
        else:
            result_lines.append(line)
            prev_empty = False

    return "\n".join(result_lines)


def check_external_server():
    """Check if someone else might be running a server on the same network"""
    try:
        # Check if there's a Minecraft process running not managed by our tmux
        result = subprocess.run(
            ["pgrep", "-f", "java.*minecraft"], capture_output=True, text=True
        )

        if result.returncode == 0:
            # Found Java processes that might be Minecraft
            processes = result.stdout.strip().split("\n")

            # Now check if we're running a server in tmux
            tmux_result = subprocess.run(
                ["tmux", "has-session", "-t", "gameserver"],
                capture_output=True,
                text=True,
            )

            if tmux_result.returncode != 0:
                # We don't have a tmux session but there's a Java process
                publish_external_server(
                    "Warning: Detected possible external Minecraft server running"
                )
    except Exception as e:
        print(f"Error checking for external servers: {str(e)}")


def start_terminal_monitor():
    global TERMINAL_MONITOR_THREAD
    if TERMINAL_MONITOR_THREAD and TERMINAL_MONITOR_THREAD.is_alive():
        print("Terminal monitor already running")
        return

    TERMINAL_MONITOR_THREAD = threading.Thread(target=monitor_tmux_session)
    TERMINAL_MONITOR_THREAD.daemon = True
    TERMINAL_MONITOR_THREAD.start()
    print("Started terminal monitor thread")


def stop_terminal_monitor():
    global TERMINAL_MONITOR_ACTIVE, TERMINAL_MONITOR_THREAD
    if TERMINAL_MONITOR_THREAD and TERMINAL_MONITOR_THREAD.is_alive():
        TERMINAL_MONITOR_ACTIVE = False
        TERMINAL_MONITOR_THREAD.join(timeout=2)
        TERMINAL_MONITOR_THREAD = None
        print("Stopped terminal monitor thread")


def fetch_server_logs(lines=100):
    try:
        logs = []

        # Try to find the server.log file in the minecraft directory
        log_files = []
        for root, dirs, files in os.walk(MINECRAFT_DIR):
            for file in files:
                if file == "server.log" or file == "latest.log":
                    log_files.append(os.path.join(root, file))

        if not log_files:
            message = "No server log files found"
            publish_log(message)
            return

        # Use the first log file found
        log_file = log_files[0]
        print(f"Found log file: {log_file}")

        # Read the file and get the last N lines
        with open(log_file, "r", encoding="utf-8", errors="replace") as f:
            all_lines = f.readlines()
            for line in all_lines[-lines:]:
                publish_log(line.strip())

    except Exception as e:
        error_msg = f"Error fetching logs: {str(e)}"
        print(error_msg)
        publish_error(error_msg)


def get_tailscale_ip(pub=True):
    try:
        result = subprocess.run(
            ["tailscale", "ip", "-4"], capture_output=True, text=True
        )

        if result.returncode == 0:
            ip = result.stdout.strip()
            if ip:
                status_msg = (
                    f"Tailscale IP: {ip}, Connect to Minecraft at {ip}:25565"
                )
                if pub:
                    publish_status(status_msg)
                return ip

        publish_error("Failed to get Tailscale IP")
        return None
    except Exception as e:
        publish_error(f"Error getting Tailscale IP: {str(e)}")
        return None


def send_minecraft_command(text):
    if not is_server_running():
        publish_error("Cannot send command: Server is not running")
        return False

    try:
        cmd = ["tmux", "send-keys", "-t", "gameserver", text, "Enter"]
        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode == 0:
            publish_log(f"Sent command to Minecraft: {text}")
            return True
        else:
            publish_error(f"Failed to send command: {result.stderr}")
            return False
    except Exception as e:
        publish_error(f"Error sending Minecraft command: {str(e)}")
        return False


def start_tailscale():
    try:
        # Check if required environment variables are set
        required_vars = ["TS_STATE_DIR", "TS_AUTHKEY", "TS_HOSTNAME"]
        missing_vars = [var for var in required_vars if var not in os.environ]

        if missing_vars:
            error_msg = f"Missing required environment variables for Tailscale: {', '.join(missing_vars)}"
            print(error_msg)
            publish_error(error_msg)
            return False

        # Start tailscaled in a tmux session
        cmd = f'tmux new-session -d -s tailscale "tailscaled --statedir={os.environ["TS_STATE_DIR"]}"'
        subprocess.run(cmd, shell=True, check=True)
        print("Started tailscaled in tmux session")

        # Wait a moment for tailscaled to initialize
        time.sleep(2)

        # Login to tailscale
        cmd = ["tailscale", "login", f"--auth-key={os.environ['TS_AUTHKEY']}"]
        subprocess.run(cmd, check=True)
        print("Logged in to tailscale")

        # Set hostname
        cmd = ["tailscale", "set", f"--hostname={os.environ['TS_HOSTNAME']}"]
        subprocess.run(cmd, check=True)
        print("Set tailscale hostname")

        return True
    except Exception as e:
        print(f"Error starting tailscale: {e}")
        publish_error(f"Failed to start tailscale: {str(e)}")
        return False


# Command handlers
def handle_command(command_data):
    if isinstance(command_data, str):
        # Simple command
        command = command_data
        args = {}
    else:
        # JSON command with arguments
        try:
            command = command_data.get("command")
            args = command_data.get("args", {})
        except:
            publish_error("Invalid command format")
            return

    print(f"Handling command: {command}, args: {args}")

    if command == "start":
        publish_status(
            "Starting server... (Can take up to 10 minutes with many mods)"
        )
        output = execute_server_command("start")
        if output:
            start_terminal_monitor()

    elif command == "stop":
        publish_status(
            "Stopping server... (Can take up to 10 minutes to safely save world data)"
        )
        output = execute_server_command("stop")
        stop_terminal_monitor()

    elif command == "restart":
        publish_status("Restarting server...")
        stop_terminal_monitor()
        output = execute_server_command("restart")
        if output:
            start_terminal_monitor()

    elif command == "status":
        ip = get_tailscale_ip(pub=False)

        if ip:
            # First check if Minecraft server port is open
            is_port_open = False
            try:
                # Try to connect to Minecraft port
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                    s.settimeout(2)
                    result = s.connect_ex((ip, 25565))
                    is_port_open = result == 0
            except:
                is_port_open = False

            if is_port_open:
                status_message = f"Server running (accessible at {ip}:25565)"
                publish_status(status_message)

                # Try to get detailed information using mcstatus if available
                server_details = "Server is online and operational"

                try:
                    server = JavaServer.lookup(f"{ip}:25565")
                    status = server.status()

                    # Get detailed information
                    players_online = (
                        f"{status.players.online}/{status.players.max}"
                    )
                    version = status.version.name
                    latency = f"{status.latency:.1f}ms"

                    server_details = f"Version: {version} | Players: {players_online} | Ping: {latency}"
                    if hasattr(status, "description") and status.description:
                        motd = status.description
                        if hasattr(
                            motd, "to_plain"
                        ):  # Handle different mcstatus versions
                            motd = motd.to_plain()
                        server_details += f" | MOTD: {motd}"
                except Exception as e:
                    print(f"Error getting detailed server info: {e}")

                publish_details(server_details)
            else:
                # Check if tmux session exists
                tmux_exists = False
                try:
                    result = subprocess.run(
                        ["tmux", "has-session", "-t", "gameserver"],
                        capture_output=True,
                        text=True,
                        check=False,  # Don't raise exception on non-zero exit
                    )
                    tmux_exists = result.returncode == 0
                except Exception as e:
                    print(f"Error checking tmux session: {e}")
                    tmux_exists = False

                if tmux_exists:
                    # Server is starting - tmux exists but port not open yet
                    publish_status(
                        f"Server is starting (will be accessible at {ip}:25565)"
                    )
                    publish_details("Server is booting up. Please wait...")
                else:
                    # IP exists but server isn't responding and no tmux session
                    publish_status("Stopped (ready to run)")
                    publish_details(None)
        else:
            # No Tailscale IP available
            publish_status("Tailscale not connected")
            publish_details(None)

    elif command == "logs":
        lines = args.get("lines", 100) if args else 100
        fetch_server_logs(lines)

    elif command == "tailscale_ip":
        get_tailscale_ip(pub=True)

    elif command == "minecraft_command":
        text = args.get("text") if args else None
        if text:
            send_minecraft_command(text)
        else:
            publish_error("No command text provided")

    elif command == "set_environment":
        sys.exit(0)

    elif command == "check_running_server":
        check_external_server()

    else:
        publish_error(f"Unknown command: {command}")


def download_tailscale_files():
    """Download Tailscale state files from Git repository"""
    try:
        # List of files to download from the ts-authkey-test/state directory
        state_files = [
            "ts-authkey-test/state/tailscaled.state",
        ]

        success = True
        for file_path in state_files:
            result = execute_server_command("get_file", file_path)
            if not result:
                publish_error(f"Failed to download {file_path}")
                success = False

        if success:
            # Reload environment variables if needed
            load_environment_variables()
            return True
        return False
    except Exception as e:
        publish_error(f"Failed to download Tailscale files: {str(e)}")
        return False


# Main function to listen for Redis messages
def listen_for_commands():
    print("Starting Redis listener...")
    # Load environment variables at startup
    load_environment_variables()

    # First download just the Tailscale state files
    download_tailscale_files()

    # Start tailscale
    start_tailscale()

    # Start the terminal monitor
    start_terminal_monitor()

    # Subscribe to the control channel
    pubsub.subscribe(CONTROL_CHANNEL)

    # Check server status at startup
    execute_server_command("status")

    try:
        for message in pubsub.listen():
            if message["type"] == "message":
                channel = message["channel"]
                data = message["data"]

                print(f"Received on {channel}: {data}")

                if channel == CONTROL_CHANNEL:
                    try:
                        # Try to parse as JSON first
                        command_data = json.loads(data)
                    except json.JSONDecodeError:
                        # If not JSON, treat as simple string command
                        command_data = data

                    handle_command(command_data)
    except KeyboardInterrupt:
        print("Shutting down listener...")
    finally:
        pubsub.unsubscribe()
        print("Unsubscribed from Redis channels")


if __name__ == "__main__":
    listen_for_commands()
