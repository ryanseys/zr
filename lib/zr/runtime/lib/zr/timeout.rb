# frozen_string_literal: true

# Timeout where no Thread can start: a wasm32-wasi module has no stack
# for a Fiber, and so none for a Thread (Hir::Build::Loader.tails runs
# this file at the end of timeout.rb). Timeout's watcher is a Thread, so
# there the block runs with no watcher, and no timeout interrupts it, as
# in a ruby built without threads. syntax_suggest, for one, runs its
# search in Timeout.timeout.
if RUBY_PLATFORM.end_with?("wasi")
  module Timeout
    class State
      def ensure_timeout_thread_created = nil
    end
  end
end
