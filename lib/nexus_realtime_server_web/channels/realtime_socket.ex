defmodule NexusRealtimeServerWeb.RealtimeSocket do
  use Phoenix.Socket
  alias NexusRealtimeServer.Auth.VerifyToken, as: Token

  channel "*", NexusRealtimeServerWeb.RealtimeChannel
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    # Returns true ONLY if the env var is exactly "true"
    # Returns false if the var is missing (nil) or anything else
    if System.get_env("AUTH_ENABLED") == "true" do
      now = System.system_time(:second)

      case Token.verify(token) do
        {:ok, %{"device" => "nexus", "exp" => exp} = claims}
        when is_integer(exp) and exp > now ->
          {:ok, assign(socket, :claims, claims)}

        _ ->
          :error
      end
    else
      # If not there or says false, just return ok
      {:ok, socket}
    end
  end

  # Fallback for when there is no token map provided
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  def id(_socket), do: nil
end
