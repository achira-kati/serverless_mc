defmodule MinecraftWebWeb.Router do
  use MinecraftWebWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {MinecraftWebWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", MinecraftWebWeb do
    pipe_through(:browser)

    live("/", MinecraftLive)
    live "/server-config", ServerConfigLive, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", MinecraftWebWeb do
  #   pipe_through :api
  # end
end
