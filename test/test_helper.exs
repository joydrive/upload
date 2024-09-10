{:ok, _} = Application.ensure_all_started(:hackney)

UploadOld.Adapters.Test.start()
ExUnit.start()
