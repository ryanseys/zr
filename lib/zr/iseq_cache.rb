# frozen_string_literal: true

require_relative "store"

module Zr
  # The compiled instructions of zr's own Ruby files, kept in the cache.
  # Ruby compiles each file that it loads, at each start: 73 ms of a
  # `zr run` for the 146 files of the compiler. Loading them from the
  # cache takes 14 ms, and 5 ms more to hash the sources.
  #
  # Ruby asks `RubyVM::InstructionSequence.load_iseq` for each file that a
  # require loads (the hook that bootsnap uses), and compiles the file
  # itself when the hook returns nil. The key of an entry is the file's
  # path and bytes, the ruby and its compile options, so an edit is a
  # miss. Only files under zr's root use the cache, only under CRuby, and
  # never while Coverage runs (a cached file would not count lines).
  module IseqCache
    module_function

    def install
      return if Zr.compiled? || !defined?(RubyVM::InstructionSequence.load_from_binary)
      return if (defined?(Coverage) && Coverage.running?) || !wanted?

      root = "#{Paths::ROOT}/"
      salt = [RUBY_VERSION, RUBY_PLATFORM, RubyVM::InstructionSequence.compile_option.sort.inspect].join("\0")
      RubyVM::InstructionSequence.singleton_class.define_method(:load_iseq) do |path|
        IseqCache.load(path, salt) if path.start_with?(root)
      end
    end

    # Whether the cache is on. With a bad ZR_* value, or no cache
    # directory (HOME is not set), ruby compiles zr's files as usual, and
    # the command reports the problem.
    def wanted?
      Config.current.iseq_cache? && Paths.cache
    rescue StandardError
      false
    end

    # The instructions of the file at `path`, from the cache or compiled
    # now and kept. Nil makes ruby compile the file as it does without
    # the hook: a cache that fails must not stop zr.
    def load(path, salt)
      source = File.binread(path)
      key = Store.key(salt, path, source)
      if (binary = Store.read(:iseq, key))
        begin
          return RubyVM::InstructionSequence.load_from_binary(binary)
        rescue TypeError, ArgumentError, RuntimeError
          nil
        end
      end
      iseq = RubyVM::InstructionSequence.compile(source, path, path)
      begin
        Store.write(:iseq, key, iseq.to_binary)
      rescue SystemCallError, SourceChanged
        nil
      end
      iseq
    rescue SystemCallError
      nil
    end
  end
end
