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

      # Returns the user's DEVELOPER_DIR and SDKROOT unchanged when set.
      def pinned
        chosen = ENV.slice("DEVELOPER_DIR", "SDKROOT")
        return chosen unless chosen.empty?

        out = IO.popen(["xcrun", "--show-sdk-path"], err: %i[child out], &:read)
        return {} unless $?.success?

        sdk = out.lines.map(&:strip).reverse.find { |line| line.start_with?("/") }
        return {} unless sdk && File.directory?(sdk)

        developer = developer_dir(sdk)
        developer && File.directory?(developer) ? { "DEVELOPER_DIR" => developer, "SDKROOT" => sdk } : {}
      rescue SystemCallError
        # No xcrun: not a macOS host, and nothing to pin.
        {}
      end

      # The developer directory that contains an SDK:
      # `/Library/Developer/CommandLineTools` for
      # `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`, and
      # `/Applications/Xcode.app/Contents/Developer` for an SDK under that
      # directory's `Platforms/MacOSX.platform/Developer/SDKs`.
      def developer_dir(sdk)
        dir = File.dirname(File.expand_path(sdk))
        return nil unless File.basename(dir) == "SDKs"

        dir = File.dirname(dir)
        if File.basename(dir) == "Developer" && File.basename(File.dirname(dir)).end_with?(".platform")
          dir = File.dirname(File.dirname(File.dirname(dir)))
        end
        dir
      end
    end
  end
end
