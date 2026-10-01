# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require "open3"
require "rbconfig"
require "socket"
require "tmpdir"
require "zr/server"

# `zr-dev serve` builds for `zr run` and `zr build` (lib/zr/server.rb). The
# client runs the program itself, so the program's output, status and
# arguments are what they are without the server. The server builds only
# what the client would build alone: another ruby, other ruby options or
# a change to zr's own files make it answer "fall back".
class ServerTest < Minitest::Test
  Server = Zr::Server
  ROOT = File.expand_path("../..", __dir__)

  def test_a_message_goes_through_a_pipe
    reader, writer = IO.pipe
    Server::Client.put(writer, { argv: %w[run a.rb], env: { "A" => "1" } })
    assert_equal({ argv: %w[run a.rb], env: { "A" => "1" } }, Server::Client.take(reader))
  end

  def test_the_server_builds_only_what_the_client_would
    server = Server.new(path: nil, log: nil)
    server.instance_variable_set(:@stamps, server.stamps)
    assert_nil server.refusal(request)
    assert_equal "another protocol", server.refusal(request.merge(version: 0))
    assert_equal "another ruby", server.refusal(request.merge(ruby_version: "3.0.0"))
    assert_equal "another RUBYOPT", server.refusal(request(env: ENV.to_h.merge("RUBYOPT" => "-rsomething")))
    server.instance_variable_set(:@stamps, {})
    assert_equal "zr changed", server.refusal(request)
  end

  def test_only_a_run_or_a_build_goes_to_the_server
    client = Server::Client.new
    Dir.mktmpdir("zr-sock-") do |dir|
      path = File.join(dir, "s.sock")
      UNIXServer.open(path) do
        Zr::Config.with(ZR_SERVER: path) do
          assert_equal path, client.client_socket(%w[run a.rb])
          assert_equal path, client.client_socket(%w[build a.rb -o a])
          assert_nil client.client_socket(%w[run --emit wasm a.rb]), "wasmtime runs a module; the client does not"
          assert_nil client.client_socket(%w[version])
        end
        Zr::Config.with(ZR_SERVER: "0") { assert_nil client.client_socket(%w[run a.rb]) }
      end
      File.delete(path)
      Zr::Config.with(ZR_SERVER: path) { assert_nil client.client_socket(%w[run a.rb]), "no socket, no server" }
    end
  end

  # One server: a run with arguments and an exit status, and a build. A
  # usage error stops in the client, before any request.
  def test_a_server_builds_and_the_client_runs
    skip "a native link on this host only" unless Zr::Target.default.link

    Dir.mktmpdir("zr-serve-") do |dir|
      socket = File.join(dir, "s.sock")
      log = File.join(dir, "log")
      server = spawn(RbConfig.ruby, File.join(ROOT, "tool/zr-dev.rb"), "serve", "--socket", socket, "--idle", "2",
                     out: log, err: log, pgroup: true)
      begin
        ready(log)
        program = File.join(dir, "p.rb")
        # A new comment each time, so the run cache does not answer.
        File.write(program, "p ARGV\nexit 3\n# #{rand(1 << 60)}\n")
        env = { "ZR_SERVER" => socket }

        out, err, status = Open3.capture3(env, RbConfig.ruby, File.join(ROOT, "exe/zr"), "run", program, "a b")
        assert_equal ["[\"a b\"]\n", 3], [out, status.exitstatus], err

        _, err, status = Open3.capture3(env, RbConfig.ruby, File.join(ROOT, "exe/zr"), "build", program, "-o", File.join(dir, "p"))
        assert_predicate status, :success?, err
        assert File.executable?(File.join(dir, "p"))

        _, err, status = Open3.capture3(env, RbConfig.ruby, File.join(ROOT, "exe/zr"), "run", "--bogus", program)
        assert_equal 2, status.exitstatus
        assert_includes err, "unknown option '--bogus'"

        served = File.read(log).lines.grep(/p\.rb/)
        assert_equal 2, served.size, File.read(log)
      ensure
        Process.kill(:TERM, -server)
        Process.wait(server)
      end
    end
  end

  private

  def request(env: ENV.to_h, **rest)
    { version: Server::VERSION, argv: %w[run a.rb], cwd: Dir.pwd, env: env, ruby: RbConfig.ruby, ruby_version: RUBY_VERSION }.merge(rest)
  end

  # Waits until the server listens, or fails with its log.
  def ready(log)
    120.times do
      return if File.exist?(log) && File.read(log).include?("listening")

      sleep 1
    end
    flunk "the server did not start: #{File.exist?(log) ? File.read(log) : "no log"}"
  end
end
