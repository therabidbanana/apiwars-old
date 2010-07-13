#\-s thin -p 5432
begin
  # Try to require the preresolved locked set of gems.
  require File.expand_path('../.bundle/environment', __FILE__)
rescue LoadError
  # Fall back on doing an unlocked resolve at runtime.
  require "rubygems"
  Gem.clear_paths
  require "bundler"
  Bundler.setup
end

require "orange-core"
require "apiwars"

run ApiWars.app