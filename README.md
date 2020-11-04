# ExMachina

[![Circle CI](https://circleci.com/gh/thoughtbot/ex_machina.svg?style=svg&circle-token=fea4685d4951936734e764796c4b37c3686cdab3)](https://circleci.com/gh/thoughtbot/ex_machina)

**ExMachina is part of the [thoughtbot Elixir family][elixir-phoenix] of projects.**

ExMachina makes it easy to create test data and associations. It works great
with Ecto, but is configurable to work with any persistence library.

> **This README follows master, which may not be the currently published version**. Here are the
[docs for the latest published version of ExMachina](https://hexdocs.pm/ex_machina/readme.html).

## Installation

#### To install in all environments (useful for generating seed data in dev/prod):

In `mix.exs`, add the ExMachina dependency:

```elixir
def deps do
  # Get the latest from hex.pm. Works with Ecto 3.0
  [
    {:ex_machina, "~> 2.4"},
  ]
end
```

And start the ExMachina application. For most projects (such as
Phoenix apps) this will mean adding `:ex_machina` to the list of applications in
`mix.exs`. You can skip this step if you are using Elixir 1.4 or later.

```elixir
def application do
  [mod: {MyApp, []},
   applications: [:ex_machina, :other_apps...]]
end
```

#### Install in just the test environment with Phoenix:

In `mix.exs`, add the ExMachina dependency:

```elixir
def deps do
  [
    {:ex_machina, "~> 2.4", only: :test},
  ]
end
```

Add your factory module inside `test/support` so that it is only compiled in the
test environment.

Next, be sure to start the application in your `test/test_helper.exs` before
ExUnit.start:

```elixir
{:ok, _} = Application.ensure_all_started(:ex_machina)
```

#### Install in just the test environment for non-Phoenix projects:

You will follow the same instructions as above, but you will also need to add
`test/support` to your compilation paths (elixirc_paths) if you have not done
so already.

In `mix.exs`, add test/support to your elixirc_paths for just the test env.

```elixir
def project do
  [app: ...,
   # Add this if it's not already in your project definition.
   elixirc_paths: elixirc_paths(Mix.env)]
end

# This makes sure your factory and any other modules in test/support are compiled
# when in the test environment.
defp elixirc_paths(:test), do: ["lib", "web", "test/support"]
defp elixirc_paths(_), do: ["lib", "web"]
```

## Overview

[Check out the docs](http://hexdocs.pm/ex_machina/ExMachina.html) for more details.

Define factories:

```elixir
defmodule MyApp.Factory do
  # with Ecto
  use ExMachina.Ecto, repo: MyApp.Repo

  # without Ecto
  use ExMachina

  def user_factory do
    %MyApp.User{
      name: "Jane Smith",
      email: sequence(:email, &"email-#{&1}@example.com"),
      role: sequence(:role, ["admin", "user", "other"]),
    }
  end

  def article_factory do
    title = sequence(:title, &"Use ExMachina! (Part #{&1})")
    # derived attribute
    slug = MyApp.Article.title_to_slug(title)
    %MyApp.Article{
      title: title,
      slug: slug,
      # associations are inserted when you call `insert`
      author: build(:user),
    }
  end

  # derived factory
  def featured_article_factory do
    struct!(
      article_factory(),
      %{
        featured: true,
      }
    )
  end

  def comment_factory do
    %MyApp.Comment{
      text: "It's great!",
      article: build(:article),
    }
  end
end
```

Using factories ([check out the docs](http://hexdocs.pm/ex_machina/ExMachina.html) for more details):

```elixir
# `attrs` are automatically merged in for all build/insert functions.

# `build*` returns an unsaved comment.
# Associated records defined on the factory are built.
attrs = %{body: "A comment!"} # attrs is optional. Also accepts a keyword list.
build(:comment, attrs)
build_pair(:comment, attrs)
build_list(3, :comment, attrs)

# `insert*` returns an inserted comment. Only works with ExMachina.Ecto
# Associated records defined on the factory are inserted as well.
insert(:comment, attrs)
insert_pair(:comment, attrs)
insert_list(3, :comment, attrs)

# `params_for` returns a plain map without any Ecto specific attributes.
# This is only available when using `ExMachina.Ecto`.
params_for(:comment, attrs)

# `params_with_assocs` is the same as `params_for` but inserts all belongs_to
# associations and sets the foreign keys.
# This is only available when using `ExMachina.Ecto`.
params_with_assocs(:comment, attrs)

# Use `string_params_for` to generate maps with string keys. This can be useful
# for Phoenix controller tests.
string_params_for(:comment, attrs)
string_params_with_assocs(:comment, attrs)
```

## Full control of factory

By default, ExMachina will merge the attributes you pass into build/insert into
your factory. But if you want full control of your attributes, you can define
your factory as accepting one argument, the attributes being passed into your
factory.

```elixir
def custom_article_factory(attrs) do
  title = Map.get(attrs, :title, "default title")

  article = %Article{
    author: "John Doe",
    title: title
  }

  # merge attributes at the end to emulate ExMachina default behavior
  merge_attributes(article, attrs)
end
```

**NOTE** that in this case ExMachina will _not_ merge the attributes into your
factory, and you will have to do this on your own if desired.

### Non-map factories

Because you have full control of the factory when defining it with one argument,
you can build factories that are neither maps nor structs.

```elixir
# factory definition
def room_number_factory(attrs) do
  %{floor: floor_number} = attrs
  sequence(:room_number, &"#{floor_number}0#{&1}")
end

# example usage
build(:room_number, floor: 5)
# => "500"

build(:room_number, floor: 5)
# => "501"
```

**NOTE** that you cannot use non-map factories with Ecto. So you cannot
`insert(:room_number)`.

## Usage in a test

```elixir
# Example of use in Phoenix with a factory that uses ExMachina.Ecto
defmodule MyApp.MyModuleTest do
  use MyApp.ConnCase
  # If using Phoenix, import this inside the using block in MyApp.ConnCase
  import MyApp.Factory

  test "shows comments for an article" do
    conn = conn()
    article = insert(:article)
    comment = insert(:comment, article: article)

    conn = get conn, article_path(conn, :show, article.id)

    assert html_response(conn, 200) =~ article.title
    assert html_response(conn, 200) =~ comment.body
  end
end
```

## Where to put your factories

If you are using ExMachina in all environments:

> Start by creating one factory module (such as `MyApp.Factory`) in
`lib/my_app/factory.ex` and putting all factory definitions in that module.

If you are using ExMachina in only the test environment:

> Start by creating one factory module (such as `MyApp.Factory`) in
`test/support/factory.ex` and putting all factory definitions in that module.

Later on you can easily create different factories by creating a new module in
the same directory. This can be helpful if you need to create factories that are
used for different repos, your factory module is getting too big, or if you have
different ways of saving the record for different types of factories.

### Splitting factories into separate files

This example shows how to set up factories for the testing environment. For setting them in all environments, please see the _To install in all environments_ section

> Start by creating main factory module in `test/support/factory.ex` and name it `MyApp.Factory`. The purpose of the main factory is to allow you to include only a single module in all tests.

```elixir
# test/support/factory.ex
defmodule MyApp.Factory do
  use ExMachina.Ecto, repo: MyApp.Repo
  use MyApp.ArticleFactory
end
```

The main factory includes `MyApp.ArticleFactory`, so let's create it next. It might be useful to create a separate directory for factories, like `test/factories`. Here is how to create a factory:

```elixir
# test/factories/article_factory.ex
defmodule MyApp.ArticleFactory do
  defmacro __using__(_opts) do
    quote do
      def article_factory do
        %MyApp.Article{
          title: "My awesome article!",
          body: "Still working on it!"
        }
      end
    end
  end
end
```

This way you can split your giant factory file into many small files. But what about name conflicts? Use pattern matching to avoid them!

```elixir
# test/factories/post_factory.ex
defmodule MyApp.PostFactory do
  defmacro __using__(_opts) do
    quote do
      def post_factory do
        %MyApp.Post{
          body: "Example body"
        }
      end

      def with_comments(%MyApp.Post{} = post) do
        insert_pair(:comment, post: post)
        post
      end
    end
  end
end

# test/factories/video_factory.ex
defmodule MyApp.VideoFactory do
  defmacro __using__(_opts) do
    quote do
      def video_factory do
        %MyApp.Video{
          url: "example_url"
        }
      end

      def with_comments(%MyApp.Video{} = video) do
        insert_pair(:comment, video: video)
        video
      end
    end
  end
end
```

## Ecto Associations

ExMachina will automatically save any associations when you call any of the
`insert` functions. This includes `belongs_to` and anything that is
inserted by Ecto when using `Repo.insert!`, such as `has_many`, `has_one`,
and embeds. Since we automatically save these records for you, we advise that
factory definitions only use `build/2` when declaring associations, like so:

```elixir
def article_factory do
  %Article{
    title: "Use ExMachina!",
    # associations are inserted when you call `insert`
    comments: [build(:comment)],
    author: build(:user),
  }
end
```

Using `insert/2` in factory definitions may lead to performance issues and bugs,
as records will be saved unnecessarily.

## Flexible Factories with Pipes

```elixir
def make_admin(user) do
  %{user | admin: true}
end

def with_article(user) do
  insert(:article, user: user)
  user
end

build(:user) |> make_admin |> insert |> with_article
```

## Using with Phoenix

If you want to keep the factories somewhere other than `test/support`,
change this line in `mix.exs`:

```elixir
# Add the folder to the end of the list. In this case we're adding `test/factories`.
defp elixirc_paths(:test), do: ["lib", "web", "test/support", "test/factories"]
```

## Multi-tenant support

If you are depending on query prefixes to switch between tenant schemas you can 
pass `repo_options` to your factory which can be used to set the `:prefix` on your insert queries.
This allows you to create a factory per tenant.

```elixir
defmodule MyApp.TenantFactory
  use ExMachina.Ecto, repo: MyApp.Repo, repo_options: [prefix: "test_tenant"]

  def user_factory do
    ...
  end

  ...
end
```

## Custom Strategies

You can use ExMachina without Ecto, by using just the `build` functions, or you
can define one or more custom strategies to use in your factory. You can also
use custom strategies with Ecto. Here's an example of a strategy for json
encoding your factories. See the docs on [ExMachina.Strategy] for more info.

[ExMachina.Strategy]: https://hexdocs.pm/ex_machina/ExMachina.Strategy.html

```elixir
defmodule MyApp.JsonEncodeStrategy do
  use ExMachina.Strategy, function_name: :json_encode

  def handle_json_encode(record, _opts) do
    Poison.encode!(record)
  end
end

defmodule MyApp.Factory do
  use ExMachina
  # Using this will add json_encode/2, json_encode_pair/2 and json_encode_list/3
  use MyApp.JsonEncodeStrategy

  def user_factory do
    %User{name: "John"}
  end
end

# Will build and then return a JSON encoded version of the user.
MyApp.Factory.json_encode(:user)
```

## Contributing

Before opening a pull request, please open an issue first.

    $ git clone https://github.com/thoughtbot/ex_machina.git
    $ cd ex_machina
    $ mix deps.get
    $ mix test

Once you've made your additions and `mix test` passes, go ahead and open a PR!

## License

ExMachina is Copyright © 2015 thoughtbot. It is free software, and may be
redistributed under the terms specified in the [LICENSE](/LICENSE) file.

## About thoughtbot

![thoughtbot](https://thoughtbot.com/logo.png)

ExMachina is maintained and funded by thoughtbot, inc.
The names and logos for thoughtbot are trademarks of thoughtbot, inc.

We love open source software, Elixir, and Phoenix. See [our other Elixir
projects][elixir-phoenix], or [hire our Elixir Phoenix development team][hire]
to design, develop, and grow your product.

[elixir-phoenix]: https://thoughtbot.com/services/elixir-phoenix?utm_source=github
[hire]: https://thoughtbot.com?utm_source=github

## Inspiration

* [Fixtures for Ecto](http://blog.danielberkompas.com/elixir/2015/07/16/fixtures-for-ecto.html)
* [Factory Bot](https://github.com/thoughtbot/factory_bot)
