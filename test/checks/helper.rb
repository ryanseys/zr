# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

ROOT = File.expand_path("../..", __dir__)

WASMTIME = ENV["WASMTIME"] || "wasmtime"
WASM_FLAGS = ["-W", "max-memory-size=#{ENV.fetch("ZE0_WASM_MEMORY", 1 << 30)}"].freeze

def wasmtime? = system(WASMTIME, "--version", out: File::NULL, err: File::NULL)

# A program a check runs must not be able to take the machine with it.
# `test/programs/utf8.rb` on the wasm road allocates in a loop: five
# gigabytes in twelve seconds, and it never ends. So a run is bounded in
# both time and resident memory, and one that passes either bound is
# killed and reads as a failure rather than as a hung machine.
#
# The memory is watched rather than asked for: wasmtime's own
# `max-memory-size` bounds the module's linear memory and not what the
# process resides in, which is what runs the machine out.
LIMIT = Integer(ENV.fetch("ZE0_LIMIT", 60))
RESIDENT = Integer(ENV.fetch("ZE0_RESIDENT", 2048))

# `[stdout, why]` of `argv` under `env`, `why` naming the bound it
# passed. `$?` is the child's, as `IO.popen` leaves it.
def bounded(env, argv, err:)
  why = nil
  out = IO.popen(env, argv, err: err) do |io|
    watchdog = Thread.new do
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + LIMIT
      loop do
        passed = beyond(io.pid, deadline)
        break if passed == :done

        if passed
          why = passed
          Process.kill("KILL", io.pid)
          break
        end
        sleep 0.25
      end
    rescue StandardError
      nil
    end
    io.read.tap { watchdog.kill }
  end
  [out, why]
end

# Which bound `pid` has passed, nil while it is within both, and `:done`
# once it has gone, which is what stops the watching.
def beyond(pid, deadline)
  return "#{LIMIT}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

  rss = `ps -o rss= -p #{pid} 2>/dev/null`.to_i
  return :done if rss.zero?

  "#{RESIDENT} MB resident" if rss > RESIDENT * 1024
end
