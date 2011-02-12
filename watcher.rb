require 'sinatra'
require 'dm-core'
require 'appengine-apis/urlfetch'

# Configure DataMapper to use the App Engine datastore 
DataMapper.setup(:default, "appengine://auto")

# Create your model class
class Test
  include DataMapper::Resource
  property :id,     Serial
  property :url,    String
  
  has n, :results
  has n, :archives
end

class Result
  include DataMapper::Resource
  property :id,     Serial
  property :date,   Time
  property :value,  Float
    
  belongs_to :test, :child_key => [:test_id]  # defaults to :required => true
end

class Archive
  include DataMapper::Resource
  property :id,     Serial
  property :type,   String
  property :date,   Time
  property :mean,   Float
  property :max,    Float
  property :min,    Float
  property :uptime, Float
  property :nbValues, Integer

  belongs_to :test, :child_key => [:test_id]  # defaults to :required => true
end


# Make sure our template can use <%=h
helpers do
  include Rack::Utils
  alias_method :h, :escape_html
end

get '/' do
  tests = Test.all
  today = Time.now
  todayL = Time.local(today.year,today.month,today.day) #00:00
  todayB = todayL - 604800
  @array = Array.new(tests.count+1) {Hash.new}
  #fill with dates
  (0..6).each do |i|
    myDate = todayL - (6-i)*86400
    @array[0][myDate] = myDate.strftime("%d/%m")

  end
  line = 1 #line0 = line with dates
  tests.each do |test|
    @array[line]["url"] = test.url
    @array[line]["id"] = test.id
    archives = test.archives.all(:type => "day",:date.gte => todayB,:date.lte => todayL,:order => [:date.asc])
    archives.each do |archive|      
      @array[line][archive.date] = archive
    end
    line = line + 1
  end
  
  erb :index
end

#display new form
get '/new' do
  erb :new
end

#add a new test
post '/new' do
  # Create a new shout and redirect back to the list.
  if params[:url] != nil and params[:url] != ""
    test = Test.create(:url => params[:url])
  end  
  redirect '/'
end

#delete tests
get '/:id/delete' do
  test = Test.get(params[:id])
  test.results.destroy
  test.archives.destroy
  test.destroy
  redirect '/'
end


def archivesDay(value,date,test)
  todayB = Time.local(date.year,date.month,date.day) #00:00
  archive = test.archives.first(:date => todayB)
  if archive != nil
    max,min,mean,uptime,nbValues = archive.max,archive.min,archive.mean,archive.uptime,archive.nbValues
    if archive.uptime == 0 and nbValues > 0 #first measures were KO
      #no change but nb of values
      nbValues = nbValues + 1
    else
      if value > max
        max = value
      end
      if value < min
        min = value
      end
      #uptime = nbvalues OK
      mean = (mean*uptime + value) / (uptime+1)
      uptime = uptime + 1
      nbValues = nbValues + 1
      archive.update(:max => max, :min => min, :mean => mean, :uptime => uptime, :nbValues => nbValues)
    end
  else #First Measure
    max,min,mean,uptime,nbValues = 0,0,0,0,0
    if value == -1 #KO
      nbValues = 1
    else #OK
      max,min,mean,uptime,nbValues = value,value,value,1,1
    end
    test.archives.create(:type => "day",:date => todayB,:max => max, :min => min, :mean => mean, :uptime => uptime, :nbValues => nbValues)  
  end
  
  
end

get '/:id/list' do
  @test = Test.get(params[:id])
  @results = @test.results.all(:order => [:date.asc])
  erb :list
end


get '/go' do
  tests = Test.all
  tests.each do |test|
    date, value = Time.new, 0
    begin
      url = test.url            
      AppEngine::URLFetch.fetch(url, :method => 'GET')
      after = Time.new
      value = after - date
      test.results.create(:value => value,:date => date)
    rescue
      value = -1
      test.results.create(:value => value,:date => date)         
    end
    archivesDay(value,date,test)
  end
  return "Done"  
end