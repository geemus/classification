require 'fog'
require 'json'
require 'sinatra/base'

__LIB_DIR__ = File.expand_path(File.join(File.dirname(__FILE__), 'lib'))
unless $LOAD_PATH.include?(__LIB_DIR__)
  $LOAD_PATH.unshift(__LIB_DIR__)
end

require 'classification/ddb'
require 'classification/server'

module Classification
end
