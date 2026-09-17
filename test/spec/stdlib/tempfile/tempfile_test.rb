# frozen_string_literal: true

require "spec_helper"

describe "Tempfile programs" do
  it "tempfile create yields a readable file" do
    _(ze0(<<~'RUBY')).must_answer "ok\n"
      require "tempfile"
      Tempfile.create("readable") do |f|
        f.write("ok")
        f.rewind
        puts f.read
      end
    RUBY
  end
end
