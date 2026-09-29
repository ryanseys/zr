# frozen_string_literal: true

require "digest/sha2"
require "fileutils"
require_relative "config"
require_relative "paths"
require_relative "settled"
require_relative "sources"
require_relative "version"

module Zr
  # The binaries that `zr run` built, kept so that a second run of the
  # same program runs at once, with no lowering and no link.
  #
  # An entry is found by a digest of what a build reads before it knows
  # which files the program requires: zr's version, the runtime and link
  # digests, the target, the path root, the settings that change a
  # build's bytes, the link arguments, and the program's path and bytes.
  # The entry then lists every file that the build compiled, with the
  # digest of its bytes, and the key of eval support for a program that
  # evals. A hit needs each of them to be the same now, so an edit to a
  # required file is a miss, as a make rule would see it.
  #
  # The binary runs from the cache. A new file is slow to start the first
  # time (macOS checks it: 61 ms against 11 ms), so a copy per run would
  # give most of that back.
  class RunCache
    VERSION = 1
    # The most binaries kept. A new one removes the ones used longest ago.
    KEPT = 100

    def self.dir = File.join(Paths.cache, "run")

    # `ZR_RUN_CACHE=0` builds each run again.
    def self.wanted? = Zr.flag?("ZR_RUN_CACHE", default: true)

    # `digest` is the runtime's digest (`Zr.runtime_digest`).
    def initialize(input, target:, digest:, link:)
      @input = File.expand_path(input)
      config = Config.current
      key = Digest::SHA256.new
      @digest = digest
      [VERSION, Zr::VERSION, digest, Zr.link_digest, target.triple, Paths.root.to_s,
       config.linker, config.eval_walk?, config.verify?, *link, "\0", @input, File.binread(@input)].each do |part|
        key << part.to_s << "\0"
      end
      @entry = File.join(self.class.dir, key.hexdigest)
    end

    # The path of the kept binary when every file it was built from is as
    # it was, else nil.
    def hit
      binary = File.join(@entry, "program")
      sources = Marshal.load(File.binread(File.join(@entry, "sources")))
      return nil unless File.executable?(binary) && current?(sources)

      FileUtils.touch(@entry)
      binary
    rescue SystemCallError, TypeError, ArgumentError, EOFError
      nil
    end

    # Keeps the binary at `out`, built from `program`. It keeps nothing when
    # a source changed during the build (`Zr.moved`), when the build does
    # not know its sources, or when the binary spells the build directory
    # `work`, which a later run would not have.
    def keep(out, program, work)
      return if program.sources.empty? || Zr.moved
      return if File.binread(out).include?(work)

      sources = program.sources.dup
      sources[:eval] = [program.evals.meta_path, program.evals.key] if program.evals
      fresh = "#{@entry}.#{Process.pid}"
      FileUtils.rm_rf(fresh)
      FileUtils.mkdir_p(fresh)
      FileUtils.cp(out, File.join(fresh, "program"), preserve: true)
      File.binwrite(File.join(fresh, "sources"), Marshal.dump(sources))
      FileUtils.rm_rf(@entry)
      File.rename(fresh, @entry)
      trim
    rescue SystemCallError
      FileUtils.rm_rf(fresh) if fresh
    end

    # Removes the entries used longest ago, beyond KEPT.
    def trim
      entries = Dir[File.join(self.class.dir, "*")].select { |dir| File.directory?(dir) }
      return if entries.size <= KEPT

      entries.sort_by { |dir| File.mtime(dir) }.first(entries.size - KEPT).each { |dir| FileUtils.rm_rf(dir) }
    end

    private

    # Whether the eval support that the binary linked is still current: its
    # metadata has the same key, and the key of its files now is that key.
    def eval_current?(meta_path, key)
      require "json"
      meta = JSON.parse(File.read(meta_path))
      meta.fetch("key") == key && Zr.eval_files_key(@digest, meta.fetch("files")) == key
    rescue JSON::ParserError, KeyError, SystemCallError
      false
    end

    def current?(sources)
      sources.all? do |path, digest|
        if path == :eval
          eval_current?(*digest)
        else
          File.file?(path) && Digest::SHA256.file(path).hexdigest == digest
        end
      end
    end
  end
end
