# frozen_string_literal: true

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
      def env
        @env ||= pinned
      end

      # The command for the tool `name` ("cc") of `target`: the host's
      # tool or a cross toolchain's tool. Else the plain name; if it fails
      # to run, its error tells what is missing.
      def command(target, name) = target.tool(name) || name

      # Runs `argv` under `env`. Returns `[output, success]`; the output
      # contains stdout and stderr together.
      def run(argv)
        log = IO.popen(env, argv, err: %i[child out], &:read)
        [log, $?.success?]
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
      def pinned
        chosen = ENV.slice("DEVELOPER_DIR", "SDKROOT")
        return chosen unless chosen.empty?

        developer = selected_developer_dir
        sdk = developer && SDKS.map { |path| File.join(developer, path) }.find { |path| File.directory?(path) }
        sdk ? { "DEVELOPER_DIR" => developer, "SDKROOT" => sdk } : {}
      end

      def selected_developer_dir
        File.realpath(SELECTED)
      rescue SystemCallError
        File.directory?(TOOLS) ? TOOLS : nil
      end
    end
  end
end
