# The constants and globals that describe the program, and ENV. The ruby constants print their shapes, which hold on any ruby and build.
p RUBY_VERSION.match?(/\A\d+\.\d+\.\d+\z/), RUBY_ENGINE, RUBY_ENGINE_VERSION == RUBY_VERSION, RUBY_PLATFORM.match?(/\A\w+(-\w+)+\z/), RUBY_PATCHLEVEL >= -1, RUBY_RELEASE_DATE.match?(/\A\d{4}-\d\d-\d\d\z/), RUBY_COPYRIGHT == "ruby - Copyright (C) 1993-#{RUBY_RELEASE_DATE[0, 4]} Yukihiro Matsumoto", RUBY_DESCRIPTION.start_with?("ruby #{RUBY_VERSION}") && RUBY_DESCRIPTION.include?(" (#{RUBY_RELEASE_DATE} ") && RUBY_DESCRIPTION.include?(" #{RUBY_REVISION[0, 10]}) ") && RUBY_DESCRIPTION.end_with?(" [#{RUBY_PLATFORM}]")
p ARGV, $*, $0, $PROGRAM_NAME, __FILE__, __LINE__, __dir__.start_with?("/"), __dir__.end_with?("/test/programs/native")
p ENV.class, ENV["HOME"].class, ENV["ZR_NOPE_X"], ENV.fetch("ZR_NOPE_X", 1), ENV.fetch("ZR_NOPE_X") { |k| k * 2 }, ENV.key?("HOME"), ENV.key?("ZR_NOPE_X"), ENV.to_h.class, ENV.keys.include?("HOME"), ENV.to_s, ENV.inspect.start_with?("{")
ENV["ZR_TEST_VAR"] = "one"
p ENV["ZR_TEST_VAR"], ENV.fetch("ZR_TEST_VAR"), ENV.delete("ZR_TEST_VAR"), ENV["ZR_TEST_VAR"], ENV.delete("ZR_TEST_VAR")
ENV["ZR_TEST_VAR"] = "two"
ENV["ZR_TEST_VAR"] = nil
p ENV["ZR_TEST_VAR"], ENV.values_at("HOME", "ZR_NOPE_X").map(&:class), ENV.select { |k, v| k == "HOME" }.keys, ENV.map { |k, v| k }.include?("HOME"), ENV.each_pair.class
begin; ENV.fetch("ZR_NOPE_X"); rescue KeyError => e; puts e.message; p e.key, e.receiver.equal?(ENV); end
begin; ENV[1]; rescue TypeError => e; puts e.message; end
def where = __dir__
p where == __dir__, __method__, [__FILE__, __LINE__]
p $;, $,, $/, $\, $VERBOSE, $DEBUG, $-w, $FILENAME, $$.class, $$ > 0, $@
begin; raise "x"; rescue; p $@.class, $@.first; end
$0 = "renamed"
p $0, $PROGRAM_NAME
p Process.pid.is_a?(Integer), Process.pid > 0, Process.pid == $$
