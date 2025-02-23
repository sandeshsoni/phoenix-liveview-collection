defmodule LiveViewCollection.Collection do
  use Agent
  require Logger
  alias LiveViewCollection.Twitter
  alias LiveViewCollection.Github

  @default_query ""
  @default_page 1
  @default_page_size 10

  def start_link(_) do
    Agent.start_link(fn -> load_from_file() end, name: __MODULE__)
  end

  def all, do: Agent.get(__MODULE__, fn collection -> collection end)

  def filter(query \\ @default_query) do
    Agent.get(__MODULE__, &do_filter(&1, query))
  end

  def resolve(query \\ @default_query, page \\ @default_page, page_size \\ @default_page_size) do
    Agent.get(__MODULE__, fn collection ->
      collection
      |> do_filter(query)
      |> do_paginate(page, page_size)
    end)
  end

  defp do_filter(collection, query) when is_nil(query) or query == "", do: collection

  defp do_filter(collection, query) do
    {:ok, regex} = Regex.compile(query, "i")

    Enum.filter(collection, fn %{"search" => search} ->
      String.match?(search, regex)
    end)
  end

  defp do_paginate(collection, page, page_size)
       when is_nil(page) or page <= 0 or is_nil(page_size) or page_size <= 0 do
    do_paginate(collection, @default_page, @default_page_size)
  end

  defp do_paginate(collection, page, page_size) do
    Enum.slice(collection, (page - 1) * page_size, page_size)
  end

  defp load_from_file do
    {:ok, collection} =
      File.cwd!()
      |> Path.join("collection.yml")
      |> YamlElixir.read_from_file()

    collection
    |> resolve_tweets()
    |> resolve_repos()
    |> resolve_search_field()
  end

  defp resolve_tweets(collection) do
    unavailable_tweet = fn item ->
      Map.merge(item, %{
        "tweet_id" => nil,
        "tweet_html" => nil
      })
    end

    resolve_item = fn
      %{"tweet_url" => tweet_url} = item when is_nil(tweet_url) ->
        unavailable_tweet.(item)

      %{"tweet_url" => tweet_url} = item ->
        case Twitter.tweet(tweet_url) do
          {:ok, tweet} ->
            tweet = %{
              "tweet_id" => Twitter.id(tweet_url),
              "tweet_html" => tweet["html"]
            }

            Map.merge(item, tweet)

          {:error, _} ->
            :error
        end
    end

    collection
    |> Enum.map(&Task.async(fn -> resolve_item.(&1) end))
    |> Enum.map(&Task.await/1)
    |> Enum.reject(&(&1 == :error))
  end

  defp resolve_repos(collection) do
    collection
    |> Enum.map(fn
      %{"github_url" => github_url} = item when is_nil(github_url) ->
        Map.put(item, "github_repo", nil)

      %{"github_url" => github_url} = item ->
        Map.put(item, "github_repo", Github.repo(github_url))
    end)
  end

  defp resolve_search_field(collection) do
    collection
    |> Enum.map(fn
      %{"name" => name, "tweet_html" => tw_html} = item when is_binary(tw_html) ->
        Map.put(item, "search", name <> " " <> tw_html)

      %{"name" => name} = item ->
        Map.put(item, "search", name)
    end)
  end
end
