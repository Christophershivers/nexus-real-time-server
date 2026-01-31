defmodule NexusRealtimeServerWeb.PageController do
  use NexusRealtimeServerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
