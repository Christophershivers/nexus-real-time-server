defmodule NexusRealtimeServerWeb.RealtimeController do
  use NexusRealtimeServerWeb, :controller

  alias NexusRealtimeServer.Auth.VerifyToken, as: Token

  def realtime(conn, _params) do
    queryParams = conn.body_params
    NexusRealtimeServerWeb.Endpoint.broadcast(queryParams["topic"], queryParams["event"], %{body: queryParams["body"]})
    json(conn, conn.body_params)
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
