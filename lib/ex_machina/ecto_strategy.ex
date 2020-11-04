defmodule ExMachina.EctoStrategy do
  @moduledoc false

  use ExMachina.Strategy, function_name: :insert

  def handle_insert(%{__meta__: %{state: :loaded}} = record, _) do
    raise "You called `insert` on a record that has already been inserted.
     Make sure that you have not accidentally called insert twice.

     The record you attempted to insert:

     #{inspect(record, limit: :infinity)}"
  end

  def handle_insert(_, %{repo: nil}) do
    raise """
    insert/1 is not available unless you provide the :repo option. Example:

    use ExMachina.Ecto, repo: MyApp.Repo
    """
  end

  def handle_insert(%{__meta__: %{__struct__: Ecto.Schema.Metadata}} = record, %{repo: repo} = opts) do
    record
    |> cast
    |> repo.insert!(opts[:repo_options] || [])
  end

  def handle_insert(record, %{repo: _repo}) do
    raise ArgumentError, "#{inspect(record)} is not an Ecto model. Use `build` instead"
  end

  def handle_insert(_record, _opts) do
    raise "expected :repo to be given to ExMachina.EctoStrategy"
  end

  defp cast(record) do
    record
    |> cast_all_fields
    |> cast_all_embeds
    |> cast_all_assocs
  end

  defp cast_all_fields(%{__struct__: schema} = struct) do
    schema
    |> schema_fields()
    |> Enum.reduce(struct, fn field_key, struct ->
      casted_value = cast_field(field_key, struct)

      Map.put(struct, field_key, casted_value)
    end)
  end

  defp cast_field(field_key, %{__struct__: schema} = struct) do
    field_type = schema.__schema__(:type, field_key)
    value = Map.get(struct, field_key)

    cast_value(field_type, value, struct)
  end

  defp cast_value(field_type, value, struct) do
    case Ecto.Type.cast(field_type, value) do
      {:ok, value} ->
        value

      _ ->
        raise "Failed to cast `#{inspect(value)}` of type #{inspect(field_type)} in #{
                inspect(struct)
              }."
    end
  end

  defp cast_all_embeds(%{__struct__: schema} = struct) do
    schema
    |> schema_embeds()
    |> Enum.reduce(struct, fn embed_key, struct ->
      casted_value = struct |> Map.get(embed_key) |> cast_embed(embed_key, struct)

      Map.put(struct, embed_key, casted_value)
    end)
  end

  defp cast_embed(embeds_many, embed_key, struct) when is_list(embeds_many) do
    Enum.map(embeds_many, &cast_embed(&1, embed_key, struct))
  end

  defp cast_embed(embed, embed_key, %{__struct__: schema}) do
    if embed do
      embedding_reflection = schema.__schema__(:embed, embed_key)
      embed_type = embedding_reflection.related
      embed_type |> struct() |> Map.merge(embed) |> cast()
    end
  end

  defp cast_all_assocs(%{__struct__: schema} = struct) do
    assoc_keys = schema_associations(schema)

    Enum.reduce(assoc_keys, struct, fn assoc_key, struct ->
      casted_value = struct |> Map.get(assoc_key) |> cast_assoc(assoc_key, struct)

      Map.put(struct, assoc_key, casted_value)
    end)
  end

  defp cast_assoc(has_many_assoc, assoc_key, struct) when is_list(has_many_assoc) do
    Enum.map(has_many_assoc, &cast_assoc(&1, assoc_key, struct))
  end

  defp cast_assoc(assoc, assoc_key, %{__struct__: schema}) do
    case assoc do
      %{__meta__: %{__struct__: Ecto.Schema.Metadata, state: :built}} ->
        cast(assoc)

      %{__struct__: Ecto.Association.NotLoaded} ->
        assoc

      %{__struct__: _} ->
        cast(assoc)

      %{} ->
        assoc_reflection = schema.__schema__(:association, assoc_key)
        assoc_type = assoc_reflection.related
        assoc_type |> struct() |> Map.merge(assoc) |> cast()

      nil ->
        nil
    end
  end

  defp schema_fields(schema) do
    schema_non_virtual_fields(schema) -- schema_embeds(schema)
  end

  defp schema_non_virtual_fields(schema) do
    schema.__schema__(:fields)
  end

  defp schema_embeds(schema) do
    schema.__schema__(:embeds)
  end

  defp schema_associations(schema) do
    schema.__schema__(:associations)
  end
end
