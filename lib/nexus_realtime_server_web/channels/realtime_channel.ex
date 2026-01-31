defmodule NexusRealtimeServerWeb.RealtimeChannel do
  use Phoenix.Channel

  alias NexusRealtimeServer.RegisterUser

  def join(_topic, payload, socket) do
    userid = payload["userid"]
    {:ok, assign(socket, :userid, userid)}
  end

  def terminate(_reason, socket) do
    user_id = socket.assigns.userid

    # 1. Use the index to find all records where userid matches
    # In Mnesia, the position is 1-based (Table Name = 1, UUID = 2, Topic = 3, UserID = 4)
    case :mnesia.dirty_index_read(:realtime_query, user_id, 4) do
      [] ->
        IO.puts("No session found for user #{user_id}")

      records ->
        # 2. Loop through and delete by the Primary Key (the UUID at index 1)
        Enum.each(records, fn record ->
          uuid = elem(record, 1)
          :mnesia.dirty_delete(:realtime_query, uuid)
        end)

        #IO.puts("User #{user_id} disconnected. Removed #{length(records)} sessions.")
    end

    :ok
  end

 def handle_in("subscribe", payload, socket) do
    # register_user MUST return: %{route_topics: [...], rows: [...]}
    %{route_topics: route_topics, rows: rows} = RegisterUser.register_user(payload)

    # IMPORTANT:
    # Don't broadcast snapshot to route topics here (race: client hasn't joined yet).
    # Instead, return rows in the reply so the client gets the snapshot reliably.
    {:reply, {:ok, %{received: true, route_topics: route_topics, rows: rows}}, socket}
  end

   def handle_in("WAL", payload, socket) do
    # register_user MUST return: %{route_topics: [...], rows: [...]}
    %{route_topics: route_topics, rows: rows} = RegisterUser.register_user(payload)

    # IMPORTANT:
    # Don't broadcast snapshot to route topics here (race: client hasn't joined yet).
    # Instead, return rows in the reply so the client gets the snapshot reliably.
    {:reply, {:ok, %{received: true, route_topics: route_topics, rows: rows}}, socket}
  end

  @spec handle_in(binary(), map(), Phoenix.Socket.t()) :: {:noreply, Phoenix.Socket.t()}
  def handle_in(event, %{"body" => body}, socket) do
    broadcast!(socket, event, %{body: body})
    {:noreply, socket}
  end
end
