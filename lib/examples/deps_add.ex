defmodule Mix.Tasks.Deps.Add do
  use Mix.Task

  @user_agent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/88.0.4324.182 Safari/537.36'

  @impl Mix.Task
  def run([name, version | _] = _args) do
    add_dep(name, version)
  end
  def run([name | _] = _args) do
    :inets.start()
    :ssl.start()

    url = 'https://hex.pm/api/packages/' ++ String.to_charlist(name)

    with {:ok, response} <- :httpc.request(:get, {url, [{'User-Agent', @user_agent}]}, [], []) do
      {_, _, body} = response
      version =
        body
        |> List.to_string()
        |> Jason.decode!()
        |> Map.get("latest_stable_version")

      %{major: major, minor: minor} = Version.parse!(version)

      version = "#{major}.#{minor}"

      add_dep(name, version)
    end
  end

  defp add_dep(name, version) do
    source = File.read!("mix.exs")
    {quoted, comments} = Formatter.string_to_quoted_with_comments(source)

    quoted = Comments.merge_comments(quoted, comments)

    name = String.to_atom(name)

    quoted = Macro.postwalk(quoted, fn
      {:defp, meta, [{:deps, _, _} = fun, body]} ->
        [{{_, _, [:do]} = do_ast, block_ast}] = body
        {:__block__, meta1, [deps]} = block_ast

        deps =
          deps ++
            [
              {:__block__, [],
               [{{:__block__, [], [name]}, {:__block__, [delimiter: "\""], ["~> " <> version]}}]}
            ]

        {:defp, meta, [fun, [do: {:__block__, meta1, [deps]}]]}

      other ->
        other
    end)

    {quoted, comments} = Comments.extract_comments(quoted)

    quoted = Normalizer.normalize(quoted)

    {:ok, doc} = Formatter.quoted_to_algebra(quoted, comments: comments)

    new_source = doc |> Inspect.Algebra.format(98) |> IO.iodata_to_binary()

    IO.puts(new_source)
  end
end
