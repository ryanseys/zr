# The constants and globals that describe the program, and ENV (native only).
p RUBY_VERSION, RUBY_ENGINE, RUBY_ENGINE_VERSION, RUBY_PLATFORM, RUBY_PATCHLEVEL, RUBY_RELEASE_DATE, RUBY_COPYRIGHT, RUBY_DESCRIPTION
p ARGV, $*, $0, $PROGRAM_NAME, __FILE__, __LINE__, __dir__.start_with?("/"), __dir__.end_with?("/test/programs")
p ENV.class, ENV["HOME"].class, ENV["ZE0_NOPE_X"], ENV.fetch("ZE0_NOPE_X", 1), ENV.fetch("ZE0_NOPE_X") { |k| k * 2 }, ENV.key?("HOME"), ENV.key?("ZE0_NOPE_X"), ENV.to_h.class, ENV.keys.include?("HOME"), ENV.to_s, ENV.inspect.start_with?("{")
ENV["ZE0_TEST_VAR"] = "one"
p ENV["ZE0_TEST_VAR"], ENV.fetch("ZE0_TEST_VAR"), ENV.delete("ZE0_TEST_VAR"), ENV["ZE0_TEST_VAR"], ENV.delete("ZE0_TEST_VAR")
ENV["ZE0_TEST_VAR"] = "two"
ENV["ZE0_TEST_VAR"] = nil
p ENV["ZE0_TEST_VAR"], ENV.values_at("HOME", "ZE0_NOPE_X").map(&:class), ENV.select { |k, v| k == "HOME" }.keys, ENV.map { |k, v| k }.include?("HOME"), ENV.each_pair.class
begin; ENV.fetch("ZE0_NOPE_X"); rescue KeyError => e; puts e.message; p e.key, e.receiver.equal?(ENV); end
begin; ENV[1]; rescue TypeError => e; puts e.message; end
def where = __dir__
p where == __dir__, __method__, [__FILE__, __LINE__]
p $;, $,, $/, $\, $VERBOSE, $DEBUG, $-w, $FILENAME, $$.class, $$ > 0, $@
begin; raise "x"; rescue; p $@.class, $@.first; end
$0 = "renamed"
p $0, $PROGRAM_NAME
