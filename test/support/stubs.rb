# frozen_string_literal: true

module Zr
  module Test
    # Stand-ins for a test, since minitest 6 has no minitest/mock.
    # test_helper includes this module in every test.
    module Stubs
      # Replaces the singleton method `owner.name` with `answer` while the
      # block runs. A callable answer is called with the method's
      # arguments; any other answer is returned as it is.
      def stub_method(owner, name, answer)
        was = owner.method(name)
        owner.define_singleton_method(name) { |*args, **kw| answer.respond_to?(:call) ? answer.call(*args, **kw) : answer }
        yield
      ensure
        owner.define_singleton_method(name, was)
      end

      # Sets the environment variables in `pairs` while the block runs,
      # and puts the old values back after. A nil value unsets one.
      def with_env(pairs)
        was = pairs.to_h { |name, _| [name, ENV.fetch(name, nil)] }
        pairs.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
        yield
      ensure
        was.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
      end
    end
  end
end
