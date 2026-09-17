# frozen_string_literal: true

# rt/ext/openssl/ossl/native.rb over Fiddle, so the port runs on ruby
# itself: tools/openssl/host.rb loads it in place of the kernel's calls.
require "fiddle"

module OpenSSL
  module Native
    RTLD_NOW = 2
    RTLD_LOCAL = RUBY_PLATFORM.include?("darwin") ? 4 : 0
    WORD = Fiddle::TYPE_INTPTR_T

    class << self
      def open(path)
        @error = nil
        Fiddle::Handle.new(path, RTLD_NOW | RTLD_LOCAL)
      rescue Fiddle::DLError => e
        @error = e.message
        nil
      end

      def error = @error.to_s

      def symbol(handle, name) = handle.sym_defined?(name) ? handle.sym(name) : 0

      # A callback that raised left its exception, which cannot unwind
      # through C's frames; it raises here once C returns, as the kernel's
      # calls do.
      def call(address, words) = resume { function(address, words.size).call(*words.map { |w| w.is_a?(Fiddle::Pointer) ? w.to_i : w }) }

      def call_errno(address, words)
        answer = call(address, words)
        [answer, Fiddle.last_error]
      end

      def call_double(address, words, float)
        function = (@functions ||= {})[[address, words.size, :double]] ||= Fiddle::Function.new(address, [WORD] * words.size + [Fiddle::TYPE_DOUBLE], WORD)
        resume { function.call(*words.map { |w| w.is_a?(Fiddle::Pointer) ? w.to_i : w }, float) }
      end

      def address(string) = Fiddle::Pointer[string].to_i

      # A NUL-ended copy, kept alive by the argument list that holds it:
      # a String's bytes on ruby end in a NUL only when it owns them.
      def cstring(string) = Fiddle::Pointer["#{string}\0".b]

      def read(address, length) = Fiddle::Pointer.new(address)[0, length].b

      def strlen(address) = Fiddle::Pointer.new(address).to_s.bytesize

      def write(address, string) = Fiddle::Pointer.new(address)[0, string.bytesize] = string

      def callback(index)
        @closures ||= {}
        @closures[index] ||= Fiddle::Closure::BlockCaller.new(WORD, [WORD] * 7) do |*args|
          answer = begin
            @dispatch.call(index, args)
          rescue Exception => e # rubocop:disable Lint/RescueException
            @unwind = e
            0
          end
          answer.is_a?(Integer) ? answer : 0
        end
        @closures[index].to_i
      end

      def dispatch(callable) = @dispatch = callable

      # ruby has no hidden instance variables, so these are plain ones
      # with a name no program uses.
      def hidden_get(object, key) = object.instance_variable_get(:"@__ossl_#{key}__")

      def hidden_set(object, key, value) = object.instance_variable_set(:"@__ossl_#{key}__", value)

      PORT = File.expand_path("../../rt/ext/openssl", __dir__)
      FIDDLE = File.dirname(Fiddle::Closure::BlockCaller.instance_method(:call).source_location.first)

      # The port's frames, and the twin's and Fiddle's under it.
      def internal_path?(path) = path.start_with?(PORT, __dir__) || (!FIDDLE.empty? && path.start_with?(FIDDLE))

      ALLOCATE = Class.instance_method(:allocate)

      def allocate(klass) = ALLOCATE.bind_call(klass)

      # ruby's C can take a class's allocator away; ruby itself can only
      # take the methods.
      def undef_allocator(klass)
        message = "allocator undefined for #{klass}"
        klass.define_singleton_method(:allocate) { raise TypeError, message }
        klass.define_singleton_method(:new) { |*| raise TypeError, message }
      end

      private

      def resume
        outer = @unwind
        @unwind = nil
        answer = yield
        left = @unwind
        @unwind = outer
        raise left if left

        answer
      end

      def function(address, arity)
        (@functions ||= {})[[address, arity]] ||= Fiddle::Function.new(address, [WORD] * arity, WORD)
      end
    end
  end
  private_constant :Native
end
