# frozen_string_literal: true

require_relative "../session"

module Zr
  module Native
    # The C toolchain that zr runs: the target's `cc` (`Target#tool`), to link.
    #
    # On macOS, `cc` finds its SDK and its `ld` in two ways that can
    # differ. Clang uses the newest SDK that it finds, and `ld` comes from
    # the developer directory that `xcode-select` gives. An Xcode older
    # than the Command Line Tools can pair an `ld` with an SDK whose `.tbd`
    # files it cannot read ("tapi error: malformed file"). Thus every tool
    # runs with DEVELOPER_DIR and SDKROOT set to the install that contains
    # the SDK. When the user already set DEVELOPER_DIR or SDKROOT, zr
    # keeps those values.
    module Toolchain
      module_function

      # The environment a `cc` runs under.
      #: () -> Hash[String, String?]
      def env
        Session.current.memo(:toolchain_env) { pinned }
      end

      # The command for the tool `name` ("cc") of `target`: the host's
      # tool or a cross toolchain's tool. Else the plain name; if it fails
      # to run, its error tells what is missing.
      #: (Target target, String name) -> String
      def command(target, name) = target.tool(name) || name

      # `-fuse-ld=mold` when mold is on PATH, else nothing. An ELF link
      # reads the whole runtime object, tens of thousands of sections
      # (one for each function and datum), and GNU ld took most of a
      # program test's time on Linux; mold reads them in parallel.
      #: () -> Array[String]
      def elf_linker_flags
        Session.current.memo(:elf_linker_flags) do
          found = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, "mold")) }
          found ? ["-fuse-ld=mold"] : []
        end
      end

      # Runs `argv` under `env`. Returns `[output, success]`; the output
      # contains stdout and stderr together.
      #: (Array[String] argv) -> [String, bool]
      def run(argv)
        log = IO.popen(env, argv, err: %i[child out], &:read)
        # `IO.popen` with a block waits for the child, so `$?` is set.
        status = $? #: Process::Status
        [log, status.success?]
      end

      # The developer directory that `xcode-select` chose: its link, else
      # the Command Line Tools.
      SELECTED = "/var/db/xcode_select_link"
      TOOLS = "/Library/Developer/CommandLineTools"

      # The macOS SDK in a developer directory: an Xcode's, or the Command
      # Line Tools'.
      SDKS = %w[Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk SDKs/MacOSX.sdk].freeze

      # Returns the user's DEVELOPER_DIR and SDKROOT unchanged when set.
      # Else the developer directory that `xcode-select` chose and its
      # SDK, which is what `xcrun --show-sdk-path` gives, read without
      # starting xcrun. On a host with neither, nothing is pinned.
      #: () -> Hash[String, String?]
      def pinned
        chosen = ENV.slice("DEVELOPER_DIR", "SDKROOT")
        return chosen unless chosen.empty?

        developer = selected_developer_dir
        sdk = developer && SDKS.map { |path| File.join(developer, path) }.find { |path| File.directory?(path) }
        sdk ? { "DEVELOPER_DIR" => developer, "SDKROOT" => sdk } : {}
      end

      #: () -> String?
      def selected_developer_dir
        File.realpath(SELECTED)
      rescue SystemCallError
        File.directory?(TOOLS) ? TOOLS : nil
      end
    end
  end
end
