# frozen_string_literal: true

module Zr
  module Native
    # The C toolchain zr runs: `cc` to link, the target's own
    # (`Target#tool`).
    #
    # On macOS `cc` finds its SDK and its `ld` on two roads that can part:
    # clang takes the newest SDK it finds, and `ld` comes from the
    # developer directory `xcode-select` names. An Xcode older than the
    # Command Line Tools pairs an `ld` with an SDK whose `.tbd` files it
    # cannot read ("tapi error: malformed file"). So every tool runs with
    # DEVELOPER_DIR and SDKROOT pinned to the one install the SDK comes
    # from. A DEVELOPER_DIR or SDKROOT already set is the user's choice,
    # and stands.
    module Toolchain
      module_function

      # The environment a `cc` runs under.
      def env
        @env ||= pinned
      end

      # The command `target`'s `name` ("cc") runs as: the host's
      # own or a cross toolchain's, else the plain name, whose failure to
      # run says what is missing.
      def command(target, name) = target.tool(name) || name

      # Runs `argv` under `env`: `[output, success]`, both streams in one.
      def run(argv)
        log = IO.popen(env, argv, err: %i[child out], &:read)
        [log, $?.success?]
      end

      # The user's own DEVELOPER_DIR and SDKROOT come back as they are.
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

      # The developer directory an SDK belongs to:
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
