source = File.read!("lib/normalizer.ex")
quoted = Code.string_to_quoted!(source, token_metadata: true)
normalized = Normalizer.normalize(quoted)

Normalizer.quoted_to_string(normalized)
|> IO.puts
