# frozen_string_literal: true

module Ze0
  # The targets ze0 emits, and what this host can build. The gem runs on
  # any host: a wasm module and a Mach-O object are Ruby all the way, but
  # a native binary links through `cc` against archives only an
  # aarch64-apple-darwin host builds.
  module Target
    AARCH64_DARWIN = "aarch64-apple-darwin"
    WASM32_WASI = "wasm32-wasi"

    module_function

    # This host as a triple: `aarch64-apple-darwin`, or what ruby says.
    def host
      require "rbconfig"
      cpu = RbConfig::CONFIG["host_cpu"]
      os = RbConfig::CONFIG["host_os"]
      cpu = "aarch64" if cpu == "arm64"
      os.start_with?("darwin") ? "#{cpu}-apple-darwin" : "#{cpu}-#{os}"
    end

    def native? = host == AARCH64_DARWIN

    # Whether this host can link a native binary: the right host, with
    # `cc` and `ar` on the PATH.
    def linkable?
      native? && %w[cc ar].all? { |tool| tool?(tool) }
    end

    def tool?(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
        path = File.join(dir, name)
        File.file?(path) && File.executable?(path)
      end
    end

    # nil when this host can build `emit` (`nil` for a native binary,
    # "obj" or "wasm"), else the message a refusal prints.
    def refusal(emit)
      return nil if %w[obj wasm].include?(emit)
      return nil if linkable?

      if native?
        "a native binary needs cc and ar on the PATH (xcode-select --install); " \
          "--emit wasm and --emit obj work without them"
      else
        "a native binary needs an #{AARCH64_DARWIN} host with cc; this host is #{host}; " \
          "--emit wasm and --emit obj work here"
      end
    end
  end
end
