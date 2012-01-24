require "#{File.dirname(__FILE__)}/../classification"
require 'test/unit'
require 'rack/test'

ENV['RACK_ENV'] = 'test'

class ClassificationTests < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Classification.new
  end

  def setup
    authorize('', '25cf3e8f7e5adea77e023ffba89e203b1c0c33eb')
  end

  def test_delete_category
    put('/categories/category', {'token' => 1}.to_json)
    response = delete('/categories/category')

    assert_equal(204, response.status)
    assert_equal('', response.body)
  end

  def test_delete_noncategory
    response = delete('/categories/noncategory')

    assert_equal(204, response.status)
    assert_equal('', response.body)
  end

  def test_list_categories
    response = get('/categories')

    assert_equal(200, response.status)
    assert_equal([], JSON.parse(response.body))
  end

  def test_update_new_category
    response = put('/categories/category', {'token' => 1}.to_json)

    assert_equal(204, response.status)
    assert_equal('', response.body)

    delete('/categories/category')
  end

  def test_update_existing_category
    put('/categories/category', {'token' => 1}.to_json)
    response = put('/categories/category', {'other_token' => 1}.to_json)

    assert_equal(204, response.status)
    assert_equal('', response.body)

    delete('/categories/category')
  end

#  def test_categorize
#    put('/categories/category', {'token' => 1}.to_json)
#    response = post('/categories', {'token' => 1}.to_json)
#
#    assert_equal(200, response.status)
#    assert_equal({'category' => 0.75}, JSON.parse(response.body))
#
#    delete('/categories/category')
#  end

# def test_match
#   put('/categories/category', {'token' => 1}.to_json)
#   response = post('/categories/category', {'token' => 1}.to_json)
#
#   assert_equal(200, response.status)
#   assert_equal({'category' => 0.75}, JSON.parse(response.body))
#
#    delete('/categories/category')
#  end

end
