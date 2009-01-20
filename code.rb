### Libraries

require 'rubygems'

# Testing

require 'test/spec'
require 'stringio'

# Rack

require 'rack'
require 'rack/mock'

### Helper

def env(options)
  Rack::MockRequest.env_for("/", options)
end

### Sample Apps

lambda_app = lambda do |env|
  [ 200,
    { 'Content-Type' => 'text/plain',
      'Content-Length' => '2' },
    "OK" ]
end

class InstanceApp
  def call(env)
    [ 200,
      { 'Content-Type' => 'text/plain',
        'Content-Length' => '2' },
      "OK" ]
  end
end

class ClassApp
  def self.call(env)
    [ 200,
      { 'Content-Type' => 'text/plain',
        'Content-Length' => '2' },
      "OK" ]
  end
end

class NotAnApp; end # does not define #call

### Spec

app = lambda_app

# application

app.respond_to?(:call)

# response

response = 
[
  200,
  {
    'Content-Type' => 'text/plain',
    'Content-Length' => '2'
  },
  "OK"
]

status = response[0]
headers = response[1]
body = response[2]

### Specification

context "Rack" do
  specify "requires applications to respond to #call" do
    lambda {
      Rack::Lint.new("not an app").call(env({}))
    }.should.raise NoMethodError
    
    lambda {
      Rack::Lint.new(lambda_app).call(env({}))
    }.should.not.raise
    
    lambda {
      Rack::Lint.new(InstanceApp.new).call(env({}))
    }.should.not.raise
    
    lambda {
      Rack::Lint.new(ClassApp).call(env({}))
    }.should.not.raise
    
    lambda {
      Rack::Lint.new(NotAnApp).call(env({}))
    }.should.raise NoMethodError
  end
  
  specify "requires applications to respond with an array of status, headers, and body" do
    good_app = lambda do |env|
      [ 200,
        { 'Content-Type' => 'text/plain',
          'Content-Length' => '2' },
        "OK" ]
    end
    bad_app = lambda { |env| nil }
    
    lambda {
      Rack::Lint.new(bad_app).call(env({}))
    }.should.raise Rack::Lint::LintError
  end
end

### Rack Application

# endpoint.rb

class RackEndpoint
  class << self
    def voodoo
      "computed awesome shit"
    end
    def call(env)
      body = voodoo
      [ 200,
        {'Content-Type' => 'text/html', 'Content-Length' => body.size},
        body ]
    end
  end
end

# config.ru

require 'endpoint'
run RackEndpoint

### Middleware

class MiddlewareClass
  def initialize(app)
    @app = app
  end
  def call(env)
    @app.call(env)
  end
end

# Real World Middleware

module Rack
  
  # A Rack middleware for providing JSON-P support.
  # 
  # Full credit to Flinn Mueller (http://actsasflinn.com/) for this contribution.
  # 
  class JSONP
    
    def initialize(app)
      @app = app
    end
    
    def call(env)
      status, headers, response = @app.call(env)
      request = Rack::Request.new(env)
      if request.params.include?('callback')
        response = pad(request.params.delete('callback'), response)
      end
      [status, headers, response]
    end
    
    def pad(callback, response, body = "")
      response.each{ |s| body << s }
      "#{callback}(#{body})"
    end
    
  end
end

### Rails Metal

# Slow Rails action

class InfoController < ApplicationController
  def status
    if status?
      render :text => "OK"
    else
      raise
    end
  end
end

# Equivalent Metal

class Metal < Rails::Rack::Metal
  def call(env)
    if env['PATH_INFO'] =~ %r{^/info/status}
      status, body = if status?
                     then [200, "OK"]
                     else [500, "Internal Server Error"]
                     end
      [ status,
        {"Content-Type" => "text/html"},
        body ]
    else
      [ 404,
        {"Content-Type" => "text/html"},
        "Not Found" ]
    end
  end
end

### Rails Middleware

Rails::Initializer.run do |config|
  # ...
  config.middleware.use MiddlewareClass
end

### Frameworks


class Posts < Fuck::Resource
  
  def create
    if post = Post.create(params)
      respond
    else
      respond "Unprocessable Entity", :status => 422
    end
  end
  
  def read(id)
    respond Post.find(id).to_json
  end
  
  def update(id)
    post = Post.find(id)
    if post.update_attributes(params)
      respond
    else
      respond "Unprocessable Entity", :status => 422
    end
  end
  
  def delete(id)
    post = Post.find(id)
    if post.destroy
      respond
    else
      respond "Internal Server Error", :status => 500
    end
  end
  
end

# The Fuck Framework

class Fuck
  
  VERSION = [0,1,1]
  
  class << self
    
    PATH_INFO = %r{/?(\w+)(/(\w+))?}
    
    def call(env)
      find_handler(env["PATH_INFO"], env["QUERY_STRING"]).call(env)
    end
    
    def find_handler(path_info, query_string)
      path_info =~ PATH_INFO
      resource, _, id = $1, $2, $3
      params = Rack::Utils.parse_query(query_string)
      Object.const_get(resource.capitalize).new(id, params)
    end
    
  end
  
  autoload :Resource, "fuck/resource"
  
end

# The Fuck Resources

class Fuck
  
  class Resource
    
    DEFAULT_HEADERS = {"Content-Type" => "text/html"}
    
    def initialize(id, params)
      @id, @params = id, params
    end
    
    def call(env)
      send((find_method(env["REQUEST_METHOD"]) || :not_implemented), *[@id].compact) or
      not_found
    rescue NoMethodError => e
      not_implemented
    rescue Exception => e
      # logger.error e.message
      # logger.error "\t"+e.backtrace.join("\n\t")
      respond("Internal Server Error", :status => 500)
    end
    
    def find_method(request_method)
      case request_method
      when "GET"
        if @id.nil?
          :all
        else
          :read
        end
      when "PUT"
        :create
      when "POST"
        :update unless @id.nil?
      when "DELETE"
        :delete unless @id.nil?
      else
        nil
      end
    end
    
    def params
      @params
    end
    
    def respond(body = "OK", options = {}, headers = {})
      options = {:status => 200}.merge(options)
      [
        options[:status],
        DEFAULT_HEADERS.merge({
          "Content-Length" => body.size.to_s
        }.merge(headers)),
        body
      ]
    end
    
    def not_found
      respond("Not Found", :status => 404)
    end
    
    def not_implemented
      respond("Not Implemented", :status => 501)
    end
    
  end
  
end

# Data examples ###############################################################
__END__

### Backtrace from Rails

/private/tmp/test/app/controllers/posts_controller.rb:5:in `index'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/base.rb:1264:in `send'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/base.rb:1264:in `perform_action_without_filters'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/filters.rb:617:in `call_filters'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/filters.rb:610:in `perform_action_without_benchmark'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/benchmarking.rb:68:in `perform_action_without_rescue'
/usr/local/lib/ruby/gems/1.8/gems/activesupport-2.3.0/lib/active_support/core_ext/benchmark.rb:17:in `ms'
/usr/local/lib/ruby/gems/1.8/gems/activesupport-2.3.0/lib/active_support/core_ext/benchmark.rb:10:in `realtime'
/usr/local/lib/ruby/gems/1.8/gems/activesupport-2.3.0/lib/active_support/core_ext/benchmark.rb:17:in `ms'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/benchmarking.rb:68:in `perform_action_without_rescue'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/rescue.rb:154:in `perform_action_without_flash'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/flash.rb:139:in `perform_action'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/base.rb:526:in `send'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/base.rb:526:in `process_without_filters'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/filters.rb:606:in `process'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/base.rb:394:in `process'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/base.rb:389:in `call'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/routing/route_set.rb:433:in `call'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/dispatcher.rb:65:in `dispatch'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/dispatcher.rb:88:in `_call'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/dispatcher.rb:59:in `initialize'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/verb_piggybacking.rb:21:in `call'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/verb_piggybacking.rb:21:in `call'
/usr/local/lib/ruby/gems/1.8/gems/rails-2.3.0/lib/rails/rack/metal.rb:32:in `call'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/session/cookie_store.rb:95:in `call'
/usr/local/lib/ruby/gems/1.8/gems/activerecord-2.3.0/lib/active_record/query_cache.rb:29:in `call'
/usr/local/lib/ruby/gems/1.8/gems/activerecord-2.3.0/lib/active_record/connection_adapters/abstract/query_cache.rb:34:in `cache'
/usr/local/lib/ruby/gems/1.8/gems/activerecord-2.3.0/lib/active_record/query_cache.rb:9:in `cache'
/usr/local/lib/ruby/gems/1.8/gems/activerecord-2.3.0/lib/active_record/query_cache.rb:28:in `call'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/failsafe.rb:11:in `call'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/lock.rb:11:in `call'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/lock.rb:11:in `synchronize'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/lock.rb:11:in `call'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-2.3.0/lib/action_controller/dispatcher.rb:83:in `call'
/usr/local/lib/ruby/gems/1.8/gems/rails-2.3.0/lib/rails/rack/static.rb:27:in `call'
/usr/local/lib/ruby/gems/1.8/gems/rails-2.3.0/lib/rails/rack/log_tailer.rb:17:in `call'
/usr/local/lib/ruby/gems/1.8/gems/rack-0.9.0/lib/rack/handler/mongrel.rb:59:in `process'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.1.5/lib/mongrel.rb:159:in `process_client'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.1.5/lib/mongrel.rb:158:in `each'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.1.5/lib/mongrel.rb:158:in `process_client'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.1.5/lib/mongrel.rb:285:in `run'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.1.5/lib/mongrel.rb:285:in `initialize'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.1.5/lib/mongrel.rb:285:in `new'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.1.5/lib/mongrel.rb:285:in `run'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.1.5/lib/mongrel.rb:268:in `initialize'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.1.5/lib/mongrel.rb:268:in `new'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.1.5/lib/mongrel.rb:268:in `run'
/usr/local/lib/ruby/gems/1.8/gems/rack-0.9.0/lib/rack/handler/mongrel.rb:32:in `run'
/usr/local/lib/ruby/gems/1.8/gems/rails-2.3.0/lib/commands/server.rb:100
/usr/local/lib/ruby/site_ruby/1.8/rubygems/custom_require.rb:31:in `gem_original_require'
/usr/local/lib/ruby/site_ruby/1.8/rubygems/custom_require.rb:31:in `require'
./script/server:3
