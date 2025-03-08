defmodule MinecraftWeb.RedisService do
  use GenServer
  require Logger

  @control_channel "minecraft:control"
  @status_channel "minecraft:status"
  # This is manually fetch log
  @logs_channel "minecraft:logs"
  # This is realtime log
  @xterm_channel "minecraft:xterm"
  @error_channel "minecraft:error"
  @details_channel "minecraft:details"
  @external_channel "minecraft:external_server"

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    # Connect to Redis for publishing commands
    {:ok, conn} = Redix.start_link(host: "redis", port: 6379)

    # Start a separate connection for pubsub
    {:ok, pubsub} = Redix.PubSub.start_link(host: "redis", port: 6379)

    # Subscribe to all channels
    {:ok, _ref1} = Redix.PubSub.subscribe(pubsub, @status_channel, self())
    {:ok, _ref1} = Redix.PubSub.subscribe(pubsub, @error_channel, self())
    {:ok, _ref2} = Redix.PubSub.subscribe(pubsub, @logs_channel, self())
    {:ok, _ref3} = Redix.PubSub.subscribe(pubsub, @xterm_channel, self())
    {:ok, _ref4} = Redix.PubSub.subscribe(pubsub, @details_channel, self())
    {:ok, _ref5} = Redix.PubSub.subscribe(pubsub, @external_channel, self())

    {:ok, %{conn: conn, pubsub: pubsub}}
  end

  # Simple commands
  def send_command(command)
      when command in [
             "start",
             "stop",
             "restart",
             "backup",
             "status",
             "logs",
             "tailscale_ip",
             "check_running_server",
             "set_environment"
           ] do
    GenServer.cast(__MODULE__, {:publish, @control_channel, command})
  end

  # Complex commands with arguments (JSON)
  def send_command_with_args(command, args) do
    message = Jason.encode!(%{command: command, args: args})
    GenServer.cast(__MODULE__, {:publish, @control_channel, message})
  end

  # Helper for Minecraft console commands
  def send_minecraft_command(text) when is_binary(text) and text != "" do
    send_command_with_args("minecraft_command", %{text: text})
  end

  # Get specific number of log lines
  def fetch_logs(lines \\ 100) do
    send_command_with_args("logs", %{lines: lines})
  end

  # Set environment variables
  def set_environment_variables(variables) when is_map(variables) do
    send_command_with_args("set_environment", %{variables: variables})
  end

  # Publish to Redis
  def handle_cast({:publish, channel, message}, %{conn: conn} = state) do
    case Redix.command(conn, ["PUBLISH", channel, message]) do
      {:ok, _} -> Logger.info("Published to #{channel}: #{inspect(message)}")
      {:error, reason} -> Logger.error("Failed to publish: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  # Handle messages from Redis channels
  def handle_info(
        {:redix_pubsub, _pid, _ref, :message, %{channel: @status_channel, payload: payload}},
        state
      ) do
    Phoenix.PubSub.broadcast(MinecraftWeb.PubSub, "minecraft:status", {:status, payload})
    {:noreply, state}
  end

  def handle_info(
        {:redix_pubsub, _pid, _ref, :message, %{channel: @error_channel, payload: payload}},
        state
      ) do
    Phoenix.PubSub.broadcast(MinecraftWeb.PubSub, "minecraft:error", {:error, payload})
    {:noreply, state}
  end

  def handle_info(
        {:redix_pubsub, _pid, _ref, :message, %{channel: @logs_channel, payload: payload}},
        state
      ) do
    Phoenix.PubSub.broadcast(MinecraftWeb.PubSub, "minecraft:logs", {:log, payload})
    {:noreply, state}
  end

  def handle_info(
        {:redix_pubsub, _pid, _ref, :message, %{channel: @xterm_channel, payload: payload}},
        state
      ) do
    Phoenix.PubSub.broadcast(MinecraftWeb.PubSub, "minecraft:xterm", {:xterm_log, payload})
    {:noreply, state}
  end

  def handle_info(
        {:redix_pubsub, _pid, _ref, :message, %{channel: @details_channel, payload: payload}},
        state
      ) do
    Phoenix.PubSub.broadcast(MinecraftWeb.PubSub, "minecraft:details", {:details, payload})
    {:noreply, state}
  end

  def handle_info(
        {:redix_pubsub, _pid, _ref, :message, %{channel: @external_channel, payload: payload}},
        state
      ) do
    Phoenix.PubSub.broadcast(
      MinecraftWeb.PubSub,
      "minecraft:external_server",
      {:external_server, payload}
    )

    {:noreply, state}
  end

  # Handle subscription confirmations
  def handle_info({:redix_pubsub, _pid, _ref, :subscribed, %{channel: channel}}, state) do
    Logger.info("Subscribed to #{channel}")
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end
end
