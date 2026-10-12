# RUBY_* version/build constants and the File::SEPARATOR family that zr
# shares with its ruby oracle. The version, the platform and the revision
# change with the ruby and the build, so this checks the separators exactly
# and the RUBY_* constants by their shapes, keeping the golden output
# portable across rubies and build hosts AND identical between zr and the
# oracle.
#
# The ENGINE-IDENTITY constants (RUBY_ENGINE, RUBY_ENGINE_VERSION,
# RUBY_DESCRIPTION) mirror CRuby's own ("ruby", RUBY_VERSION, version.c's
# banner). They are checked in `ruby_engine_identifies_as_ruby`;
# this golden covers the shared version/build constants.
puts RUBY_VERSION.match?(/\A\d+\.\d+\.\d+\z/)
puts RUBY_PATCHLEVEL >= -1
puts RUBY_RELEASE_DATE.match?(/\A\d{4}-\d\d-\d\d\z/)
puts File::SEPARATOR
p File::ALT_SEPARATOR
puts File::PATH_SEPARATOR

# Structural checks (true on every build host, both engines):
puts RUBY_PLATFORM.include?("-")
puts RUBY_REVISION.match?(/\A\h{40}\z/)
puts RUBY_COPYRIGHT.end_with?("-#{RUBY_RELEASE_DATE[0, 4]} Yukihiro Matsumoto")
