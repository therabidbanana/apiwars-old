require 'rubygems'
require 'sinatra'
require 'dm-core'
require 'dm-serializer'
require 'dm-timestamps'
require 'dm-migrations'
require 'haml'
require 'digest/md5'

require 'oa-oauth'


use OmniAuth::Strategies::GitHub, (ENV['GITHUB_KEY'] || '5ce55eaa17d66bf4f9cf'), (ENV['GITHUB_SECRET'] || '350137e0a82fd6402fddaa2992ff80b2ed46eff0')
DataMapper.setup(:default, ENV['DATABASE_URL'] || 'sqlite://'+Dir.pwd+'/testing.sqlite')
DataMapper::Property::String.length(255)

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
  def claim?(p1, unit)
    return false unless(self.player.nil? || self.player == p1)
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
  property :pin, String
  property :created_on, DateTime
  property :reset_on, DateTime, :default => DateTime.parse("1/1/11")
  property :daily_calls, Integer, :default => 0

  # Concatenate all players' sauce to create
  # a string that's not guessable to hash
  # everything with
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
    self.api = Digest::MD5.hexdigest("player: "+id.to_s+provider+uid+Player.secret_sauce+created_on.to_s)
    self.save
  end
  def calls?(max, num = 1)
    reset_if_possible
    daily= self.daily_calls || 0
    can = (daily + num.to_i)
    if can <= max
      self.daily_calls = can
      self.save
    end
    return can
  end

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

class Game
  include DataMapper::Resource
  property :id, Serial
  property :created_on, DateTime
  property :name, String
end

DataMapper.auto_upgrade!
DataMapper.finalize

configure do
  enable :sessions
  set :max_spaces, 60**2
  set :players, [['github', 'therabidbanana']]
  set :max_calls, 100
  set :method_values, {"GET" => 1, "POST" => "2", "PUT" => 3, "DELETE" => 5, "HEAD" => 1}
end

helpers do
  def api_authorized?
    halt(401, 'Valid API Key Required') unless params["key"]
    if(p = Player.first(:api => params["key"]))
      request.env['api_player'] = p
      pin_player = Player.first(:pin => params["pin"])
      if pin_player
        request.env['pin_player'] = pin_player
      else
        # Penalize hacking to make it risky
        p.calls?(settings.max_calls, 2)
        halt 401, 'Valid Pin Required'
      end
    else
      halt 401, 'Valid API Key Required'
    end
  end

  def has_calls?
    p = request.env['pin_player']
    spent = p.calls?(settings.max_calls, settings.method_values[request.request_method])
    halt 402, 'Not enough calls' unless spent
  end

end

before %r{/(grid|player)/.+} do
  api_authorized?
  has_calls?
end

get "/grid/:space" do
  space = params[:space] + Player.secret_sauce
  digest = Digest::MD5.hexdigest(space)
  id = Integer("0x#{digest[0..3]}")
  if(g =GridSpace.get(id))
    status 200
    g.to_json
  else
    halt 404, "Invalid Space"
  end
end

put "/grid/:space" do
  space = params[:space] + Player.secret_sauce
  digest = Digest::MD5.hexdigest(space)
  id = Integer("0x#{digest[0..3]}")
  if(g =GridSpace.get(id))
    if(g.claim?(request.env['api_player'], params["unit"]))
      status 201
      g.to_json
    else
      halt 403, 'Someone else owns the space'
    end
  else
    halt 404, "Invalid Space"
  end
end

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

get "/game/seed" do
  unless Game.first()
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
  'game already seeded'
end

get "/" do
  haml :index, :locals => {:spaces => GridSpace.all}
end

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
