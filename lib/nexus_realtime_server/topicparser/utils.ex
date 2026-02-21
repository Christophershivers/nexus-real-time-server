defmodule NexusRealtimeServer.Utils do
    def type_family(type) do
    case type do
      "smallint" -> :number
      "integer" -> :number
      "bigint" -> :number
      "real" -> :number
      "double precision" -> :number
      "numeric" -> :number
      "decimal" -> :number
      "double" -> :number
      "bigserial" -> :number
      "int32" -> :number
      "int64" -> :number

      "boolean" -> :boolean
      "date" -> :date
      "uuid" -> :uuid

      "text" -> :text
      "character varying" -> :text
      "varchar" -> :text

      _ -> :text
    end
  end

  def compare_uuid("eq", left, right), do: left == right
  def compare_uuid("!eq", left, right), do: left != right
  def compare_uuid(_, _left, _right), do: false

  def compare_text("eq", left, right), do: left == right
  def compare_text("!eq", left, right), do: left != right
  def compare_text("contains", left, right), do: String.contains?(left, right)
  def compare_text("starts_with", left, right), do: String.starts_with?(left, right)
  def compare_text("ends_with", left, right), do: String.ends_with?(left, right)
  def compare_text(_, _left, _right), do: false

  def cast(:number, v) when is_integer(v), do: {:ok, v}
  def cast(:number, v) when is_float(v), do: {:ok, v}

  def cast(:number, v) when is_binary(v) do
    case Integer.parse(v) do
      {i, ""} -> {:ok, i}
      _ ->
        case Float.parse(v) do
          {f, ""} -> {:ok, f}
          _ -> :error
        end
    end
  end

  def cast(:number, _), do: :error

  def cast(:boolean, v) when is_boolean(v), do: {:ok, v}

  def cast(:boolean, v) when is_binary(v) do
    case String.downcase(v) do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ -> :error
    end
  end

  def cast(:boolean, _), do: :error

  def cast(:date, %Date{} = d), do: {:ok, d}
  def cast(:date, v) when is_binary(v), do: Date.from_iso8601(v)
  def cast(:date, _), do: :error

  def cast(:uuid, v), do: {:ok, to_string(v)}
  def cast(:text, v), do: {:ok, to_string(v)}

  def compare("eq", l, r), do: l == r
  def compare("!eq", l, r), do: l != r
  def compare("gt", l, r), do: l > r
  def compare("lt", l, r), do: l < r
  def compare("gte", l, r), do: l >= r
  def compare("lte", l, r), do: l <= r
  def compare(_, _l, _r), do: false

  # MapSet variant
  def eval_value_or_set(family, op, left_raw, %MapSet{} = set) do
    cond do
      op in ["eq", "!eq"] ->
        with {:ok, left} <- cast(family, left_raw) do
          typed_set = cast_set(family, set)
          if op == "eq", do: MapSet.member?(typed_set, left), else: not MapSet.member?(typed_set, left)
        else
          _ -> false
        end

      true ->
        case MapSet.to_list(set) do
          [single_val] ->
            eval_value_or_set(family, op, left_raw, single_val)

          _ ->
            false
        end
    end
  end

  def eval_value_or_set(family, op, left_raw, right_raw) do
    with {:ok, left} <- cast(family, left_raw),
         {:ok, right} <- cast(family, right_raw) do
      compare_by_family(family, op, left, right)
    else
      _ -> false
    end
  end

  def cast_set(family, set) do
    Enum.reduce(set, MapSet.new(), fn v, acc ->
      case cast(family, v) do
        {:ok, typed} -> MapSet.put(acc, typed)
        _ -> acc
      end
    end)
  end

  def compare_by_family(:uuid, op, left, right),
    do: compare_uuid(op, to_string(left), to_string(right))

  def compare_by_family(:text, op, left, right),
    do: compare_text(op, to_string(left), to_string(right))

  def compare_by_family(_family, op, left, right),
    do: compare(op, left, right)
end
