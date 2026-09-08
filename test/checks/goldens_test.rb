# frozen_string_literal: true

require_relative "helper"
require "rbconfig"

# ze0's own text for every `test/ze0/` program, held byte for byte: the
# oracle for a refactor of the lowering while nothing it emits can run.
# `ZE0_BLESS=1` rewrites them; a diff is a reviewed change to the lowering.
#
# Each program compiles in its own ruby from `test/`, named `ze0/<name>.rb`,
# so the paths in the text never move.
class GoldensTest < Minitest::Test
  GOLDENS = File.join(ROOT, "test/goldens")

  def self.compile(rb)
    Dir.mktmpdir("ze0-golden-") do |dir|
      out = File.join(dir, "p.clif")
      log = IO.popen([RbConfig.ruby, File.join(ROOT, "ze0.rb"), "ze0/#{File.basename(rb)}", "-o", out],
                     chdir: File.join(ROOT, "test"), err: %i[child out], &:read)
      raise "#{rb}: #{log}" unless $?.success?

      [File.binread(out), File.binread(File.join(dir, "p.zeodata"))]
    end
  end

  Dir[File.join(ROOT, "test/ze0/*.rb")].sort.each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_golden_#{name}") do
      clif, zeodata = self.class.compile(rb)
      if ENV["ZE0_BLESS"] == "1"
        FileUtils.mkdir_p(GOLDENS)
        File.binwrite(File.join(GOLDENS, "#{name}.clif"), clif)
        File.binwrite(File.join(GOLDENS, "#{name}.zeodata"), zeodata)
        skip "blessed #{name}"
      end
      %w[clif zeodata].zip([clif, zeodata]).each do |ext, text|
        path = File.join(GOLDENS, "#{name}.#{ext}")
        assert File.file?(path), "#{path} is not recorded (ZE0_BLESS=1 to record)"
        assert_equal File.binread(path), text, "#{path} differs from what ze0 writes now (ZE0_BLESS=1 to accept)"
      end
    end
  end
end
