# frozen_string_literal: true

require "digest/sha2"
require_relative "../config"
require_relative "../paths"
require_relative "../ir/fingerprint"

module Zr
  module Native
    # The machine code of each function that a build assembled, kept by the
    # function's fingerprint (`IR::Fingerprint`), so that the next build
    # assembles only the functions whose IR changed.
    #
    # An edit to one file of the runtime lowers the kernel and the core
    # again, but most functions come out with the same IR. Their passes and
    # their assembly were 58 s of work for the runtime object, and 177 s for
    # eval support, before this cache.
    #
    # The cache has one directory for each backend digest: the files that
    # the passes and the backend load (`BACKEND`), and this file. An edit to
    # the lowering keeps the directory; an edit to a pass or to the backend
    # starts a new one. Each build of an object writes one pack, with the
    # code of all its functions, and an index of it. A build reads the
    # indexes of the packs of its kind, and keeps the `KEPT` newest packs of
    # each kind of object.
    #
    # `ZR_CODE_CACHE=0` turns it off. `ZR_CODE_CACHE=verify` assembles each
    # function that the cache has, too, and raises when the bytes differ.
    class CodeCache
      VERSION = 1
      # The newest packs of one kind that a build keeps.
      KEPT = 3

      # The files that `IR::Passes.prepare` and `Backend::Aarch64.assemble`
      # load, relative to lib/zr. `code_cache_test.rb` checks that a new
      # process that requires them loads no other file of zr.
      BACKEND = %w[
        backend.rb backend/aarch64.rb backend/aarch64/assembler.rb backend/aarch64/codegen.rb
        backend/aarch64/codegen/layout.rb backend/aarch64/codegen/moves.rb backend/aarch64/regalloc.rb
        backend/aarch64/registers.rb backend/aarch64/stub.rb bytes.rb config.rb ir/analysis.rb
        ir/effects.rb ir/fingerprint.rb ir/function.rb ir/gvn.rb ir/inst.rb ir/licm.rb ir/passes.rb
        ir/promotion.rb ir/regions.rb ir/statics.rb ir/types.rb ir/verify.rb obj/model.rb refused.rb
        native/code_cache.rb paths.rb version.rb
      ].freeze

      LIB = File.expand_path("..", __dir__)

      def self.mode = Config.current.code_cache

      # The cache for objects of `kind` (such as "runtime"), or nil when the
      # cache is off or the target has another backend.
      def self.for(kind, target)
        return nil if mode == "0" || target.arch != :aarch64

        new(kind)
      end

      def self.backend_digest
        @backend_digest ||= Digest::SHA256.new.tap do |d|
          d << VERSION.to_s << "\0"
          BACKEND.each { |name| d << name << "\0" << File.binread(File.join(LIB, name)) << "\0" }
        end.hexdigest
      end

      # The store loads here, not with this file: a file that the backend
      # loads is in BACKEND, and an edit to the store must not make every
      # pack a miss.
      def self.dir
        require_relative "../cache/store"
        Cache::Store.path(:code, backend_digest[0, 32])
      end

      attr_reader :hits, :misses

      def initialize(kind)
        @kind = kind
        @dir = self.class.dir
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

      def verify? = self.class.mode == "verify"

      # The code for `key`, or nil. The raw bytes come with it, for the new
      # pack.
      def take(key)
        blob = blob(key)
        blob && [Marshal.load(blob), blob]
      rescue TypeError, ArgumentError
        nil
      end

      # Only the raw bytes of the code for `key`, or nil. A worker sends
      # them to the build, which loads them once: a load in the worker as
      # well was 7% of its time.
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
      def handle(pack) = (@handles ||= {})[pack] ||= File.open(pack, "rb")

      def close = (@handles || {}).each_value(&:close).tap { @handles = {} }

      # Writes one pack with the code of every function of this build:
      # `entries` are `[key, blob]` pairs, a blob being Marshal of an
      # `Obj::Code`. Then removes the packs of this kind beyond KEPT.
      # Writes nothing if a source changed during the build.
      def keep(entries)
        close
        return if SourceGuard.changed_file

        Paths.mkdir_p(@dir)
        stem = File.join(@dir, "#{@kind}-#{Time.now.strftime("%Y%m%d%H%M%S%N")}-#{Process.pid}")
        index = {}
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

      def trim
        packs = Dir[File.join(@dir, "#{@kind}-*.pack")].sort_by { |pack| File.mtime(pack) }
        packs.first([packs.size - KEPT, 0].max).each do |pack|
          [pack, pack.sub(/\.pack\z/, ".index")].each { |path| File.delete(path) if File.exist?(path) }
        end
      end
    end
  end
end
