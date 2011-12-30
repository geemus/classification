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

  def test_list_categories
    response = get('/categories')

    assert_equal(200, response.status)
    assert_equal([], JSON.parse(response.body))
  end

  def test_update_new_category
    response = put('/categories/bad', {'foo' => 1}.to_json)

    assert_equal(204, response.status)
    assert_equal('', response.body)

    delete('/categories/bad')
  end

  def test_update_existing_category
    put('/categories/bad', {'foo' => 1}.to_json)
    response = put('/categories/bad', {'bar' => 1}.to_json)

    assert_equal(204, response.status)
    assert_equal('', response.body)

    delete('/categories/bad')
  end

  def test_delete_category
    put('/categories/bad', {'foo' => 1}.to_json)
    response = delete('/categories/bad')

    assert_equal(204, response.status)
    assert_equal('', response.body)
  end

  def test_categorize
    put('/categories/bad', {'foo' => 1}.to_json)
    response = post('/categories', {'foo' => 1}.to_json)

    assert_equal(200, response.status)
    assert_equal({'bad' => 0.75}, JSON.parse(response.body))

    delete('/categories/bad')
  end

  def test_match
    put('/categories/bad', {'foo' => 1}.to_json)
    response = post('/categories/bad', {'foo' => 1}.to_json)

    assert_equal(200, response.status)
    assert_equal({'bad' => 0.75}, JSON.parse(response.body))

    delete('/categories/bad')
  end

end
