# frozen_string_literal: true

require "spec_helper"

describe "Tempfile programs" do
  it "tempfile create yields a readable file" do
    result = ze0(<<~'RUBY')
      require "tempfile"
      Tempfile.create("readable") do |f|
        f.write("ok")
        f.rewind
        puts f.read
      end
    RUBY

    _(result).must_answer "ok\n"
  end
end
