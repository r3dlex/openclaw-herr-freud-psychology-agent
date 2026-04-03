import Config

config :herr_freud, HerrFreud.Repo,
  database: "priv/herr_freud_test.db",
  pool_size: 1

config :herr_freud,
  env: :test,
  llm_mod: HerrFreud.LLM.Stub,
  embeddings_mod: HerrFreud.Embeddings.Stub,
  stt_mod: HerrFreud.STT.Stub,
  iamq_http_mod: HerrFreud.IAMQ.HttpStub

config :logger, level: :warning
