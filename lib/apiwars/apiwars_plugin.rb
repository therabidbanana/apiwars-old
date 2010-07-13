module Orange::Plugins
  class ApiWars < Base
    assets_dir      File.join(File.dirname(__FILE__), 'assets')
    views_dir       File.join(File.dirname(__FILE__), 'views')
    templates_dir   File.join(File.dirname(__FILE__), 'templates')
    
  end
end

Orange.plugin(Orange::Plugins::ApiWars.new)

