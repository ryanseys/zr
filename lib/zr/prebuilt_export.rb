# frozen_string_literal: true

require_relative "prebuilt"

module Zr
  # The export half of a bundle (`zr cache export`): it builds the
  # runtimes into this cache (`warm`) and writes them as one file. It is
  # apart from lib/zr/prebuilt.rb, which a build loads to take a
  # platform gem's runtime, because a warm loads the whole API.
  module Prebuilt
    module_function

    # Writes the bundle of `target` to `out`, from this cache. Raises
    # Invalid when the cache has no built runtime for the target, or when
    # an entry names the install's own path, which another install would
    # not have.
    #: (Target target, String out) -> Hash[String, untyped]
    def export(target, out)
      started = Time.now
      warm(target)
      # Only the roots that the warm wrote or touched (`Store.root`): an
      # older one can name the entries of another zr, or of an eval kind
      # that this export does not build.
      roots = roots_of(target).select { |name, _| File.mtime(File.join(Cache::Store.dir, "roots", name)) >= started - 1 }
      raise Invalid, "the cache has no built runtime for #{target.triple}: build a program for it first" if roots.empty?

      entries = roots.values.flat_map { |text| text.lines(chomp: true) }.uniq.sort
      files = entries.reject { |rel| LEFT_OUT.include?(rel.split("/").first) }.flat_map { |rel| files_of(rel) }
      raise Invalid, "the roots of #{target.triple} name no entry in the cache; build a program for it again" if files.empty?

      modules = target.object_format == :wasm ? runtime_modules(files) : {}
      manifest = { "format" => FORMAT, "zr" => VERSION, "target" => target.triple, "roots" => roots,
                   "files" => files.map { |rel| entry(rel) },
                   "modules" => modules.map { |name, path| { "path" => name, "size" => File.size(path), "sha256" => Digest::SHA256.file(path).hexdigest } } }
      Paths.publish(out) do |draft|
        Zlib::GzipWriter.open(draft) do |gz|
          gz.mtime = 0
          json = JSON.generate(manifest)
          Tar.add(gz, MANIFEST, json.bytesize) { |io| io.write(json) }
          files.each do |rel|
            path = File.join(Cache::Store.dir, rel)
            Tar.add(gz, STORE + rel, File.size(path)) { |io| File.open(path, "rb") { |src| IO.copy_stream(src, io) } }
          end
          modules.each do |name, path|
            Tar.add(gz, MODULES + name, File.size(path)) { |io| File.open(path, "rb") { |src| IO.copy_stream(src, io) } }
          end
          Tar.finish(gz)
        end
      end
      manifest
    end

    # The runtime module of each wasm prelude in `files`, by its file
    # name: the module in `modules_dir`, written there from the prelude
    # when it is not there yet. One prelude at a time is loaded: one with
    # eval support is 250 MB of Marshal.
    #: (Array[String] files) -> Hash[String, String]
    def runtime_modules(files)
      require_relative "native/build"
      files.filter_map do |rel|
        next unless rel.start_with?("wasm/") && rel.end_with?(".marshal") && !File.basename(rel).start_with?("prelude-")

        key = File.basename(rel, ".marshal")
        name = Native::Build.wasm_runtime_name(key)
        path = File.join(modules_dir, name)
        unless File.exist?(path)
          prelude = Marshal.load(File.binread(File.join(Cache::Store.dir, rel)))
          Paths.mkdir_p(modules_dir)
          Paths.write_atomic(path, Backend::Wasm.runtime_module(prelude, link: Native::Build.wasm_link_text(key)))
        end
        [name, path]
      end.sort.to_h
    end

    # Builds a plain program and one with eval for `target` into this
    # cache, so that its link and built roots name this zr's runtime and
    # eval support; for a native target, also one with the tree-walking
    # eval support (ZR_EVAL=walk). A cache that has them takes seconds;
    # an empty one takes the minutes of a first build.
    #: (Target target) -> void
    def warm(target)
      require "tmpdir"
      require_relative "api"
      evals = "puts eval(\"1 + 1\")\n"
      builds = { "plain" => ["puts 1 + 1\n", {}], "evals" => [evals, {}] } #: Hash[String, [String, Hash[Symbol, String]]]
      builds["walked"] = [evals, { eval_mode: "walk" }] if target.link
      # The settings of this process that a build reads: `Zr.build`
      # reads none from ENV.
      config = Config.current
      given = { cache_dir: Paths.cache, timing: config.timing?, verify: config.verify? } #: Hash[Symbol, untyped]
      given[:jobs] = config.jobs if config.jobs_given?
      Dir.mktmpdir("zr-warm-") do |dir|
        builds.each do |name, (source, settings)|
          # Each in a process of its own: a process keeps one eval support
          # for each target (`EvalSupport.for`), which a second kind of
          # eval support would reuse.
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          pid = Process.fork do
            Process.setproctitle("zr warm #{name} #{target.triple}")
            Zr.build(File.join(dir, "#{name}.rb"), source: source, out: File.join(dir, name), target: target.triple,
                                                   settings: { **given, **settings })
            exit!(0)
          rescue StandardError, ScriptError => e
            warn "zr: #{e.message}"
            exit!(1)
          end
          raise Invalid, "the #{name} build for #{target.triple} did not finish" unless Process.wait2(pid).last.success?

          if config.timing?
            warn format("zr: warmed %s for %s in %.1f s", name, target.triple,
                        Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
          end
        end
      end
    end

    # The roots of `target` in this cache that a bundle holds, by name,
    # with their text.
    #: (Target target) -> Hash[String, String]
    def roots_of(target)
      dir = File.join(Cache::Store.dir, "roots")
      return {} unless File.directory?(dir)

      Dir.children(dir).sort.filter_map do |name|
        next unless name.start_with?(target.triple) && root?(name)

        [name, File.read(File.join(dir, name))]
      end.to_h
    end

    # The files of the entry `rel`: itself, or each file of a directory
    # entry. An entry that is gone gives none.
    #: (String rel) -> Array[String]
    def files_of(rel)
      path = File.join(Cache::Store.dir, rel)
      return [] unless File.exist?(path)
      return [rel] unless File.directory?(path)

      Dir.children(path).sort.filter_map { |child| File.join(rel, child) if File.file?(File.join(path, child)) }
    end

    # The manifest's row of the store file `rel`. A file that names this
    # install's path would not serve another install, so it stops the
    # export.
    #: (String rel) -> Hash[String, untyped]
    def entry(rel)
      path = File.join(Cache::Store.dir, rel)
      bytes = File.binread(path)
      Paths::INSTALLED.each do |dir|
        raise Invalid, "#{rel} names this install's path (#{dir}); a bundle must not" if bytes.include?(dir)
      end
      { "path" => rel, "size" => bytes.bytesize, "sha256" => Digest::SHA256.hexdigest(bytes) }
    end
  end
end
