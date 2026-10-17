# rbs finds a library's signatures in the sig/ directory of its gem, which
# Gem::Specification finds, and the core's in its own core/ directory.
# zr's Gem::Specification lists the gems that the build compiled in, so
# the program requires the libraries whose types it reads.
require "rbs"
require "prime"
require "base64"

loader = RBS::EnvironmentLoader.new
loader.add(library: "prime")
loader.add(library: "base64")
env = RBS::Environment.from_loader(loader).resolve_type_names
builder = RBS::DefinitionBuilder.new(env: env)

prime = builder.build_singleton(RBS::TypeName.parse("::Prime"))
p prime.methods.key?(:each), prime.methods[:prime?].method_types.map(&:to_s)
p builder.build_singleton(RBS::TypeName.parse("::Base64")).methods[:strict_encode64].method_types.map(&:to_s)
p builder.build_instance(RBS::TypeName.parse("::Integer")).methods[:prime?].method_types.map(&:to_s)
p env.class_decls.key?(RBS::TypeName.parse("::String"))

# An unknown library raises only when the environment loads.
missing = RBS::EnvironmentLoader.new
missing.add(library: "no_such_library_here")
begin
  RBS::Environment.from_loader(missing)
rescue RBS::EnvironmentLoader::UnknownLibraryError => e
  puts e.message
end
