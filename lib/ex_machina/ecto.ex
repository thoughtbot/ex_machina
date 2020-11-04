defmodule ExMachina.Ecto do
  @moduledoc """
  Module for building and inserting factories with Ecto

  This module works much like the regular `ExMachina` module, but adds a few
  nice things that make working with Ecto easier.

  * It uses `ExMachina.EctoStrategy`, which adds `insert/1`, `insert/2`,
    `insert_pair/2`, `insert_list/3`.
  * Adds a `params_for` function that is useful for working with changesets or
    sending params to API endpoints.

  More in-depth examples are in the [README](readme.html).
  """
  defmacro __using__(opts) do
    verify_ecto_dep()

    quote do
      use ExMachina
      use ExMachina.EctoStrategy,
        repo: unquote(Keyword.get(opts, :repo)),
        repo_options: unquote(Keyword.get(opts, :repo_options, []))

      def params_for(factory_name, attrs \\ %{}) do
        ExMachina.Ecto.params_for(__MODULE__, factory_name, attrs)
      end

      def string_params_for(factory_name, attrs \\ %{}) do
        ExMachina.Ecto.string_params_for(__MODULE__, factory_name, attrs)
      end

      def params_with_assocs(factory_name, attrs \\ %{}) do
        ExMachina.Ecto.params_with_assocs(__MODULE__, factory_name, attrs)
      end

      def string_params_with_assocs(factory_name, attrs \\ %{}) do
        ExMachina.Ecto.string_params_with_assocs(__MODULE__, factory_name, attrs)
      end
    end
  end

  defp verify_ecto_dep do
    unless Code.ensure_loaded?(Ecto) do
      raise "You tried to use ExMachina.Ecto, but the Ecto module is not loaded. " <>
              "Please add ecto to your dependencies."
    end
  end

  @doc """
  Builds a factory and inserts it into the database.

  The arguments are the same as `c:ExMachina.build/2`.
  """
  @callback insert(factory_name :: atom) :: any
  @callback insert(factory_name :: atom, attrs :: keyword | map) :: any

  @doc """
  Builds two factories and inserts them into the database.

  The arguments are the same as `c:ExMachina.build_pair/2`.
  """
  @callback insert_pair(factory_name :: atom) :: list
  @callback insert_pair(factory_name :: atom, attrs :: keyword | map) :: list

  @doc """
  Builds many factories and inserts them into the database.

  The arguments are the same as `c:ExMachina.build_list/3`.
  """
  @callback insert_list(number_of_records :: integer, factory_name :: atom) :: list
  @callback insert_list(
              number_of_records :: integer,
              factory_name :: atom,
              attrs :: keyword | map
            ) :: list

  @doc """
  Builds a factory and returns only its fields.

  This is only for use with Ecto models.

  Will return a map with the fields and virtual fields, but without the Ecto
  metadata, the primary key, or any `belongs_to` associations. This will
  recursively act on `has_one` associations and Ecto structs found in
  `has_many` associations.

  If you want `belongs_to` associations to be inserted, use
  `c:params_with_assocs/2`.

  If you want params with string keys use `c:string_params_for/2`.

  ## Example

      def user_factory do
        %MyApp.User{name: "John Doe", admin: false}
      end

      # Returns %{name: "John Doe", admin: true}
      params_for(:user, admin: true)

      # Returns %{name: "John Doe", admin: false}
      params_for(:user)
  """
  @callback params_for(factory_name :: atom) :: %{optional(atom) => any}
  @callback params_for(factory_name :: atom, attrs :: keyword | map) :: %{optional(atom) => any}

  @doc false
  def params_for(module, factory_name, attrs \\ %{}) do
    factory_name
    |> module.build(attrs)
    |> recursively_strip
  end

  @doc """
  Similar to `c:params_for/2` but converts atom keys to strings in returned map.

  The result of this function can be safely used in controller tests for Phoenix
  web applications.

  ## Example

      def user_factory do
        %MyApp.User{name: "John Doe", admin: false}
      end

      # Returns %{"name" => "John Doe", "admin" => true}
      string_params_for(:user, admin: true)
  """
  @callback string_params_for(factory_name :: atom) :: %{optional(String.t()) => any}
  @callback string_params_for(factory_name :: atom, attrs :: keyword | map) :: %{
              optional(String.t()) => any
            }

  @doc false
  def string_params_for(module, factory_name, attrs \\ %{}) do
    module
    |> params_for(factory_name, attrs)
    |> convert_atom_keys_to_strings
  end

  @doc """
  Similar to `c:params_for/2` but inserts all `belongs_to` associations and
  sets the foreign keys.

  If you want params with string keys use `c:string_params_with_assocs/2`.

  ## Example

      def article_factory do
        %MyApp.Article{title: "An Awesome Article", author: build(:author)}
      end

      # Inserts an author and returns %{title: "An Awesome Article", author_id: 12}
      params_with_assocs(:article)
  """
  @callback params_with_assocs(factory_name :: atom) :: %{optional(atom) => any}
  @callback params_with_assocs(factory_name :: atom, attrs :: keyword | map) :: %{
              optional(atom) => any
            }

  @doc false
  def params_with_assocs(module, factory_name, attrs \\ %{}) do
    factory_name
    |> module.build(attrs)
    |> insert_belongs_to_assocs(module)
    |> recursively_strip
  end

  @doc """
  Similar to `c:params_with_assocs/2` but converts atom keys to strings in
  returned map.

  The result of this function can be safely used in controller tests for Phoenix
  web applications.

  ## Example

      def article_factory do
        %MyApp.Article{title: "An Awesome Article", author: build(:author)}
      end

      # Inserts an author and returns %{"title" => "An Awesome Article", "author_id" => 12}
      string_params_with_assocs(:article)
  """
  @callback string_params_with_assocs(factory_name :: atom) :: %{optional(String.t()) => any}
  @callback string_params_with_assocs(factory_name :: atom, attrs :: keyword | map) :: %{
              optional(String.t()) => any
            }

  @doc false
  def string_params_with_assocs(module, factory_name, attrs \\ %{}) do
    module
    |> params_with_assocs(factory_name, attrs)
    |> convert_atom_keys_to_strings
  end

  defp recursively_strip(record = %{__struct__: _}) do
    record
    |> set_persisted_belongs_to_ids
    |> handle_assocs
    |> handle_embeds
    |> drop_ecto_fields
    |> drop_fields_with_nil_values
  end

  defp recursively_strip(record), do: record

  defp handle_assocs(record = %{__struct__: struct}) do
    Enum.reduce(struct.__schema__(:associations), record, fn association_name, record ->
      case struct.__schema__(:association, association_name) do
        %{__struct__: Ecto.Association.BelongsTo} ->
          Map.delete(record, association_name)

        _ ->
          record
          |> Map.get(association_name)
          |> handle_assoc(record, association_name)
      end
    end)
  end

  defp handle_assoc(original_assoc, record, association_name) do
    case original_assoc do
      %{__meta__: %{__struct__: Ecto.Schema.Metadata, state: :built}} ->
        assoc = recursively_strip(original_assoc)
        Map.put(record, association_name, assoc)

      nil ->
        Map.put(record, association_name, nil)

      list when is_list(list) ->
        has_many_assoc = Enum.map(original_assoc, &recursively_strip/1)
        Map.put(record, association_name, has_many_assoc)

      %{__struct__: Ecto.Association.NotLoaded} ->
        Map.delete(record, association_name)
    end
  end

  defp handle_embeds(record = %{__struct__: struct}) do
    Enum.reduce(struct.__schema__(:embeds), record, fn embed_name, record ->
      record
      |> Map.get(embed_name)
      |> handle_embed(record, embed_name)
    end)
  end

  defp handle_embed(original_embed, record, embed_name) do
    case original_embed do
      %{} ->
        embed = recursively_strip(original_embed)
        Map.put(record, embed_name, embed)

      list when is_list(list) ->
        embeds_many = Enum.map(original_embed, &recursively_strip/1)
        Map.put(record, embed_name, embeds_many)

      nil ->
        Map.delete(record, embed_name)
    end
  end

  defp set_persisted_belongs_to_ids(record = %{__struct__: struct}) do
    Enum.reduce(struct.__schema__(:associations), record, fn association_name, record ->
      association = struct.__schema__(:association, association_name)

      case association do
        %{__struct__: Ecto.Association.BelongsTo} ->
          case Map.get(record, association_name) do
            belongs_to = %{__meta__: %{__struct__: Ecto.Schema.Metadata, state: :loaded}} ->
              set_belongs_to_primary_key(record, belongs_to, association)

            _ ->
              record
          end

        _ ->
          record
      end
    end)
  end

  defp set_belongs_to_primary_key(record, belongs_to, association) do
    primary_key = Map.get(belongs_to, association.related_key)
    Map.put(record, association.owner_key, primary_key)
  end

  defp insert_belongs_to_assocs(record = %{__struct__: struct}, module) do
    Enum.reduce(struct.__schema__(:associations), record, fn association_name, record ->
      case struct.__schema__(:association, association_name) do
        association = %{__struct__: Ecto.Association.BelongsTo} ->
          insert_built_belongs_to_assoc(module, association, record)

        _ ->
          record
      end
    end)
  end

  defp insert_built_belongs_to_assoc(module, association, record) do
    case Map.get(record, association.field) do
      built_relation = %{__meta__: %{state: :built}} ->
        relation = module.insert(built_relation)
        set_belongs_to_primary_key(record, relation, association)

      _ ->
        Map.delete(record, association.owner_key)
    end
  end

  @doc false
  def drop_ecto_fields(record = %{__struct__: struct}) do
    record
    |> Map.from_struct()
    |> Map.delete(:__meta__)
    |> drop_autogenerated_ids(struct)
  end

  def drop_ecto_fields(embedded_record), do: embedded_record

  defp drop_autogenerated_ids(map, struct) do
    case struct.__schema__(:autogenerate_id) do
      {name, _source, _type} -> Map.delete(map, name)
      {name, _type} -> Map.delete(map, name)
      nil -> map
    end
  end

  defp drop_fields_with_nil_values(map) do
    map
    |> Enum.reject(fn {_, value} -> value == nil end)
    |> Enum.into(%{})
  end

  defp convert_atom_keys_to_strings(values) when is_list(values) do
    Enum.map(values, &convert_atom_keys_to_strings/1)
  end

  defp convert_atom_keys_to_strings(%{__struct__: _} = record) when is_map(record) do
    Map.from_struct(record) |> convert_atom_keys_to_strings()
  end

  defp convert_atom_keys_to_strings(record) when is_map(record) do
    Enum.reduce(record, Map.new(), fn {key, value}, acc ->
      Map.put(acc, to_string(key), convert_atom_keys_to_strings(value))
    end)
  end

  defp convert_atom_keys_to_strings(value), do: value
end
