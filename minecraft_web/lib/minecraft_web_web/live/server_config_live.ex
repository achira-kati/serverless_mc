defmodule MinecraftWebWeb.ServerConfigLive do
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
    # Try to load environment variables from file, use defaults if not found
    env_vars =
      case load_env_config() do
        {:ok, vars} -> vars
        {:error, _} -> @env_defaults
      end

    # Initial validation
    errors = validate_env_vars(env_vars)

    {:ok,
     assign(socket,
       environment_variables: env_vars,
       env_validation_errors: errors,
       page_title: "Server Configuration",
       show_git_token: false,
       show_ts_authkey: false
     )}
  end

  @impl true
  def handle_event("save_env_vars", %{"env_vars" => env_vars}, socket) do
    # Validate required fields
    errors = validate_env_vars(env_vars)
    config_valid = map_size(errors) == 0

    if config_valid do
      # Save configuration to file
      save_env_config(env_vars)

      # Restart server script to load new env
      RedisService.send_command("set_environment")

      # Redirect to the main dashboard
      {:noreply,
       socket
       |> put_flash(:info, "Configuration saved successfully")
       |> redirect(to: ~p"/")}
    else
      {:noreply,
       assign(socket,
         environment_variables: env_vars,
         env_validation_errors: errors
       )}
    end
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
end
