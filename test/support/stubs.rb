# frozen_string_literal: true

require_relative "../../lib/zr/session"

module Zr
  module Test
    # Stub helpers for tests, because minitest 6 does not include
    # minitest/mock. test_helper includes this module in every test.
    module Stubs
      # Replaces the singleton method `owner.name` with `answer` while the
      # block runs. If `answer` is callable, the stub calls it with the
      # arguments of the method. Otherwise the stub returns `answer`.
      def stub_method(owner, name, answer)
        was = owner.method(name)
        owner.define_singleton_method(name) { |*args, **kw| answer.respond_to?(:call) ? answer.call(*args, **kw) : answer }
        yield
      ensure
        owner.define_singleton_method(name, was)
      end

      # Sets the environment variables in `pairs` while the block runs,
      # and puts the old values back after. A nil value unsets one. The
      # session reads the settings again in the block and after it
      # (`Session#reset!`), as a new zr would.
      def with_env(pairs)
        was = pairs.to_h { |name, _| [name, ENV.fetch(name, nil)] }
        pairs.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
        Session.current.reset!(keep_runtimes: true)
        yield
      ensure
        was.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
        Session.current.reset!(keep_runtimes: true)
      end
    end
  end
end
