# frozen_string_literal: true

require_relative "lib/zr/dev"
require_relative "../lib/zr/server"
require_relative "../lib/zr/gc_tuning"

module Zr
  module Dev
    # Keeps a warm compiler for the edit loop (lib/zr/server.rb). While it
    # runs, each `zr run` and `zr build` of this checkout gives it the
    # build, and runs the program itself. It stops after a time with no
    # request, and starts itself again when a file of zr changes.
    #
    #   zr-dev serve                 serve until 30 minutes pass with no request
    #   zr-dev serve --idle 120      ... 120 minutes
    #   zr-dev serve --socket PATH   listen at PATH (then set ZR_SERVER=PATH)
    #
    # `ZR_SERVER=0` makes a `zr` command build alone while a server runs.
    class Serve < Command
      summary "Keep a warm compiler that zr run and zr build of this checkout use"
      usage "[--idle MINUTES] [--socket PATH]"
      host_ruby!

      def defaults
        @idle = nil
        @socket = nil
      end

      def options(o)
        o.on("--idle MINUTES", Integer, "stop after this many minutes with no request (default 30)") { |v| @idle = v }
        o.on("--socket PATH", "listen at PATH, not at the cache's server.sock") { |v| @socket = v }
      end

      def run(_argv)
        # The builds are forks of this process, so it needs the collector
        # limits itself: it starts again with them, then turns YJIT on.
        Zr::GcTuning.now($PROGRAM_NAME, ARGV)
        Zr::Server.serve(path: @socket || Zr::Server.socket, idle: (@idle || 30) * 60)
        true
      end
    end
  end
end
