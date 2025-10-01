Application.ensure_all_started(:mimic)

Mox.defmock(Hermes.MockTransport, for: Hermes.Transport.Behaviour)

if Code.ensure_loaded?(:gun), do: Mimic.copy(:gun)

# Start Finch for SSE streaming tests
{:ok, _} = Finch.start_link(name: Hermes.TestFinch)

ExUnit.start()
