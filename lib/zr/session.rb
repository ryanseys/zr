# frozen_string_literal: true

module Zr
  # The state that one zr process keeps across its builds: each value
  # that a module reads from the environment or the disk, or builds,
  # once per process. A module keeps it here (`memo`), not in its own
  # instance variables, so one call starts the next build as a new zr
  # would (`reset!`): a warm server does that before each build.
  class Session
    # @rbs @memos: Hash[Symbol | Array[untyped], untyped]

    # The memos that the environment decides: the settings, the cache
    # directory, and the library roots and directories that follow from
    # them. A new build reads them again.
    ENVIRONMENT = %i[config cache library_roots stdlib].freeze

    # The memos that a build makes: the runtimes and eval supports.
    # A server keeps them for a build with the same settings and the
    # same runtime digest.
    BUILT = %i[runtimes eval_supports].freeze

    # The one session of this process.
    #: () -> Session
    def self.current = @current ||= new

    #: () -> void
    def initialize
      @memos = {}
    end

    # The value of `key`, made by the block the first time. A key is a
    # Symbol, or an Array whose first element names its kind.
    #: [T] (Symbol | Array[untyped] key) { () -> T } -> T
    def memo(key) = @memos.fetch(key) { @memos[key] = yield }

    # Sets the value of `key`, as a test does for a directory of its own.
    #: [T] (Symbol | Array[untyped] key, T value) -> T
    def set(key, value)
      @memos[key] = value
    end

    # Drops the value of `key`, so the next `memo` makes it again.
    #: (Symbol | Array[untyped] key) -> untyped
    def forget(key)
      @memos.delete(key)
    end

    # Drops each memo that the environment decides, and with them the
    # built runtimes, unless `keep_runtimes`. The rest (parses, prelinks,
    # digests of zr's own files) depend only on bytes that their keys
    # name, so they stay.
    #: (?keep_runtimes: bool) -> void
    def reset!(keep_runtimes: false)
      dropped = keep_runtimes ? ENVIRONMENT : ENVIRONMENT + BUILT
      @memos.delete_if { |key, _| dropped.include?(key.is_a?(Array) ? key.first : key) }
    end
  end
end
