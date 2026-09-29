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
      return Check.new(:ok, "ruby", version) if version == RUBY
      return Check.new(:warn, "ruby", "#{version}; zr is tested with #{RUBY}") if Zr.supported_ruby?(version)

      Check.new(:fail, "ruby", "#{version}; zr needs #{RUBY} or a later 4.0 release")
    end

    def host(triple = Target.host_triple)
      target = Target.fetch(triple)
      native = target&.outputs&.include?(:native) && target.linkable?
      return Check.new(:ok, "host", triple) if native

      Check.new(:warn, "host", "#{triple}; no native binaries, use --emit wasm")
    end

    def wasmtime(path = which("wasmtime"))
      return Check.new(:ok, "wasmtime", path) if path

      Check.new(:warn, "wasmtime", "not on PATH")
    end

    # The places a macOS binary looks for OpenSSL 3 when a program
    # requires openssl (runtime/ext/openssl/ossl/library.rb).
    def openssl(env = ENV)
      return Check.new(:ok, "openssl", "not needed") unless Target.host_triple.end_with?("darwin")

      prefix = env["OPENSSL_DIR"]
      dirs = prefix && !prefix.empty? ? [File.join(prefix, "lib")] : %w[/opt/homebrew/opt/openssl@3/lib /usr/local/opt/openssl@3/lib /opt/local/lib]
      found = dirs.map { |dir| File.join(dir, "libssl.3.dylib") }.find { |path| File.exist?(path) }
      return Check.new(:ok, "openssl", found) if found

      Check.new(:warn, "openssl", "not found")
    end

    def gems
      require_relative "libraries"
      require_relative "ports"
      missing = Libraries.roots.flatten.reject { |dir| File.directory?(dir) }
      return Check.new(:fail, "libraries", "#{missing.first} is missing; reinstall zr (gem install zr)") unless missing.empty?

      Check.new(:ok, "libraries", "stdlib of ruby #{RUBY} (#{Stdlib::DEFAULT.size + Stdlib::BUNDLED.size} gems), #{Ports::ALL.size} ports")
    end

    def cache
      require_relative "cache"
      dir = Paths.cache
      Paths.mkdir_p(dir)
      return Check.new(:fail, "cache", "#{dir} is not writable") unless File.writable?(dir)

      Check.new(:ok, "cache", format("%s, %d MB", dir, Cache.megabytes(Cache.all)))
    rescue SystemCallError => e
      Check.new(:fail, "cache", "#{dir}: #{e.message}")
    end

    def compiled_compiler(env = ENV)
      require_relative "compiled_compiler"
      cc = CompiledCompiler
      state = if env["ZR_COMPILED"] == "0" then "off"
              elsif !cc.runnable? then "not for this host"
              elsif cc.current? then "current"
              elsif cc.program.failed? then "last build failed"
              elsif Paths.checkout? then "not built"
              else "not built"
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
