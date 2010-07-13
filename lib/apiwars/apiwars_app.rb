require 'orange-core'
require 'orange-more/administration'
require 'orange-more/assets'
require 'orange-more/pages'
require 'orange-more/sitemap'
require 'orange-more/slices'
require 'orange-more/disqus'
require 'orange-more/analytics'
require 'orange-more/cloud'
require 'orange-more/debugger'
require 'orange-more/subsites'
require 'maruku'
require 'rack/builder'
require 'rack/abstract_format'

require 'orange-sparkles/plugin'

class ApiWars < Orange::Application
  def stack_init
    @core.template_chooser do |packet|
      if [:api].include?(packet['route.context'])
        false
      else
        # packet.add_js('jquery-1.4.1.min.js', :module => '_sparkles_')
        #        ['reset', '960_24_col', 'text', 'main'].each{|c| packet.add_css("#{c}.css", :module => '_sparkles_')}
        'page.haml'
      end
    end # end do
  end
  
  stack do
    orange.options[:development_mode] = true
    use Rack::CommonLogger
    use Rack::MethodOverride
    use Rack::Session::Cookie, :secret => (orange.options['main_user'] || 'the_secret')
    auto_reload!
    use_exceptions
    
    use Rack::OpenID, OpenIDDataMapper::DataMapperStore.new
    prerouting

    routing :single_user => false, :exposed_actions => {:api => :all}
    
    postrouting
    orange.add_pulp(ApiWarsHelpers)
    run ApiWars.new(orange)
  end
  
end



module ApiWarsHelpers
  def markdown(string)
    # Preparse for radius
    string = orange[:radius].parse_text(self, string)
    Maruku.new(string).to_html
  end
  def lorem(chars = 300)
    chars = chars.to_i
    ("Lorem ipsum dolor sit amet, consectetur adipiscing elit. In tincidunt enim eget ante semper  interdum. Proin quis erat nec tellus faucibus volutpat. Aenean ornare augue eu tellus fermentum vel blandit ipsum bibendum. Pellentesque a nisi justo, non tristique metus. Curabitur fermentum tincidunt neque, sit amet posuere dui tempor at. Suspendisse imperdiet lobortis tempus. Nulla ac sem ut lorem laoreet porttitor at vestibulum dui.

    Lorem ipsum dolor sit amet, consectetur adipiscing elit. In tincidunt enim eget ante semper interdum. Proin quis erat nec tellus faucibus volutpat. Aenean ornare augue eu tellus fermentum vel blandit ipsum bibendum."*6)[0..chars]
  end
end