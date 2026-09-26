# frozen_string_literal: true

require "rbconfig"
require_relative "version"
require_relative "paths"
require_relative "target"

module Zr
  # `zr doctor`: what zr needs on this host, checked one by one. Each
  # check gives a status (`:ok`, `:warn` or `:fail`), a name and one line
  # of detail. Only a `:fail` stops a build; a `:warn` limits what zr can
  # do here.
  module Doctor
    Check = Data.define(:status, :name, :detail)

    module_function

    def checks = [ruby, host, wasmtime, openssl, gems, cache, compiled_compiler]

    # Prints each check. Returns true when none failed.
    def run(out = $stdout)
      results = checks
      results.each { |c| out.puts format("%-5s %-18s %s", c.status, c.name, c.detail) }
      results.none? { |c| c.status == :fail }
    end

    def ruby(version = RUBY_VERSION)
      return Check.new(:ok, "ruby", "#{version}, the ruby zr #{VERSION} pins") if version == RUBY

      Check.new(:fail, "ruby", "#{version}; zr #{VERSION} builds only on ruby #{RUBY}")
    end

    def host(triple = Target.host_triple)
      target = Target.fetch(triple)
      native = target&.outputs&.include?(:native) && target.linkable?
      builds = Target.all.select { |t| t.outputs.any? { |o| t.refusal(o == :native ? nil : o.to_s).nil? } }.map(&:triple)
      detail = "#{triple}; builds for #{builds.join(", ")}"
      return Check.new(:ok, "host", "#{detail}; runs its own binaries") if native

      Check.new(:warn, "host", "#{detail}; `zr run` needs --emit wasm here")
    end

    def wasmtime(path = which("wasmtime"))
      return Check.new(:ok, "wasmtime", path) if path

      Check.new(:warn, "wasmtime", "not on PATH; `zr run --emit wasm` needs it (https://wasmtime.dev)")
    end

    # The places a macOS binary looks for OpenSSL 3 when a program
    # requires openssl (runtime/ext/openssl/ossl/library.rb).
    def openssl(env = ENV)
      return Check.new(:ok, "openssl", "not needed on this host") unless Target.host_triple.end_with?("darwin")

      prefix = env["OPENSSL_DIR"]
      dirs = prefix && !prefix.empty? ? [File.join(prefix, "lib")] : %w[/opt/homebrew/opt/openssl@3/lib /usr/local/opt/openssl@3/lib /opt/local/lib]
      found = dirs.map { |dir| File.join(dir, "libssl.3.dylib") }.find { |path| File.exist?(path) }
      return Check.new(:ok, "openssl", found) if found

      Check.new(:warn, "openssl", "no OpenSSL 3 in #{dirs.join(", ")}; only a program that requires openssl needs it")
    end

    def gems
      require_relative "libraries"
      Check.new(:ok, "pinned gems", "#{Libraries::PINS.size + Libraries::HOST.size} libraries in #{Libraries.root}")
    rescue Libraries::Unresolved => e
      Check.new(:fail, "pinned gems", e.message)
    end

    def cache
      require_relative "cache"
      dir = Paths.cache
      Paths.mkdir_p(dir)
      return Check.new(:fail, "cache", "#{dir} is not writable") unless File.writable?(dir)

      Check.new(:ok, "cache", format("%s, %d MB (`zr cache clean` frees it)", dir, Cache.megabytes(Cache.all)))
    rescue SystemCallError => e
      Check.new(:fail, "cache", "#{dir}: #{e.message}")
    end

    def compiled_compiler(env = ENV)
      require_relative "compiled_compiler"
      cc = CompiledCompiler
      state = if env["ZR_COMPILED"] == "0" then "off (ZR_COMPILED=0); ruby runs every build"
              elsif !cc.runnable? then "not for this host; ruby runs every build"
              elsif cc.current? then "current: #{cc.binary}"
              elsif cc.program.failed? then "its last build failed; ZR_COMPILED=1 tries again"
              elsif Paths.checkout? then "not built; `rake build:self` builds it"
              else "not built yet; the first build makes it (some minutes)"
              end
      Check.new(:ok, "compiled compiler", state)
    end

    # The path of `command` on PATH, or nil.
    def which(command)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, command) }
         .find { |path| File.file?(path) && File.executable?(path) }
    end
  end
end
