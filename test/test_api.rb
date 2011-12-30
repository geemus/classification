require "#{File.dirname(__FILE__)}/../secrets"
require 'test/unit'
require 'rack/test'

class SecretsTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Secrets.new
  end

  def setup
    authorize('', '25cf3e8f7e5adea77e023ffba89e203b1c0c33eb')
  end

  def test_categories
    get('/categories')
    assert_equal 200, last_response.status
    assert_equal '[]', last_response.body
  end

end
