defmodule NexusRealtimeServerWeb.RealtimeController do
  use NexusRealtimeServerWeb, :controller

  alias NexusRealtimeServer.Auth.VerifyToken, as: Token

  def realtime(conn, _params) do
    with :ok <- ensure_authed(conn) do
      query_params = conn.body_params

      NexusRealtimeServerWeb.Endpoint.broadcast(
        query_params["topic"],
        query_params["event"],
        %{body: query_params["body"]}
      )

      json(conn, %{ok: true})
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Unauthorized"})
    end
  end


  defp ensure_authed(conn) do
    if System.get_env("AUTH_ENABLED") == "true" do
      conn
      |> get_req_header("authorization")
      |> List.first()
      |> case do
        "Bearer " <> token ->
          case Token.verify(token) do
            {:ok, _claims} -> :ok
            {:error, _} -> {:error, :unauthorized}
          end

        _ ->
          {:error, :unauthorized}
      end
    else
      :ok
    end
  end


  def auth(conn, _params) do
    if System.get_env("AUTH_ENABLED") == "true" do
      auth_header =
        conn
        |> get_req_header("authorization")
        |> List.first()

      token =
        case auth_header do
          "Bearer " <> t -> t
          _ -> nil
        end

      case token do
        nil ->
          conn
          |> put_status(:unauthorized)
          |> json(%{error: "Unauthorized"})

        token ->
          case Token.verify(token) do
            {:ok, incoming_claims} ->
              # mint a new token (with whatever claims you want)
              new_token = Token.sign(%{"device" => "nexus", "sub" => incoming_claims["sub"]})

              # decode claims for the new token (optional, but you said you want claims)
              {:ok, new_claims} = Token.verify(new_token)

              json(conn, %{ok: true, token: new_token, claims: new_claims})

            {:error, _} ->
              conn
              |> put_status(:unauthorized)
              |> json(%{error: "Unauthorized"})
          end
      end
    else
      # If auth is not enabled, just return ok
      json(conn, %{ok: true})
    end
  end

end
