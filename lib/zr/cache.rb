# frozen_string_literal: true

require_relative "paths"
require_relative "version"

module Zr
  # The runtime cache (`Paths.cache`): a runtime object, a prelinked image
  # and an eval support object for each digest that a zr builds, the
  # binaries that the spec tier keeps, and the parsed trees. The digest
  # changes with every file under lib/ and runtime/, so old entries
  # collect: 9.5 GB after one week of work in a checkout, and some
  # hundred MB for each release that a user installs.
  #
  # `zr cache` and `zr-dev cache` read and clean it with this module. A
  # clean keeps the files that this zr uses (`live`), whatever their age,
  # so the next build rebuilds nothing. All other files are
  # content-addressed and made again on demand.
  module Cache
    module_function

    # The cache files, the binaries that the spec tier and `zr run` keep in
    # the cache, the parsed trees (lib/zr/parse_cache.rb) and the packs of
    # machine code (lib/zr/native/code_cache.rb). Their names come from the
    # source only, so only age shows which are not used.
    def all = Dir[File.join(Paths.cache, "{*,binaries/*,parse/*,run/*/*,code/*/*,core/*/*,eval-*/*/*}")].select { |path| File.file?(path) }

    # The compiled compilers of other zr versions and installs, in the
    # user's cache (lib/zr/compiled_compiler.rb). Each one is about
    # 120 MB.
    def other_compilers
      require_relative "compiled_compiler"
      own = CompiledCompiler.install_dir
      Dir[File.join(Paths.user_cache, "self-*")].select { |dir| File.directory?(dir) && dir != own }
    end

    def load!
      require_relative "runtime"
      require_relative "native/build"
    end

    # The files that this zr uses, for each target: the runtime object,
    # the eval support object and its meta file, and the prelinked image
    # of each. Only the meta file gives the key of the eval support
    # object.
    def live
      load!
      Target.all.flat_map { |target| live_for(target) }.compact.uniq
    rescue StandardError, ScriptError
      [] # if the compiler does not load, keep no file as live
    end

    def live_for(target)
      runtime = Zr.runtime(target)
      object = runtime.object_path
      # Without its symbol table, a runtime was never built here, so no eval
      # support was either; the ABI digest would need the core lowered.
      base = Zr.eval_digest(target, runtime.digest)
      metas = base ? %w[jit walk].map { |kind| EvalSupport.meta_file(base, kind) }.select { |path| File.exist?(path) } : []
      evals = metas.filter_map { |meta| eval_object(meta) }
      sets = [[object], *evals.map { |eval| [object, eval] }]
      [object, runtime.gem_prelude_path, *metas, *evals, *sets.map { |set| Native::Build.prelink_path(set) },
       *sets.map { |set| Native::Build.skeleton_path(set) }] + Dir[File.join(Paths.cache, "*-#{runtime.digest}.*")]
    end

    # The eval support object. Only its meta file gives its path.
    def eval_object(meta)
      require "json"
      key = JSON.parse(File.read(meta)).fetch("key") if File.exist?(meta)
      key && EvalSupport.object_path(key)
    end

    def bytes(paths) = paths.sum { |path| File.size?(path).to_i }
    def megabytes(paths) = bytes(paths) / (1 << 20)

    # The bytes of every file below `dir`.
    def tree_bytes(dir) = bytes(Dir[File.join(dir, "**/*")].select { |path| File.file?(path) })

    def kind(path)
      return "binary" if File.basename(File.dirname(path)) == "binaries"
      return "parse" if File.basename(File.dirname(path)) == "parse"
      return "code" if File.basename(File.dirname(path, 2)) == "code"
      return "core" if File.basename(File.dirname(path, 2)) == "core"
      return "eval units" if File.basename(File.dirname(path, 2)).start_with?("eval-")
      return "run" if File.basename(File.dirname(path, 2)) == "run"

      File.basename(path).sub(/-[0-9a-f]{64}/, "").sub(/\A[^.]*\./, "")
    end

    # Deletes the files that this zr does not use and that are older than
    # `days`. Returns the paths it deleted.
    def prune(days: 0)
      live = self.live
      young = Time.now - (days * 86_400)
      stale = all.reject { |path| live.include?(path) || File.mtime(path) > young }
      stale.each { |path| File.delete(path) }
      stale
    end

    # Deletes every cache file, also the ones this zr uses. Returns the
    # paths it deleted.
    def clear
      files = all
      files.each { |path| File.delete(path) }
      files
    end

    # The most GB that an installed zr keeps in its cache before a build
    # prunes it (`ZR_CACHE_MAX_GB`, default 5; 0 turns the limit off).
    def limit_gb = Config.current.cache_max_gb

    # How often a build measures the cache. A measure stats every file
    # (tens of thousands of parsed trees), so a build does it at most once
    # a day.
    CHECK_EVERY = 86_400

    # After a build of an installed zr: when the cache is over the limit,
    # delete what this zr does not use, then the compiled compilers of
    # other versions. A checkout cleans its own cache with
    # `zr-dev cache prune`, because the tests keep binaries in it.
    def trim
      return if Paths.checkout? || limit_gb <= 0

      stamp = File.join(Paths.cache, ".measured")
      return if File.exist?(stamp) && Time.now - File.mtime(stamp) < CHECK_EVERY

      Paths.write_atomic(stamp, "")
      return if bytes(all) < limit_gb * (1 << 30)

      prune
      other_compilers.each { |dir| Paths.remove(dir) }
    rescue SystemCallError
      nil # a cache that cannot be measured or cleaned does not stop a build
    end
  end
end
