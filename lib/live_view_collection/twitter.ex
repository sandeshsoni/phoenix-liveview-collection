defmodule LiveViewCollection.Twitter do
  require Logger

  def tweet(tweet_url) do
    %HTTPotion.Response{body: body, status_code: status_code} =
      HTTPotion.get(
        "https://publish.twitter.com/oembed?url=#{tweet_url}&omit_script=true&hide_thread=true"
      )

    Logger.info("#{tweet_url} => #{status_code}")

    body
    |> Jason.decode()
    |> case do
      {:ok, tweet} ->
        {:ok, tweet}

      {:error, _body} ->
        Logger.debug("^ error fetching this tweet ^")
        {:error, :error_fetching_tweet}
    end
  end

  def id(tweet_url) do
    tweet_url
    |> String.split("/")
    |> List.last()
  end
end
