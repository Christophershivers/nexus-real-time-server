defmodule NexusRealtimeServer.SQLGuard do
  @moduledoc false

  def validate_selectish_single_statement!(sql) when is_binary(sql) do
    s = String.trim(sql)

    if s == "" do
      raise ArgumentError, "empty sql not allowed"
    end

    if String.contains?(s, ";") do
      raise ArgumentError, "multi-statement SQL not allowed"
    end

    if String.contains?(s, "--") do
      raise ArgumentError, "comments not allowed"
    end

    if String.contains?(s, "/*") do
      raise ArgumentError, "comments not allowed"
    end

    unless Regex.match?(~r/^\s*(select|with)\b/i, s) do
      raise ArgumentError, "only SELECT queries are allowed"
    end

    :ok
  end

  def validate_in_postgres_readonly!(repo, sql, timeout \\ 5_000) do
    case repo.transaction(fn ->
           repo.query!("SET LOCAL TRANSACTION READ ONLY", [], timeout: timeout)
           repo.query!("SET LOCAL statement_timeout = '#{timeout}'", [], timeout: timeout)
           repo.query!("EXPLAIN (FORMAT JSON) " <> sql, [], timeout: timeout)
           :ok
         end) do
      {:ok, :ok} ->
        :ok

      {:error, err} ->
        raise ArgumentError, "SQL rejected by Postgres: #{inspect(err)}"
    end
  end
end
