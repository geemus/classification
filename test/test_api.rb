ENV['RACK_ENV'] = 'test'

require './lib/classification'
require 'test/unit'
require 'rack/test'

# use QueueClassic in synchronous mode for tests
def QC.enqueue(function_call, *args)
  eval("#{function_call} *#{args.inspect}")
end

class ClassificationServerTests < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Classification::Server.new
  end

  def ddb
    Fog::AWS::DynamoDB.new(
      :aws_access_key_id      => ENV['AWS_ACCESS_KEY_ID'],
      :aws_secret_access_key  => ENV['AWS_SECRET_ACCESS_KEY']
    )
  end

  def setup
    authorize('geemus@gmail.com', '25cf3e8f7e5adea77e023ffba89e203b1c0c33eb')
  end

  def teardown
    # cleanup leftover tables, if any exist
    begin
      tables_to_delete = ddb.list_tables.body['TableNames'].select {|table| table =~ /classification\.test\..*/}
      tables_to_delete.each do |table|
        ddb.delete_table(table)
      end
      # wait for delete to finish
      Fog.wait_for { !ddb.list_tables.body['TableNames'].any? {|table| tables_to_delete.include?(table)} }
    rescue Excon::Errors::BadRequest => error
      if error.response.body =~ /Requested resource not found/
        # ignore errors, if for instance the table does not already exist
      else
        raise(error)
      end
    end
  end

  def test_delete_category
    put('/categories/category', {'token' => 1}.to_json)
    response = delete('/categories/category')

    assert_equal('', response.body)
    assert_equal(204, response.status)
  end

  def test_delete_noncategory
    response = delete('/categories/noncategory')

    assert_equal('', response.body)
    assert_equal(204, response.status)
  end

  def test_list_categories
    response = get('/categories')

    assert_equal([], JSON.parse(response.body))
    assert_equal(200, response.status)
  end

  def test_update_new_category
    response = put('/categories/category', {'token' => 1}.to_json)

    assert_equal('', response.body)
    assert_equal(204, response.status)

    delete('/categories/category')
  end

  def test_update_existing_category
    put('/categories/category', {'token' => 1}.to_json)
    response = put('/categories/category', {'other_token' => 1}.to_json)

    assert_equal('', response.body)
    assert_equal(204, response.status)

    delete('/categories/category')
  end

  def test_categorize
    put('/categories/category', {'token' => 1}.to_json)
    response = post('/categories', {'token' => 1}.to_json)

    assert_equal({'category' => 0.9948244640920437}, JSON.parse(response.body))
    assert_equal(200, response.status)

    delete('/categories/category')
  end

  def test_match
    put('/categories/category', {'token' => 1}.to_json)
    response = post('/categories/category', {'token' => 1}.to_json)

    assert_equal({'category' => 0.9948244640920437}, JSON.parse(response.body))
    assert_equal(200, response.status)

    delete('/categories/category')
  end

  def test_match_without_data
    response = post('/categories/category', {'token' => 1}.to_json)

    assert_equal({'category' => 0.8465735902799727}, JSON.parse(response.body))
    assert_equal(200, response.status)
  end

end
