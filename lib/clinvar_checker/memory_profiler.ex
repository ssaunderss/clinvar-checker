defmodule ClinvarChecker.MemoryProfiler do
  # require Logger

  @spec profile((-> any())) :: any()
  def profile(func) do
    initial_memory = :erlang.memory()

    {time, result} = :timer.tc(func)

    final_memory = :erlang.memory()

    memory_diff =
      for {type, after_bytes} <- final_memory do
        {type, after_bytes - initial_memory[type]}
      end

    IO.puts("""
    Memory Usage:
    Total: #{Sizeable.filesize(memory_diff[:total])}
    Processes: #{Sizeable.filesize(memory_diff[:processes])}
    System: #{Sizeable.filesize(memory_diff[:system])}
    Atom: #{Sizeable.filesize(memory_diff[:atom])}
    Binary: #{Sizeable.filesize(memory_diff[:binary])}
    Code: #{Sizeable.filesize(memory_diff[:code])}
    ETS: #{Sizeable.filesize(memory_diff[:ets])}

    Execution time: #{time / 1_000_000} seconds
    """)

    result
  end
end
