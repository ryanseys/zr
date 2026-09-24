# frozen_string_literal: true

require "spec_helper"

describe "Tempfile programs" do
  it "Tempfile.create yields a file the block can write and read back" do
    result = zr(<<~'RUBY')
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
