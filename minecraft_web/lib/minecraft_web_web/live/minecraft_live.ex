defmodule MinecraftWebWeb.MinecraftLive do
  use MinecraftWebWeb, :live_view
  alias MinecraftWeb.RedisService
  require Logger

  # Path to environment configuration file
  @config_file_path "/minecraft/env_config.json"

  # Default environment variable values
  @env_defaults %{
    "REPO_URL" => "",
    "GIT_TOKEN" => "",
    "DOWNLOAD_SERVER_URL" => "",
    "ALLOW_CRACK_CLIENT" => "true",
    "TS_AUTHKEY" => "",
    "GIT_USER_NAME" => "Minecraft Server Bot",
    "GIT_USER_EMAIL" => "minecraft-bot@example.com"
  }

  @impl true
  def mount(_params, _session, socket) do
    # Try to load environment variables from file
    case load_env_config() do
      {:error, "Configuration file not found"} ->
        # Redirect to server configuration page if config doesn't exist
        {:ok,
         socket
         |> redirect(to: ~p"/server-config")}

      env_result ->
        env_vars =
          case env_result do
            {:ok, vars} -> vars
            {:error, _} -> @env_defaults
          end

        # Check if configuration is valid
        errors = validate_env_vars(env_vars)
        config_valid = map_size(errors) == 0

        if connected?(socket) do
          # Subscribe to all channels
          Phoenix.PubSub.subscribe(MinecraftWeb.PubSub, "minecraft:status")
          Phoenix.PubSub.subscribe(MinecraftWeb.PubSub, "minecraft:error")
          Phoenix.PubSub.subscribe(MinecraftWeb.PubSub, "minecraft:logs")
          Phoenix.PubSub.subscribe(MinecraftWeb.PubSub, "minecraft:xterm")
          Phoenix.PubSub.subscribe(MinecraftWeb.PubSub, "minecraft:details")
          Phoenix.PubSub.subscribe(MinecraftWeb.PubSub, "minecraft:external_server")

          # Set up timer for periodic updates
          if connected?(socket), do: Process.send_after(self(), :update_status, 5000)

          # Initial data
          RedisService.fetch_logs(50)
        end

        {:ok,
         assign(socket,
           status: "Checking server status...",
           details: nil,
           logs: [],
           xterm_logs: [],
           active_tab: "terminal",
           environment_variables: env_vars,
           external_running: nil,
           # Show modal automatically if config is invalid
           show_env_modal: !config_valid,
           env_validation_errors: if(!config_valid, do: errors, else: %{}),
           config_valid: config_valid,
           show_ts_authkey: false,
           show_git_token: false
         )}
    end
  end

  # Error handling event
  @impl true
  def handle_event("dismiss_error", _, socket) do
    {:noreply, assign(socket, error: nil)}
  end

  # Environment variable modal handlers
  @impl true
  def handle_event("show_env_modal", _, socket) do
    {:noreply, assign(socket, show_env_modal: true)}
  end

  @impl true
  def handle_event("hide_env_modal", _, socket) do
    {:noreply, assign(socket, show_env_modal: false)}
  end

  @impl true
  def handle_event("send_command", %{"command" => command}, socket) do
    RedisService.send_command(command)
    # If the command is "start", clear the logs
    socket =
      if command == "start" do
        assign(socket, logs: [], xterm_logs: [])
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("send_minecraft_command", %{"command" => command}, socket) do
    RedisService.send_minecraft_command(command)
    {:noreply, socket}
  end

  @impl true
  def handle_event("fetch_logs", %{"lines" => lines}, socket) do
    lines_int = String.to_integer(lines)
    RedisService.fetch_logs(lines_int)
    {:noreply, socket}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: tab)}
  end

  @impl true
  def handle_info({:status, status}, socket) do
    {:noreply, assign(socket, status: status)}
  end

  @impl true
  def handle_info({:error, error}, socket) do
    # Log the error for debugging
    Logger.error("Critical Minecraft server error: #{error}")

    # Use put_flash to add the error message as a flash message
    {:noreply, socket |> put_flash(:error, "Server error: #{error}")}
  end

  @impl true
  def handle_info({:external_server, message}, socket) do
    if String.contains?(String.downcase(message), "warning") do
      {:noreply, assign(socket, external_running: true)}
    else
      {:noreply, assign(socket, external_running: nil)}
    end
  end

  @impl true
  def handle_info({:details, details}, socket) do
    {:noreply, assign(socket, details: details)}
  end

  @impl true
  def handle_info({:log, log}, socket) do
    logs = [log | socket.assigns.logs] |> Enum.take(100)
    {:noreply, assign(socket, logs: logs)}
  end

  @impl true
  def handle_info({:xterm_log, log}, socket) do
    xterm_logs = [log | socket.assigns.xterm_logs] |> Enum.take(500)
    {:noreply, assign(socket, xterm_logs: xterm_logs)}
  end

  @impl true
  def handle_info(:update_status, socket) do
    # Check status more frequently - every 5 seconds
    Process.send_after(self(), :update_status, 5000)

    RedisService.send_command("status")
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"env_vars" => env_vars}, socket) do
    errors = validate_env_vars(env_vars)

    {:noreply,
     assign(socket,
       environment_variables: env_vars,
       env_validation_errors: errors
     )}
  end

  @impl true
  def handle_event("toggle_ts_authkey_visibility", _params, socket) do
    {:noreply, assign(socket, show_ts_authkey: !socket.assigns.show_ts_authkey)}
  end

  @impl true
  def handle_event("toggle_git_token_visibility", _params, socket) do
    {:noreply, assign(socket, show_git_token: !socket.assigns.show_git_token)}
  end

  # Enhanced ANSI-to-HTML conversion for terminal output
  defp ansi_to_html(text) do
    text
    |> String.replace(~r/\x1b\[31m(.+?)\x1b\[0m/, "<span class='text-red-500'>\\1</span>")
    |> String.replace(~r/\x1b\[32m(.+?)\x1b\[0m/, "<span class='text-green-500'>\\1</span>")
    |> String.replace(~r/\x1b\[33m(.+?)\x1b\[0m/, "<span class='text-yellow-500'>\\1</span>")
    |> String.replace(~r/\x1b\[34m(.+?)\x1b\[0m/, "<span class='text-blue-500'>\\1</span>")
    |> String.replace(~r/\x1b\[35m(.+?)\x1b\[0m/, "<span class='text-purple-500'>\\1</span>")
    |> String.replace(~r/\x1b\[36m(.+?)\x1b\[0m/, "<span class='text-cyan-500'>\\1</span>")
    |> String.replace(~r/\x1b\[1m(.+?)\x1b\[0m/, "<span class='font-bold'>\\1</span>")
    |> String.replace(~r/\x1b\[3m(.+?)\x1b\[0m/, "<span class='italic'>\\1</span>")
    |> String.replace(~r/\x1b\[4m(.+?)\x1b\[0m/, "<span class='underline'>\\1</span>")
    |> Phoenix.HTML.raw()
  end

  defp validate_env_vars(env_vars) do
    required_fields = ["REPO_URL", "GIT_TOKEN", "DOWNLOAD_SERVER_URL", "TS_AUTHKEY"]

    Enum.reduce(required_fields, %{}, fn field, errors ->
      if String.trim(env_vars[field] || "") == "" do
        Map.put(errors, field, "This field is required")
      else
        errors
      end
    end)
  end

  defp server_running?(status) do
    String.contains?(String.downcase(status || ""), "running")
  end

  # Load environment configuration from file
  defp load_env_config do
    case File.read(@config_file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, config} -> {:ok, config}
          {:error, _} -> {:error, "Invalid JSON in configuration file"}
        end

      {:error, :enoent} ->
        {:error, "Configuration file not found"}

      {:error, _reason} ->
        {:error, "Error reading configuration file"}
    end
  end

  # Save environment configuration to file
  defp save_env_config(env_vars) do
    case Jason.encode(env_vars, pretty: true) do
      {:ok, json} ->
        # Ensure directory exists
        File.mkdir_p(Path.dirname(@config_file_path))
        # Write file
        File.write(@config_file_path, json)

      {:error, reason} ->
        Logger.error("Failed to encode environment variables: #{inspect(reason)}")
        {:error, "Failed to encode environment variables"}
    end
  end

  defp is_transitional_state?(status) do
    status = status || ""

    not (String.contains?(String.downcase(status), "stopped") ||
           String.contains?(status, "running (accessible at"))
  end
end
