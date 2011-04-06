# <a href="https://github.com/therabidbanana/apiwars"><img style="position: absolute; top: 0; right: 0; border: 0;" src="https://d3nwyuy0nl342s.cloudfront.net/img/30f550e0d38ceb6ef5b81500c64d970b7fb0f028/687474703a2f2f73332e616d617a6f6e6177732e636f6d2f6769746875622f726962626f6e732f666f726b6d655f72696768745f6f72616e67655f6666373630302e706e67" alt="Fork me on GitHub"></a>
#
# API Wars
# ========
#
# **APIWars** is a game for nerds. There is no UI. All
# of the actions are accomplished via RESTful actions
# to the Grid, Players or Test objects.
# 

## Installation
#
# The game is a small Sinatra script that can be installed
# on any server that can run a Sinatra app and has database
# access (using DataMapper for database communications).
#
# API Wars is intended to be hosted on your own server to
# play with your nerdier friends/colleagues - so some
# assembly is required (Heroku makes it dead-easy though.)

### Requirements
# A gemfile is included - just run "bundle install" to
# get the necessary gems
require 'rubygems'
require 'sinatra'
require 'dm-core'
require 'dm-serializer'
require 'dm-timestamps'
require 'dm-migrations'
require 'haml'
require 'digest/md5'

### OAuth Setup
# We use OmniAuth for authentication to reduce complexity.
# Currently the script uses Github's OAuth. You'll need
# to request an oauth application on their site:
# 
# https://github.com/account/applications/new
#
# Set the callback like so:
# 
#     http://mygame.example.com/auth/github/callback
# 
# It should be pretty easy to use something else
# (FB, Twitter, etc.) Check out the Omniauth Docs.
#
require 'oa-oauth'

# Set your Github Key and Secret here, or with ENV variables
# (good for heroku.)
use OmniAuth::Strategies::GitHub, 
  (ENV['GITHUB_KEY'] || '5ce55eaa17d66bf4f9cf'), 
  (ENV['GITHUB_SECRET'] || '350137e0a82fd6402fddaa2992ff80b2ed46eff0')

### Database
# Set your database url with an ENV variable or in place
# of the url below. Make sure you have the appropraite
# datamapper gem installed for your database:
# mysql => dm-mysql-adapter
# posgres => dm-postgres-adapter
DataMapper.setup(:default, 
                 ENV['DATABASE_URL'] || 'sqlite://'+Dir.pwd+'/testing.sqlite')


configure do
  enable :sessions
  # Goal 
  # ----
  #
  # The goal of the game is simple - to own the most grid 
  # spaces. Players accomplish this with PUTs to grid spaces.
  # max_spaces is the maximum amount of grid spaces available
  # to players
  set :max_spaces, 60**2

  # Players
  # -------
  # 
  # You'll probably want at least 2. For github
  # authentication, use nicknames. 
  set :players, [ ['github', 'therabidbanana'], 
                  ['github', 'shaineh'],
                  ['github', 'eperiodfperiod'],
                  ['github', 'radicaleggnog']]

  # Moves
  # ----
  # 
  # Play is accomplished with RESTful calls. Players are 
  # limited to the amount of calls they can make
  # in a single day.
  set :max_calls, 100

  # DELETEs, PUTs and POSTs are more costly than GETs because
  # they can do more.
  set :method_values, {"GET" => 1, "POST" => "2", 
    "PUT" => 3, "DELETE" => 5, "HEAD" => 1}
end


DataMapper::Property::String.length(255)

# The Grid
# --------
#
# To make things a bit more challenging, only certain
# grid spaces are actually valid. Any grid id passed will
# be hashed and turned into a 16 bit integer.
#
# This means players should use GETs to find possible grid
# spaces before spending more costly PUTs.
class GridSpace
  include DataMapper::Resource
  property :id, Integer, :key=> true
  property :attack, Integer, :default => 0
  property :defense, Integer, :default => 0
  property :hits, Integer, :default => 0
  belongs_to :player, :required => false
  def color
    return "#fff" unless player
    return "##{Digest::MD5.hexdigest(player.id.to_s)[0..5]}"
  end

  def reset!
    self.player = nil
    self.attack = 0
    self.defense = 0
    self.hits = 0
    self.save
  end

  # Occupation
  # ----------
  #
  # PUTs of units are only successful if Grid space is 
  # unoccupied or already owned by the player.
  # 
  # DELETEs are more costly, but will attack other players
  # if they are occupying the space (and occupy an unoccupied
  # space).
  #
  # Units have three attributes: attack, defense and hp.
  # These are used to calculate if a DELETE is successful.
  # Several DELETEs may be necessary to remove an occupying 
  # unit.
  #
  def claim?(p1, unit)
    return false unless(self.player.nil? || self.player == p1)
    return false unless unit
    digest = Digest::MD5.hexdigest(Player.secret_sauce + unit)
    atk = Integer("0x#{digest[0..1]}")
    dfn = Integer("0x#{digest[3..4]}")
    hp = Integer("0x#{digest[6..7]}")
    self.player = p1
    self.attack = atk
    self.defense = dfn
    self.hits = hp
    self.save
  end
  def attack?(p1, unit)
    return true if(claim?(p1, unit))
    return false unless unit
    digest = Digest::MD5.hexdigest(Player.secret_sauce + unit)
    atk = Integer("0x#{digest[0..1]}")
    atk = atk  - self.defense
    atk = (atk > 0)? atk : 1
    hp = self.hits - atk
    if hp > 0
      self.hits = hp
      self.save
      return false
    else
      atk = Integer("0x#{digest[0..1]}")
      dfn = Integer("0x#{digest[3..4]}")
      hp = Integer("0x#{digest[6..7]}")
      self.player = p1
      self.attack = atk
      self.defense = dfn
      self.hits = hp
      self.save
    end
  end
end

class Player
  include DataMapper::Resource
  property :id, Serial
  property :provider, String
  property :uid, String
  property :api, String
  property :sauce, String
  property :pin, String, :length => 4
  property :created_on, DateTime
  property :reset_on, DateTime, :default => DateTime.parse("1/1/11")
  property :daily_calls, Integer, :default => 0
  has n, :grid_spaces
  
  #### The secret sauce
  # The secret sauce is a salt for all of the
  # hash functions done in the game. 
  #
  # We concatenate all players' sauce to create
  # a string that's not guessable to any
  # particular player (unless they have DB access).
  #
  # Resetting your own sauce will completely modify the
  # game board, possibly invalidating everything you know.
  # Probably a good way to stay ahead, or just mess people.
  def self.secret_sauce
    sauce = "extra delicious"
    Player.all.each{ |p| sauce += p.sauce if p.sauce }
    sauce
  end

  
  def api
    generate_key! unless self.attribute_get(:api)
    self.attribute_get(:api)
  end
  
  def generate_key!
    self.api = Digest::MD5.hexdigest("player: "+id.to_s+
                                     provider+uid+Player.secret_sauce+
                                     created_on.to_s)
    self.save
  end

  def calls?(max, num = 1)
    reset_if_possible
    daily= self.daily_calls || 0
    can = (daily + num.to_i)
    if can <= max
      self.daily_calls = can
      self.save
      true
    else
      false
    end
  end
 
  # The player may reset their pin at any time, but to do so they
  # loose one of their squares. Pins must be 4 numeric digits,
  # all other characters are replaced by 0.
  def pin=(new_pin)
    new_pin = "" unless new_pin
    new_pin = new_pin[0..3] # Trim
    new_pin = new_pin.gsub(/[^0-9]/, '0')
    new_pin = new_pin.center(4, '0')
    disown! unless self.pin == new_pin
    super(new_pin)
  end


  # If a player resets their pin, this method is called
  def disown!
    if space = self.grid_spaces.first
      space.reset!
    end
    self.grid_spaces.reload
  end

  # The player may reset their own sauce at any time. This
  # changes the hashes that run the game for everyone, so
  # to limit the destructive tendencies of players, they
  # must be willing to give up their spaces.
  def sauce=(new_sauce)
    disown_all! unless self.sauce == new_sauce
    super
  end

  # If a player resets their sauce, this method is called
  def disown_all!
    self.grid_spaces.each do |s|
      s.reset!
    end
    self.grid_spaces.reload
  end

  # Every 24 hours the player gets their call count reset. This happens
  # on their next call.
  def reset_if_possible
    now = DateTime.now
    reset_time = self.reset_on || DateTime.parse("1/1/11")
    if (now - reset_on).to_f > 1
      self.reset_on = now
      self.daily_calls = 0
      self.save
    else
      self.reset_on = reset_time
      self.save
    end
  end
end

# For storing game data. May be used for historical tracking
# in some future version.
class Game
  include DataMapper::Resource
  property :id, Serial
  property :created_on, DateTime
  property :name, String
end

DataMapper.finalize


helpers do
  # All moves require valid authentication
  # parameters to be passed are:
  #    key:  the user's API key
  #    pin:  a valid user pin
  def api_authorized?
    halt(401, 'Valid API Key Required') unless params["key"]
    if(p = Player.first(:api => params["key"]))
      request.env['api_player'] = p
      pin_player = Player.first(:pin => params["pin"])
      pin_player = p if request.path_info == "/player/"+p.id.to_s
      if pin_player
        # Note that the pin doesn't have to be the same user
        # as the api key.
        request.env['pin_player'] = pin_player
      else
        # But we count invalid pins against the API
        # key player, so it's risky to waste
        # API calls trying to find out someone
        # else's PIN.
        p.calls?(settings.max_calls, 2)
        halt 401, 'Valid Pin Required'
      end
    else
      halt 401, 'Valid API Key Required'
    end
  end

  def has_calls?
    # Checks to make sure player has moves left
    # before allowing move. 
    #
    # Remember the pin player can be any player,
    # not necessarily the same one as the API key.
    p = request.env['pin_player']
    spent = p.calls?(settings.max_calls, 
                     settings.method_values[request.request_method])
    halt(403, 'Not enough calls') unless spent
  end

  # Redirect to seed game if DataMapper can't find an
  # existing game (so all we need to do to install is
  # visit the home page once)
  def game?
    begin
      Game.first
    rescue Exception => e
      redirect '/game/seed'
    end
  end
end

before %r{!(/game/seed/?)} do
  game?
end

# Grid and Player resources require authorization
before %r{/(grid|player)/.+} do
  api_authorized?
  has_calls?
  cache_control :no_cache
end

# Get info about a given grid space.
# Note that the :space id is hashed with the 
# secret sauce and converted to an integer, then
# we test to see if it is a valid grid space.
#
# GET /grid/:space 
#   
#   (Requires key and pin arguments)
get "/grid/:space" do
  space = params[:space] + Player.secret_sauce
  digest = Digest::MD5.hexdigest(space)
  id = Integer("0x#{digest[0..3]}")
  if(g =GridSpace.get(id))
    # Returns 200 with hash of space info on success
    status 200
    g.to_json
  else
    # Oherwise, returns 404
    halt 404, "Invalid Space"
  end
end

# Place a unit on a space, if unoccupied and valid.
#
# PUT /grid/:space?unit=foo
#   unit: a string to be hashed to create unit attributes
#
#   (Requires key and pin arguments)
put "/grid/:space" do
  space = params[:space] + Player.secret_sauce
  digest = Digest::MD5.hexdigest(space)
  id = Integer("0x#{digest[0..3]}")
  if(g =GridSpace.get(id))
    if(g.claim?(request.env['api_player'], params["unit"]))
      # Returns 201 and a hash of space info on success
      status 201
      g.to_json
    else
      # Returns 403 with error if someone else occupies
      halt 403, 'Someone else owns the space'
    end
  else
    # Returns 404 if space id invalid
    halt 404, "Invalid Space"
  end
end

# Place a unit on a space, attacking any existing unit on
# the space (note attack may not be successful, depending
# on occupying unit's attributes)
#
# DELETE /grid/:space?unit=foo
#   unit: a string to be hashed to create unit attributes
#
#   (Requires key and pin arguments)
delete "/grid/:space" do
  space = params[:space] + Player.secret_sauce
  digest = Digest::MD5.hexdigest(space)
  id = Integer("0x#{digest[0..3]}")
  if(g =GridSpace.get(id))
    if(g.attack?(request.env['api_player'] , params["unit"]))
      status 200
      g.to_json
    else
      halt 409, 'Attack unsuccessful'
    end
  else
    halt 404, "Invalid Space"
  end
end

# Run initialization of database if
# it hasn't been done yet. Last step before
# you can play. Executed automatically first
# time site is visited.
get "/game/seed" do
  begin
    Game.first()
    'game already seeded'
  rescue Exception => e
    DataMapper.auto_migrate!
    max = settings.max_spaces
    (0..max).each do |space|
      unless GridSpace.get(space)
        GridSpace.create(:id => space)
      end
    end
    settings.players.each do |provider, uid|
      unless Player.get(:provider => provider, :uid => uid)
        p = Player.create(:provider => provider, :uid => uid)
      end
    end
    Game.create(:name => 'Game')
    return 'game ready with '+settings.max_spaces.to_s + ' squares'
  end
end

# Show a basic message with game status.
get "/" do
  expires 1800, :public, :must_revalidate
  haml :index, :locals => {:spaces => GridSpace.all, :players => Player.all}
end

# This is how we allow players to access their
# API keys - they log in via Github.
#
# GET /auth/github 
#    => redirects to Github auth page.
#    => if authorized, redirects here.
#
# A form is shown to allow updating pin and sauce
get "/auth/:provider/callback" do
  auth = request.env['omniauth.auth']
  uid = case auth['provider']
  when 'github'
    auth['user_info']['nickname']
  else
    auth['uid']
  end
  if(p = Player.first(:provider => params[:provider], :uid => uid))
    
    haml :form, :locals => {:player => p}
  else
    status 404
    return 'invalid player'
  end
end

# You may update your pin and sauce at any time.
# Updating your pin will ensure nobody can use it to make 
# calls.
#
# Updating your sauce will change all hash calculations,
# completely changing valid grid id's and unit attributes.
#
# POST /player/:id
# (Requires key and pin arguments) 
#
post "/player/:id" do
  if params["key"]
    if(p=Player.first(:api => params["key"]))
      unless p.id == params[:id].to_i
        status 401
        return 'Not allowed to edit other players'
      end
      if params["pin"] && params["pin"] != ''
        p.pin = params["pin"][0..3]
      end
      if params["sauce"] && params["sauce"] != ''
        p.sauce = params["sauce"]
      end

      p.save
      return 'Updated player info'
    else
      status 401
      return 'Not allowed (check api key)'
    end
  else
    status 401
    return 'Not allowed, must provide api key'
  end
end
