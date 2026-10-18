# frozen_string_literal: true

require "digest/sha2"
require_relative "../config"
require_relative "../ir/fingerprint"

module Zr
  module Cache
    # The machine code of each function that a build assembled, kept by the
    # function's fingerprint (`IR::Fingerprint`), so that the next build
    # assembles only the functions whose IR changed.
    #
    # An edit to one file of the runtime lowers the kernel and the core
    # again, but most functions come out with the same IR. Their passes and
    # their assembly were 58 s of work for the runtime object, and 177 s for
    # eval support, before this cache.
    #
    # The cache has one directory for each backend digest: the code of the
    # files that the passes and the backend load (`BACKEND`), and this file.
    # An edit to the lowering, or to a comment, keeps the directory; an edit
    # to the code of a pass or of the backend starts a new one. Each build of an object writes one pack, with the
    # code of all its functions, and an index of it. A build reads the
    # indexes of the packs of its kind, and keeps the `KEPT` newest packs of
    # each kind of object.
    #
    # `ZR_CODE_CACHE=0` turns it off. `ZR_CODE_CACHE=verify` assembles each
    # function that the cache has, too, and raises when the bytes differ.
    class Code
      # @rbs @kind: String
      # @rbs @dir: String
      # @rbs @index: Hash[String, [String, Integer, Integer]]
      # @rbs @handles: Hash[String, File]?

      VERSION = 1
      # The newest packs of one kind that a build keeps.
      KEPT = 3

      # The files that `IR::Passes.prepare` and each backend load, relative
      # to lib/zr: the files of the passes, then the backend's own.
      # `code_cache_test.rb` checks that a new process that requires them
      # loads no other file of zr.
      PASSES = %w[
        backend.rb binary.rb bytes.rb config.rb ir/analysis.rb ir/effects.rb ir/fingerprint.rb ir/function.rb ir/gvn.rb
        ir/inst.rb ir/licm.rb ir/passes.rb ir/passes/blocks.rb ir/passes/chains.rb ir/passes/dce.rb
        ir/passes/fold.rb ir/passes/forward.rb ir/passes/inline.rb ir/passes/renaming.rb ir/promotion.rb
        ir/regions.rb ir/statics.rb ir/switches.rb ir/threads.rb ir/types.rb ir/verify.rb obj/model.rb
        refused.rb cache/code.rb session.rb timing.rb
      ].freeze
      BACKENDS = {
        aarch64: %w[
          backend/aarch64.rb backend/aarch64/assembler.rb backend/aarch64/codegen.rb
          backend/aarch64/codegen/layout.rb backend/aarch64/codegen/moves.rb backend/aarch64/registers.rb
          backend/aarch64/stub.rb backend/native/planner.rb backend/native/pools.rb backend/native/regalloc.rb
        ],
        wasm32: %w[backend/wasm.rb backend/wasm/codegen.rb backend/wasm/codegen/body.rb backend/wasm/locals.rb backend/wasm/shims.rb]
      }.transform_values { |own| (PASSES + own).freeze }.freeze #: Hash[Symbol, Array[String]]

      LIB = File.expand_path("..", __dir__) #: String

      #: () -> String
      def self.mode = Config.current.code_cache

      # The cache of aarch64 code for objects of `kind` (such as "runtime"),
      # or nil when the cache is off or the target has another backend.
      #: (String kind, Target target) -> Code?
      def self.for(kind, target)
        return nil if mode == "0" || target.arch != :aarch64

        new(kind)
      end

      # The cache of wasm bodies for preludes of `kind`
      # (`Native::Build.prepared_bodies`), or nil when the cache is off.
      #: (String kind) -> Code?
      def self.wasm(kind) = mode == "0" ? nil : new(kind, :wasm32)

      # The digests load here, not with this file (see `dir`).
      #: (?Symbol arch) -> String
      def self.backend_digest(arch = :aarch64)
        Session.current.memo([:backend_digest, arch]) do
          require_relative "../digests"
          Digest::SHA256.new.tap do |d|
            d << VERSION.to_s << "\0"
            BACKENDS.fetch(arch).each { |name| d << name << "\0" << Digests.file(File.join(LIB, name)) << "\0" }
          end.hexdigest
        end
      end

      # The store (and `Paths`, which `keep` uses) loads here, not with
      # this file: a file that the backend loads is in BACKENDS, and an edit
      # to the store must not make every pack a miss.
      #: (?Symbol arch) -> String
      def self.dir(arch = :aarch64)
        require_relative "store"
        key = backend_digest(arch)[0, 32] #: String
        Store.path(:code, key)
      end

      attr_reader :hits, :misses #: Integer

      #: (String kind, ?Symbol arch) -> void
      def initialize(kind, arch = :aarch64)
        @kind = kind
        @dir = self.class.dir(arch)
        @index = {}
        # Only this kind's packs: the functions of one kind of object are not
        # in another's, and eval support's indexes alone take a second.
        Dir[File.join(@dir, "#{kind}-*.index")].sort.each do |index|
          pack = index.sub(/\.index\z/, ".pack")
          next unless File.file?(pack)

          Marshal.load(File.binread(index)).each { |key, (at, size)| @index[key] = [pack, at, size] }
        rescue SystemCallError, TypeError, ArgumentError
          next
        end
        @hits = @misses = 0
      end

      #: () -> bool
      def verify? = self.class.mode == "verify"

      # Whether a pack has the code for `key`. Reads no pack.
      #: (String key) -> bool
      def has?(key) = @index.key?(key)

      # The code for `key`, or nil. The raw bytes come with it, for the new
      # pack.
      #: (String key) -> [Obj::Code, String]?
      def take(key)
        blob = blob(key)
        blob && [Marshal.load(blob), blob]
      rescue TypeError, ArgumentError
        nil
      end

      # Only the raw bytes of the code for `key`, or nil. A worker sends
      # them to the build, which loads them once: a load in the worker as
      # well was 7% of its time.
      #: (String key) -> String?
      def blob(key)
        pack, at, size = @index[key]
        return nil unless pack

        blob = handle(pack).pread(size, at)
        blob if blob.bytesize == size
      rescue SystemCallError, EOFError
        nil
      end

      # One open file for each pack that this build reads. An open for each
      # function cost more than its read.
      #: (String pack) -> File
      def handle(pack)
        handles = @handles ||= {} #: Hash[String, File]
        handles[pack] ||= File.open(pack, "rb")
      end

      #: () -> Hash[String, File]
      def close = (@handles || {}).each_value(&:close).tap { @handles = {} }

      # Writes one pack with the code of every function of this build:
      # `entries` are `[key, blob]` pairs, a blob being Marshal of an
      # `Obj::Code`. Then removes the packs of this kind beyond KEPT.
      # Writes nothing if a source changed during the build.
      #: (Array[[String, String]] entries) -> void
      def keep(entries)
        close
        return if SourceGuard.changed_file

        Paths.mkdir_p(@dir)
        stem = File.join(@dir, "#{@kind}-#{Time.now.strftime("%Y%m%d%H%M%S%N")}-#{Process.pid}")
        index = {} #: Hash[String, [Integer, Integer]]
        File.open("#{stem}.pack.tmp", "wb") do |io|
          entries.each do |key, blob|
            index[key] = [io.pos, blob.bytesize]
            io.write(blob)
          end
        end
        File.binwrite("#{stem}.index.tmp", Marshal.dump(index))
        File.rename("#{stem}.pack.tmp", "#{stem}.pack")
        File.rename("#{stem}.index.tmp", "#{stem}.index")
        trim
      rescue SystemCallError
        nil
      end

      #: () -> void
      def trim
        packs = Dir[File.join(@dir, "#{@kind}-*.pack")].sort_by { |pack| File.mtime(pack) }
        packs.first([packs.size - KEPT, 0].max).each do |pack|
          [pack, pack.sub(/\.pack\z/, ".index")].each { |path| File.delete(path) if File.exist?(path) }
        end
      end
    end
  end
end
