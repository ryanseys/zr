# frozen_string_literal: true

require_relative "config"

module Zr
  # A target that zr emits code for: its instruction set, its OS, its
  # object format, and the facts that a build reads from them. The gem
  # runs on any host. A target tells what it builds, and `refusal` tells
  # whether this host can build it.
  class Target
    attr_reader :triple, :arch, :os, :libc, :object_format, :word, :page, :symbol_prefix, :ruby_platform, :link, :outputs,
                :min_os

    # `outputs` are the outputs zr can build for the target: `:native`
    # (a binary), `:obj` (an object) and `:wasm` (a module). `min_os` is
    # the oldest OS version that a binary loads on ("14.0"), or nil when
    # the target records none.
    def initialize(triple:, arch:, os:, object_format:, page:, symbol_prefix:, ruby_platform:, link:, outputs:, libc: nil, word: 8,
                   min_os: nil)
      @triple = triple
      @arch = arch
      @os = os
      @libc = libc
      @object_format = object_format
      @word = word
      @page = page
      @symbol_prefix = symbol_prefix
      @ruby_platform = ruby_platform
      @link = link
      @outputs = outputs
      @min_os = min_os
    end

    def to_s = triple

    # The runtime layer that zr lowers with for each OS. runtime/kernel/os/,
    # runtime/core/os/ and runtime/ext/os/ each contain one directory per layer.
    OS_LAYERS = { darwin: "darwin", linux: "linux", wasi: "wasi" }.freeze
    # The machine layer, under runtime/kernel/arch/.
    ARCH_LAYERS = { aarch64: "aarch64", wasm32: "wasm32" }.freeze

    def os_layer = OS_LAYERS.fetch(os)
    def arch_layer = ARCH_LAYERS.fetch(arch)

    # Every target, by triple (`Target.register`).
    @registry = {}

    # The oldest macOS that a darwin binary loads on.
    MIN_MACOS = "14.0"

    # RUBY_PLATFORM of a darwin target. Ruby names the Darwin version of
    # the macOS that it was built for, and Darwin N is macOS N - 9. A
    # binary gives the platform of the oldest macOS that it loads on, as
    # ruby gives the platform that it was built for.
    def self.darwin_platform(min_os) = "arm64-darwin#{min_os.to_i + 9}"

    # `min_os` as the three numbers of a Mach-O LC_BUILD_VERSION.
    def min_os_parts = [*min_os.split(".").map(&:to_i), 0, 0].first(3)

    def self.register(target)
      @registry[target.triple] = target
    end

    AARCH64_DARWIN = register(new(triple: "aarch64-apple-darwin", arch: :aarch64, os: :darwin, object_format: :macho,
                                  page: 16_384, symbol_prefix: "_", ruby_platform: darwin_platform(MIN_MACOS),
                                  link: :darwin, outputs: %i[native obj], min_os: MIN_MACOS))
    AARCH64_LINUX_MUSL = register(new(triple: "aarch64-linux-musl", arch: :aarch64, os: :linux, libc: :musl,
                                      object_format: :elf, page: 4096, symbol_prefix: "", ruby_platform: "aarch64-linux-musl",
                                      link: :static, outputs: %i[native obj]))
    WASM32_WASI = register(new(triple: "wasm32-wasi", arch: :wasm32, os: :wasi, object_format: :wasm,
                               page: 65_536, symbol_prefix: "", ruby_platform: "wasm32-wasi",
                               link: nil, outputs: %i[wasm]))

    # The target with this `triple`, or nil.
    def self.fetch(triple) = @registry[triple]

    def self.all = @registry.values

    # This host as a triple: `aarch64-apple-darwin`, `aarch64-linux-musl`,
    # or what ruby says.
    def self.host_triple
      require "rbconfig"
      cpu = RbConfig::CONFIG["host_cpu"]
      os = RbConfig::CONFIG["host_os"]
      cpu = "aarch64" if cpu == "arm64"
      return "#{cpu}-apple-darwin" if os.start_with?("darwin")
      return "#{cpu}-linux-musl" if os.start_with?("linux-musl")

      "#{cpu}-#{os}"
    end

    # The target whose binaries this host runs, or nil.
    def self.host = fetch(host_triple) || all.find(&:runs_here?)

    # The target of a build that gives no target: the host's own, else
    # aarch64-apple-darwin.
    def self.default = host || AARCH64_DARWIN

    def native? = Target.host_triple == triple

    # Whether this host can run the target's native binary: its own target,
    # or a static musl binary on another Linux of the same machine.
    def runs_here? = native? || musl_on_linux?

    # Whether a program for this target can write machine code into
    # itself while it runs. Eval support does this. A wasm module's code
    # is fixed when the engine instantiates it, and WASI gives a guest no
    # way to make a second module. So there, eval uses the tree-walking
    # interpreter (lib/zr/eval/walk.rb).
    def jits? = arch != :wasm32

    # The output for `emit`: `:native` for nil, else the symbol.
    def self.output(emit) = emit ? emit.to_sym : :native

    # Whether this host can link a binary for this target. zr's own
    # Mach-O linker needs no tool on any host, unless `ZR_LINKER=cc`
    # selects the system linker. All other links run the target's C
    # compiler driver: the host's own or a cross toolchain's.
    def linkable?
      return true if link == :darwin && Config.current.linker != "cc"

      !tool("cc").nil?
    end

    # The command that this host runs for the target's tool `name`
    # ("cc"), or nil. On the target's own host, it is the plain tool.
    # On other hosts, it is a cross toolchain's tool, prefixed with the
    # triple as musl-cross and crosstool do (`aarch64-linux-musl-gcc`).
    #
    # A glibc Linux host of the same machine can link a musl binary with
    # musl's own wrapper (`musl-gcc`), or with the compiler that `$CC`
    # names.
    def tool(name)
      names = native? ? [name] : [name, *CROSS_NAMES[name]].map { |base| "#{triple}-#{base}" }
      names = [ENV["CC"], *names, *MUSL_NAMES[name]].compact.reject(&:empty?) if musl_on_linux?
      names.find { |command| Target.tool?(command) }
    end

    # Other names that a cross toolchain can use for a tool.
    CROSS_NAMES = { "cc" => %w[gcc] }.freeze
    # The names of musl's wrapper for a tool, on a host with another libc.
    MUSL_NAMES = { "cc" => %w[musl-gcc] }.freeze

    # Whether this is a musl target, and the host is another Linux of the
    # same machine.
    def musl_on_linux?
      return false unless libc == :musl && !native?

      Target.host_triple.start_with?("#{arch}-") && Target.host_triple.include?("-linux")
    end

    def self.tool?(name)
      return File.file?(name) && File.executable?(name) if name.include?("/")

      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
        path = File.join(dir, name)
        File.file?(path) && File.executable?(path)
      end
    end

    # How to get a C compiler on this host.
    def self.cc_hint(os_release: "/etc/os-release")
      return "xcode-select --install" if host_triple.end_with?("-darwin")

      id = File.file?(os_release) ? File.read(os_release)[/^ID(?:_LIKE)?="?([\w ]+)/, 1].to_s : ""
      return "apk add build-base" if id.include?("alpine")
      return "apt install musl-tools" if id.match?(/debian|ubuntu/)

      "install musl-gcc, or set CC to a C compiler for musl"
    end

    # nil when this host can build `emit` (nil for a native binary, "obj"
    # or "wasm") for this target, else the message a refusal prints.
    def refusal(emit)
      output = Target.output(emit)
      return "zr does not build #{output == :native ? "a native binary" : "--emit #{emit}"} for #{triple}" unless outputs.include?(output)
      return nil unless output == :native
      return nil if linkable?

      if native? || musl_on_linux?
        "a native binary needs cc on the PATH (#{Target.cc_hint}); " \
          "--emit wasm and --emit obj work without it"
      else
        "a native binary for #{triple} needs a #{triple} host with cc, or #{triple}-gcc " \
          "on the PATH; this host is #{Target.host_triple}; --emit obj works here"
      end
    end
  end
end
