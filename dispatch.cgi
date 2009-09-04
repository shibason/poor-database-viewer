#!/home/shiba/bin/ruby
require 'application'
disable :run
Rack::Handler::CGI.run Sinatra::Application
