{:ok, _} = Application.ensure_all_started(:hackney)

Upload.Adapters.Test.start()
ExUnit.start()
