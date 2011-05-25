require 'em-synchrony'
require 'em-synchrony/em-http'
require 'vcr'

VCR.config do |c|
  c.cassette_library_dir = 'spec/cassettes'
  c.stub_with :webmock
  c.default_cassette_options = { :record => :none }
end
