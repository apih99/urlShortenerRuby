ENV['RACK_ENV'] = 'test'

require 'rspec'
require 'rack/test'
require_relative '../app'

RSpec.configure do |config|
  config.include Rack::Test::Methods

  config.before(:each) do
    # Clean the database before each test
    db = SQLite3::Database.new 'urls.db'
    db.execute('DELETE FROM urls')
    db.close
  end
end

def app
  Sinatra::Application
end 