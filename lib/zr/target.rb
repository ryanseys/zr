# frozen_string_literal: true

require_relative "config"

module Zr
  # A target that zr emits code for: its instruction set, its OS, its
  # object format, and the facts that a build reads from them. The gem
  # runs on any host. A target tells what it builds, and `refusal` tells
  # whether this host can build it.
  #
  # `outputs` are the outputs zr can build for the target: `:native` (a
  # binary), `:obj` (an object) and `:wasm` (a module). `min_os` is the
  # oldest OS version that a binary loads on ("14.0"), or nil when the
  # target records none.
  # @rbs skip -- typed in sig/zr/target.rbs
  Target = Data.define(:triple, :arch, :os, :libc, :object_format, :word, :page, :symbol_prefix, :ruby_platform, :link, :outputs,
                       :min_os)

  class Target
    # @rbs triple: String
    # @rbs arch: arch
    # @rbs os: os
    # @rbs object_format: object_format
    # @rbs page: Integer
    # @rbs symbol_prefix: String
    # @rbs ruby_platform: String
    # @rbs link: link?
    # @rbs outputs: Array[output]
    # @rbs libc: libc?
    # @rbs word: Integer
    # @rbs min_os: String?
    # @rbs return: void
    def initialize(triple:, arch:, os:, object_format:, page:, symbol_prefix:, ruby_platform:, link:, outputs:, libc: nil, word: 8,
                   min_os: nil)
      super
    end

    #: () -> String
    def to_s = triple

    # The runtime layer that zr lowers with for each OS. lib/zr/runtime/kernel/os/,
    # lib/zr/runtime/core/os/ and lib/zr/runtime/ext/os/ each contain one directory per layer.
    OS_LAYERS = { darwin: "darwin", linux: "linux", wasi: "wasi" }.freeze #: Hash[os, String]
    # The machine layer, under lib/zr/runtime/kernel/arch/.
    ARCH_LAYERS = { aarch64: "aarch64", x86_64: "x86_64", wasm32: "wasm32" }.freeze #: Hash[arch, String]

    #: () -> String
    def os_layer = OS_LAYERS.fetch(os)

    # The extension of a C extension's library, which a require of
    # `parser.so` finds as ruby's does: `bundle` on darwin, `so` elsewhere.
    #: () -> String
    def dlext = os == :darwin ? "bundle" : "so"

    #: () -> String
    def arch_layer = ARCH_LAYERS.fetch(arch)

    # The oldest macOS that a darwin binary loads on.
    MIN_MACOS = "14.0"

    # RUBY_PLATFORM of a darwin target. Ruby names the Darwin version of
    # the macOS that it was built for, and Darwin N is macOS N - 9. A
    # binary gives the platform of the oldest macOS that it loads on, as
    # ruby gives the platform that it was built for.
    #: (String min_os) -> String
    def self.darwin_platform(min_os) = "arm64-darwin#{min_os.to_i + 9}"

    # `min_os` as the three numbers of a Mach-O LC_BUILD_VERSION.
    #: () -> Array[Integer]
    def min_os_parts = [*(min_os or raise("#{triple} has no min_os")).split(".").map(&:to_i), 0, 0].first(3)

    AARCH64_DARWIN = new(triple: "aarch64-apple-darwin", arch: :aarch64, os: :darwin, object_format: :macho,
                         page: 16_384, symbol_prefix: "_", ruby_platform: darwin_platform(MIN_MACOS),
                         link: :darwin, outputs: %i[native obj], min_os: MIN_MACOS) #: Target
    AARCH64_LINUX_MUSL = new(triple: "aarch64-linux-musl", arch: :aarch64, os: :linux, libc: :musl,
                             object_format: :elf, page: 4096, symbol_prefix: "", ruby_platform: "aarch64-linux-musl",
                             link: :static, outputs: %i[native obj]) #: Target
    X86_64_LINUX_MUSL = new(triple: "x86_64-linux-musl", arch: :x86_64, os: :linux, libc: :musl,
                            object_format: :elf, page: 4096, symbol_prefix: "", ruby_platform: "x86_64-linux-musl",
                            link: :static, outputs: %i[native obj]) #: Target
    # The glibc targets link dynamically: ld.so loads libc, and dlopen
    # loads C extensions and FFI libraries. ruby names their platform
    # with no C library.
    X86_64_LINUX_GNU = new(triple: "x86_64-linux-gnu", arch: :x86_64, os: :linux, libc: :glibc,
                           object_format: :elf, page: 4096, symbol_prefix: "", ruby_platform: "x86_64-linux",
                           link: :dynamic, outputs: %i[native obj]) #: Target
    AARCH64_LINUX_GNU = new(triple: "aarch64-linux-gnu", arch: :aarch64, os: :linux, libc: :glibc,
                            object_format: :elf, page: 4096, symbol_prefix: "", ruby_platform: "aarch64-linux",
                            link: :dynamic, outputs: %i[native obj]) #: Target
    WASM32_WASI = new(triple: "wasm32-wasi", arch: :wasm32, os: :wasi, object_format: :wasm,
                      page: 65_536, symbol_prefix: "", ruby_platform: "wasm32-wasi",
                      link: nil, outputs: %i[wasm]) #: Target

    # Every target.
    ALL = [AARCH64_DARWIN, AARCH64_LINUX_MUSL, X86_64_LINUX_MUSL, X86_64_LINUX_GNU, AARCH64_LINUX_GNU, WASM32_WASI].freeze #: Array[Target]
    # Every target, by triple.
    BY_TRIPLE = ALL.to_h { |target| [target.triple, target] }.freeze #: Hash[String, Target]

    # How far CI checks each target: `:tested` runs its program tests in
    # CI, `:experimental` builds and runs only a slice there.
    # tool/gen/targets.rb writes the tables of the README and of
    # docs/reference/targets.md from it.
    SUPPORT = { "aarch64-apple-darwin" => :tested, "aarch64-linux-musl" => :tested, "wasm32-wasi" => :tested,
                "x86_64-linux-musl" => :experimental, "x86_64-linux-gnu" => :experimental,
                "aarch64-linux-gnu" => :experimental }.freeze #: Hash[String, :tested | :experimental]

    #: () -> (:tested | :experimental)
    def support = SUPPORT.fetch(triple)

    # Whether a binary for this target can link a gem's own C extension
    # (`--native-ext`): every target that builds a binary.
    #: () -> bool
    def native_ext? = outputs.include?(:native)

    # The target with this `triple`, or nil.
    #: (String triple) -> Target?
    def self.fetch(triple) = BY_TRIPLE[triple]

    #: () -> Array[Target]
    def self.all = ALL

    # This host as a triple: `aarch64-apple-darwin`, `aarch64-linux-musl`,
    # `x86_64-linux-gnu`, or what ruby says. An x86_64 ruby that Rosetta runs on an Apple
    # Silicon Mac is on an aarch64 host, which runs zr's binaries.
    #: () -> String
    def self.host_triple
      require "rbconfig"
      cpu = RbConfig::CONFIG.fetch("host_cpu")
      os = RbConfig::CONFIG.fetch("host_os")
      cpu = "aarch64" if cpu == "arm64" || (cpu == "x86_64" && os.start_with?("darwin") && rosetta?)
      return "#{cpu}-apple-darwin" if os.start_with?("darwin")
      return "#{cpu}-linux-musl" if os.start_with?("linux-musl")
      # A glibc ruby says `linux-gnu`, or `linux` where it was configured
      # with no libc in its host (setup-ruby's builds).
      return "#{cpu}-linux-gnu" if os == "linux" || os.start_with?("linux-gnu")

      "#{cpu}-#{os}"
    end

    # Whether Rosetta translates this process (`sysctl.proc_translated`).
    #: () -> bool
    def self.rosetta?
      Session.current.memo(:rosetta) do
        IO.popen(%w[sysctl -n sysctl.proc_translated], err: File::NULL, &:read).strip == "1"
      rescue SystemCallError
        false
      end
    end

    # Whether this host is Windows, where zr does not run.
    #: () -> bool
    def self.windows?
      require "rbconfig"
      RbConfig::CONFIG.fetch("host_os").match?(/mswin|mingw|cygwin/)
    end

    # The target whose binaries this host runs, or nil.
    #: () -> Target?
    def self.host = fetch(host_triple) || all.find(&:runs_here?)

    # The target of a build that gives no target: the host's own, else
    # aarch64-apple-darwin.
    #: () -> Target
    def self.default = host || AARCH64_DARWIN

    #: () -> bool
    def native? = Target.host_triple == triple

    # Whether this host can run the target's native binary: its own target,
    # or a static musl binary on another Linux of the same machine.
    #: () -> bool
    def runs_here? = native? || musl_on_linux?

    # Whether a program for this target can write machine code into
    # itself while it runs. Eval support does this. A wasm module's code
    # is fixed when the engine instantiates it, and WASI gives a guest no
    # way to make a second module. So there, eval uses the tree-walking
    # interpreter (lib/zr/eval/interpreter.rb).
    #: () -> bool
    def jits? = arch != :wasm32

    # The output for `emit`: `:native` for nil, else the symbol.
    #: (String | Symbol | nil emit) -> Symbol
    def self.output(emit) = emit ? emit.to_sym : :native

    # Whether this host can link a binary for this target. zr's own
    # Mach-O linker needs no tool on any host, unless `ZR_LINKER=cc`
    # selects the system linker. All other links run the target's C
    # compiler driver: the host's own or a cross toolchain's.
    #: () -> bool
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
    #: (String name) -> String?
    def tool(name)
      names = native? ? [name] : [name, *CROSS_NAMES[name]].map { |base| "#{triple}-#{base}" }
      names = [ENV["CC"], *names, *MUSL_NAMES[name]].compact.reject(&:empty?) if musl_on_linux?
      names.find { |command| Target.tool?(command) }
    end

    # Other names that a cross toolchain can use for a tool.
    CROSS_NAMES = { "cc" => %w[gcc], "c++" => %w[g++] }.freeze #: Hash[String, Array[String]]
    # The names of musl's wrapper for a tool, on a host with another libc.
    MUSL_NAMES = { "cc" => %w[musl-gcc] }.freeze #: Hash[String, Array[String]]

    # Whether this is a musl target, and the host is another Linux of the
    # same machine.
    #: () -> bool
    def musl_on_linux?
      return false unless libc == :musl && !native?

      Target.host_triple.start_with?("#{arch}-") && Target.host_triple.include?("-linux")
    end

    # Whether `name` is a tool that this host can run.
    #: (String name) -> bool
    def self.tool?(name) = !which(name).nil?

    # The path of the executable `name`, or nil. A name with a `/` is a
    # path; any other name is looked for on PATH.
    #: (String name) -> String?
    def self.which(name)
      return (name if File.file?(name) && File.executable?(name)) if name.include?("/")

      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }
         .find { |path| File.file?(path) && File.executable?(path) }
    end

    # How to get a C compiler on this host for a target with `libc`.
    #: (?os_release: String, ?libc: libc?) -> String
    def self.cc_hint(os_release: "/etc/os-release", libc: :musl)
      return "xcode-select --install" if host_triple.end_with?("-darwin")

      id = File.file?(os_release) ? File.read(os_release)[/^ID(?:_LIKE)?="?([\w ]+)/, 1].to_s : ""
      return "apk add build-base" if id.include?("alpine")
      return libc == :glibc ? "apt install build-essential" : "apt install musl-tools" if id.match?(/debian|ubuntu/)

      "install musl-gcc, or set CC to a C compiler for musl"
    end

    # nil when this host can build `emit` (nil for a native binary, "obj"
    # or "wasm") for this target, else the message a refusal prints.
    #: (String | Symbol | nil emit) -> String?
    def refusal(emit)
      output = Target.output(emit)
      return "zr does not build #{output == :native ? "a native binary" : "--emit #{emit}"} for #{triple}" unless outputs.include?(output)
      return nil unless output == :native
      return nil if linkable?

      if native? || musl_on_linux?
        "a native binary needs cc on the PATH (#{Target.cc_hint(libc: libc)}); " \
          "--emit wasm and --emit obj work without it"
      else
        "a native binary for #{triple} needs a #{triple} host with cc, or #{triple}-gcc " \
          "on the PATH; this host is #{Target.host_triple}; --emit obj works here"
      end
    end
  end
end
