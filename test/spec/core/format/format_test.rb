# frozen_string_literal: true

require "spec_helper"

describe "Format programs" do
  it "percent r literal syntax" do
    result = zr(<<~'RUBY')
      r = %r{foo/bar}
      puts r.match?("xxfoo/barxx")
      puts r.source
    RUBY

    _(result).must_answer "true\nfoo/bar\n"
  end
end
