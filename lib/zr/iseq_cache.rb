# frozen_string_literal: true

require "digest/sha2"
require_relative "paths"

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
      return if !Config.current.iseq_cache? || (defined?(Coverage) && Coverage.running?)

      root = "#{Paths::ROOT}/"
      dir = File.join(Paths.cache, "iseq")
      salt = [RUBY_VERSION, RUBY_PLATFORM, RubyVM::InstructionSequence.compile_option.sort.inspect].join("\0")
      RubyVM::InstructionSequence.singleton_class.define_method(:load_iseq) do |path|
        IseqCache.load(path, dir, salt) if path.start_with?(root)
      end
    end

    # The instructions of the file at `path`, from the cache or compiled
    # now and kept. Nil makes ruby compile the file as it does without
    # the hook: a cache that fails must not stop zr.
    def load(path, dir, salt)
      source = File.binread(path)
      entry = File.join(dir, "#{Digest::SHA256.hexdigest("#{salt}\0#{path}\0#{source}")}.bin")
      begin
        return RubyVM::InstructionSequence.load_from_binary(File.binread(entry))
      rescue SystemCallError, TypeError, ArgumentError, RuntimeError
        nil
      end
      iseq = RubyVM::InstructionSequence.compile(source, path, path)
      begin
        Paths.write_atomic(entry, iseq.to_binary)
      rescue SystemCallError
        nil
      end
      iseq
    rescue SystemCallError
      nil
    end
  end
end
