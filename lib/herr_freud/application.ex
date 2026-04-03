defmodule HerrFreud.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # In test environment, skip all external-service children to avoid failures
    children =
      if :test == Application.get_env(:herr_freud, :env, :prod) do
        [
          HerrFreud.Repo,
          {Task.Supervisor, name: HerrFreud.Session.TaskSupervisor},
          HerrFreud.Style.Manager
        ]
      else
        [
          HerrFreud.Repo,
          {Task.Supervisor, name: HerrFreud.Session.TaskSupervisor},
          HerrFreud.Style.Manager,
          HerrFreud.IAMQ.HttpClient,
          HerrFreud.Input.Watcher,
          HerrFreud.Cron.Handler
        ]
      end

    opts = [strategy: :one_for_one, name: HerrFreud.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
