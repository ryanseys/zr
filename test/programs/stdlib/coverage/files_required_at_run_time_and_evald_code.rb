require "coverage"
require "tmpdir"

# Files whose paths the build cannot see: each is compiled when it is
# required, and Coverage measures it as ruby does.
Dir.mktmpdir do |dir|
  fix = File.join(dir, "cov_fix.rb")
  File.write(fix, "# A fixture.\nclass CovFix\n  def run\n    1\n  end\nend\nCovFix.new.run\n")
  evals = File.join(dir, "cov_eval.rb")
  File.write(evals, "5 + 5\n\nmodule CoverageSpecs\n\n  class_eval <<-RUBY, __FILE__, __LINE__ + 1\n    attr_reader :ok\n  RUBY\n\nend\n\n4 + 4\n")
  short = ->(h) { h.transform_keys { |k| File.basename(k) } }

  Coverage.start
  require [fix].first
  p short.(Coverage.peek_result)
  p short.(Coverage.result)
  Coverage.start(:all)
  $LOADED_FEATURES.delete(fix)
  load [fix].first
  p short.(Coverage.result(stop: false, clear: true))
  p short.(Coverage.result)

  Coverage.start(lines: true, eval: true)
  require [evals].first
  p short.(Coverage.result)
  $LOADED_FEATURES.delete(evals)
  Coverage.start(lines: true, eval: false)
  require [evals].first
  p short.(Coverage.result)
  Coverage.start(lines: true, eval: true)
  eval("Object.new\n" * 3, binding, "test.rb", 1)
  eval("x = 1\ny = 2", binding, "other.rb", 3)
  p short.(Coverage.result)
end
