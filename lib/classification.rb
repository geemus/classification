require 'fog'
require 'json'
require 'queue_classic'
require 'sinatra/base'

__LIB_DIR__ = File.expand_path(File.join(File.dirname(__FILE__)))
unless $LOAD_PATH.include?(__LIB_DIR__)
  $LOAD_PATH.unshift(__LIB_DIR__)
end

require 'classification/ddb'
require 'classification/server'

ENVIRONMENT = ENV['RACK_ENV'] || 'development'
DATABASE = "classification_{ENVIRONMENT}"
DATABASE_URL = ENV["DATABASE_URL"] || "postgres://localhost/#{DATABASE}"

module Classification; end

def QC.enqueue(function_call, *args)
  eval("#{function_call} *#{args.inspect}")
end
