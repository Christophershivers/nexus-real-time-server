defmodule NexusRealtimeServer.Auth.VerifyToken do
  @moduledoc """
  Module for verifying authentication tokens.
  """
  @alg "HS256"

  def verify(token) when is_binary(token) do
    secret = System.fetch_env!("AUTH_SECRET")

    case JOSE.JWT.verify_strict(
           JOSE.JWK.from_oct(secret),
           [@alg],
           token
         ) do
      {true, %JOSE.JWT{fields: claims}, _jws} ->
        {:ok, claims}

      {false, _jwt, _jws} ->
        {:error, :invalid_token}
    end
  rescue
    _ -> {:error, :invalid_token}
  end


  def sign(claims \\ %{}) do
    secret = System.fetch_env!("AUTH_SECRET")

    jwk = JOSE.JWK.from_oct(secret)

    now = System.system_time(:second)

    payload =
      claims
      |> Map.put_new("iss", "my_app")
      |> Map.put_new("iat", now)
      |> Map.put_new("exp", now + 60 * 60) # 1 hour
      |> Map.put_new("device", "nexus") # 1 hour

    {_, token} =
      JOSE.JWT.sign(jwk, %{"alg" => @alg}, payload)
      |> JOSE.JWS.compact()

    token
  end

end
