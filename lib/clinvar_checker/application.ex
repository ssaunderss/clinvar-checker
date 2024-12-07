defmodule ClinvarChecker.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # children = [
    # Starts a worker by calling: ClinvarChecker.Worker.start_link(arg)
    # {ClinvarChecker.Worker, arg}
    # ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    # opts = [strategy: :one_for_one, name: ClinvarChecker.Supervisor]
    # Supervisor.start_link(children, opts)
    #
    args = Burrito.Util.Args.get_arguments()
    ClinvarChecker.Cli.main(args)
    System.halt(0)
  end
end
