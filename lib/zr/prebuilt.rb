# frozen_string_literal: true

require "digest/sha2"
require "fileutils"
require "json"
require "zlib"
require_relative "cache/store"
require_relative "config"
require_relative "error"
require_relative "paths"
require_relative "target"
require_relative "version"

module Zr
  # A target's built runtime as one file, so that a machine can take it
  # in place of the minutes of its first build (`zr cache export` and
  # `zr cache import`). A runtime has no path of the install in it
  # (`Paths.portable`), so a bundle that one install wrote serves another
  # install of the same zr at any path.
  #
  # A bundle is a gzip stream: the line `zr-runtime 1`, one line of JSON
  # (the manifest: zr's version, the target, each file's path, size and
  # SHA-256, and the text of each root), then each file's bytes in the
  # manifest's order. It holds the entries that the link and built roots
  # of the target name (`ROOTS`): what a build reads when nothing has
  # changed. The lowerings and the packs of machine code (`LEFT_OUT`),
  # which only speed up a build after a change, stay out: half of a
  # runtime's bytes.
  #
  # An import trusts the bundle as zr trusts its cache (SECURITY.md): the
  # cache holds Marshal data and code that zr runs. So it takes only a
  # bundle that the caller names, checks its SHA-256 when the caller gives
  # one, and checks each file against the manifest before the file goes
  # into the store.
  module Prebuilt
    FORMAT = "zr-runtime 1"

    # The roots of a target that a bundle holds, by their names after the
    # target's triple.
    ROOTS = /\A-(?:link|built|prelude)-[\w.-]+\z/

    # A file of the store: `<kind>/<2>/<key>`, or a file in a directory
    # entry (`code/9f/9fe0…/eval.pack`).
    ENTRY = %r{\A[a-z]+/[0-9a-f]{2}/[0-9A-Za-z][\w.-]*(?:/[0-9A-Za-z][\w.-]*)?\z}

    # A line of a root: an entry of the store, a file or a directory.
    ROOT_LINE = %r{\A[a-z]+/[0-9a-f]{2}/[0-9A-Za-z][\w.-]*\z}

    # The kinds of entry that a root names and a bundle leaves out: a
    # build from the runtime's object and images reads none of them.
    LEFT_OUT = %w[code].freeze

    # A bundle that zr cannot take.
    class Invalid < StandardError
      include Zr::Error
    end

    # Where a release keeps its bundles: the GitHub Release of the tag.
    # ZR_PREBUILT_URL names a mirror with the same files.
    RELEASES = "https://github.com/ryanseys/zr/releases/download"

    # The most bytes that `fetch` takes for one file.
    MAX_BYTES = 2 << 30

    # The most redirects that `fetch` follows for one file.
    REDIRECTS = 5

    module_function

    # The file name of the bundle of `target` for this zr.
    #: (Target target) -> String
    def bundle_name(target) = "zr-runtime-#{VERSION}-#{target.triple}.zrr"

    # The directory of this version's bundles.
    #: () -> String
    def url = (Config.prebuilt_url || "#{RELEASES}/v#{VERSION}").chomp("/")

    # Downloads the bundle of `target` for this zr and imports it (`zr
    # cache fetch`). It checks the bundle against the release's SHA256SUMS,
    # or against `sha256` when the caller gives one. zr downloads nothing
    # unless this runs.
    #: (Target target, ?sha256: String?) -> Hash[String, untyped]
    def fetch(target, sha256: nil)
      require "tmpdir"
      Dir.mktmpdir("zr-fetch-") do |dir|
        sha256 ||= listed_sha256(download("#{url}/SHA256SUMS", File.join(dir, "SHA256SUMS")), bundle_name(target))
        import(download("#{url}/#{bundle_name(target)}", File.join(dir, bundle_name(target))), sha256: sha256)
      end
    end

    # The digest that the SHA256SUMS file at `path` gives `file`.
    #: (String path, String file) -> String
    def listed_sha256(path, file)
      line = File.readlines(path, chomp: true).find { |row| row.split(/\s+\*?/, 2).last == file }
      line or raise Invalid, "the release lists no #{file}: it has no prebuilt runtime for this target"
      line.split.first.to_s
    end

    # Downloads `from` (https only) into `to`, at most MAX_BYTES, after at
    # most REDIRECTS redirects. Returns `to`.
    #: (String from, String to, ?Integer hops) -> String
    def download(from, to, hops = REDIRECTS)
      require "net/http"
      uri = URI(from)
      raise Invalid, "zr fetches over https only, not #{from}" unless uri.is_a?(URI::HTTPS)

      host = uri.host or raise Invalid, "#{from} names no host"
      Net::HTTP.start(host, uri.port, use_ssl: true, open_timeout: 30, read_timeout: 120) do |http|
        http.request(Net::HTTP::Get.new(uri)) do |response|
          case response
          when Net::HTTPRedirection
            raise Invalid, "#{from} redirects more than #{REDIRECTS} times" if hops.zero?

            return download(URI.join(from, response["location"].to_s).to_s, to, hops - 1)
          when Net::HTTPSuccess
            save(response, to, from)
          else
            raise Invalid, "#{from} answered #{response.code} #{response.message}"
          end
        end
      end
      to
    rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse => e
      raise Invalid, "zr could not download #{from}: #{e.message}"
    end

    # Writes the body of `response` to `to`, and stops at MAX_BYTES.
    #: (Net::HTTPResponse response, String to, String from) -> void
    def save(response, to, from)
      size = 0
      File.open(to, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |out|
        response.read_body do |chunk|
          size += chunk.bytesize
          raise Invalid, "#{from} is larger than #{MAX_BYTES >> 20} MB" if size > MAX_BYTES

          out.write(chunk)
        end
      end
    end

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

      manifest = { "format" => FORMAT, "zr" => VERSION, "target" => target.triple, "roots" => roots,
                   "files" => files.map { |rel| entry(rel) } }
      Paths.publish(out) do |draft|
        Zlib::GzipWriter.open(draft) do |gz|
          gz.mtime = 0
          gz.write("#{FORMAT}\n#{JSON.generate(manifest)}\n")
          files.each { |rel| File.open(File.join(Cache::Store.dir, rel), "rb") { |io| IO.copy_stream(io, gz) } }
        end
      end
      manifest
    end

    # Reads the bundle at `file` into this cache: each file the cache
    # lacks, then the roots. With `sha256`, the bundle must have that
    # digest. Returns the manifest. Raises Invalid for a bundle of another
    # zr, a changed file, or a path that is no entry of the store.
    #: (String file, ?sha256: String?) -> Hash[String, untyped]
    def import(file, sha256: nil)
      # @type var staging: String
      if sha256 && (got = Digest::SHA256.file(file).hexdigest) != sha256.downcase
        raise Invalid, "#{file} has SHA-256 #{got}, not #{sha256}"
      end

      store = Cache::Store.dir
      # Beside the store, not in it, where no listing of the store's kinds
      # meets it; on the same file system, so each file renames into place.
      staging = File.join(Paths.cache, ".import-#{Process.pid}-#{rand(1 << 32).to_s(16)}")
      manifest = {} #: Hash[String, untyped]
      Zlib::GzipReader.open(file) do |gz|
        manifest = header(gz)
        Paths.mkdir_p(staging, 0o700)
        manifest.fetch("files").each { |row| stage(gz, row, staging) }
        manifest.fetch("files").each { |row| place(File.join(staging, row.fetch("path")), File.join(store, row.fetch("path"))) }
        manifest.fetch("roots").each { |name, text| Paths.write_atomic(File.join(store, "roots", name), text) }
      end
      manifest
    rescue Zlib::Error, JSON::ParserError, KeyError, TypeError, ArgumentError => e
      raise Invalid, "#{file} is not a runtime bundle: #{e.message}"
    ensure
      FileUtils.rm_rf(staging) if staging
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

    # The manifest, after the format line. A bundle of another zr or of a
    # format that this zr does not read is refused.
    #: (Zlib::GzipReader gz) -> Hash[String, untyped]
    def header(gz)
      raise Invalid, "not a runtime bundle (no #{FORMAT} line)" unless gz.gets == "#{FORMAT}\n"

      manifest = JSON.parse(gz.gets.to_s)
      raise Invalid, "the manifest is no object" unless manifest.is_a?(Hash)
      raise Invalid, "the bundle is of zr #{manifest["zr"]}; this is zr #{VERSION}" unless manifest["zr"] == VERSION

      files = manifest.fetch("files")
      raise Invalid, "the manifest's files are no list of objects" unless files.is_a?(Array) && files.all?(Hash)

      files.each do |row|
        path = row.fetch("path")
        raise Invalid, "the bundle names #{path.inspect}, which is no entry of the store" unless path.is_a?(String) && path.match?(ENTRY)
      end
      roots = manifest.fetch("roots")
      raise Invalid, "the manifest's roots are no object of texts" unless roots.is_a?(Hash) && roots.values.all?(String)

      roots.each do |name, text|
        raise Invalid, "the bundle has a root #{name.inspect} of no target" unless root?(name)
        # A later export reads the entries that a root names.
        bad = text.lines(chomp: true).find { |line| !line.match?(ROOT_LINE) }
        raise Invalid, "the root #{name} names #{bad.inspect}, which is no entry of the store" if bad
      end
      manifest
    end

    # Whether `name` is the name of a root that a bundle holds.
    #: (String name) -> bool
    def root?(name)
      Target.all.any? { |target| name.start_with?(target.triple) && name.delete_prefix(target.triple).match?(ROOTS) }
    end

    # Reads the next file of the bundle into `staging`, and checks its
    # size and digest.
    #: (Zlib::GzipReader gz, Hash[String, untyped] row, String staging) -> void
    def stage(gz, row, staging)
      size = Integer(row.fetch("size"))
      digest = Digest::SHA256.new
      path = File.join(staging, row.fetch("path"))
      Paths.mkdir_p(File.dirname(path))
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |out|
        left = size
        while left.positive?
          chunk = gz.read([left, 1 << 20].min) or raise Invalid, "the bundle ends inside #{row["path"]}"
          digest << chunk
          out.write(chunk)
          left -= chunk.bytesize
        end
      end
      raise Invalid, "#{row["path"]} in the bundle does not match its digest" unless digest.hexdigest == row.fetch("sha256")
    end

    # Moves a staged file into the store, where the store lacks it. A file
    # that the store has is the same, by its key.
    #: (String from, String to) -> void
    def place(from, to)
      return if File.exist?(to)

      Paths.mkdir_p(File.dirname(to))
      File.chmod(0o644 & ~File.umask, from)
      File.rename(from, to)
    end
  end
end
