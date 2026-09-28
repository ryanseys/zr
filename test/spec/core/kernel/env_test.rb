# frozen_string_literal: true

require "spec_helper"

describe "ENV" do
  it "ENV gives frozen Strings, raises setenv's error and checks names and values" do
    result = zr(<<~'RUBY')
      # ENV gives frozen Strings, raises setenv's error, and checks names and
      # values as get_env_cstr does.
      ENV["ZQ_SPEC"] = "v"
      p [ENV["ZQ_SPEC"].frozen?, ENV.fetch("ZQ_SPEC").frozen?, ENV.to_h["ZQ_SPEC"].frozen?, ENV.assoc("ZQ_SPEC").map(&:frozen?)]
      p((begin; ENV["A=B"] = "x"; rescue => e; e; end), (begin; ENV[""] = "x"; rescue => e; e; end), ENV.delete("A=B"))
      p((begin; ENV["X"] = "a".encode("utf-16le"); rescue => e; e; end), (begin; ENV["X".encode("utf-16le")] = "a"; rescue => e; e; end))
      p((ENV.merge!(1) rescue $!), (ENV.to_h { 1 } rescue $!), (ENV.to_h { [1] } rescue $!))
      ENV.delete("ZQ_SPEC")
    RUBY

    _(result).must_answer <<~'OUT'
      [true, true, true, [false, true]]
      #<Errno::EINVAL: Invalid argument - setenv(A=B)>
      #<Errno::EINVAL: Invalid argument - setenv()>
      nil
      #<ArgumentError: bad environment variable value: ASCII incompatible encoding: UTF-16LE>
      #<ArgumentError: bad environment variable name: ASCII incompatible encoding: UTF-16LE>
      #<TypeError: no implicit conversion of Integer into Hash>
      #<TypeError: wrong element type Integer (expected array)>
      #<ArgumentError: element has wrong array length (expected 2, was 1)>
    OUT
  end
end
