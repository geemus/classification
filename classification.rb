require 'fog'
require 'json'
require 'sinatra/base'

require "#{File.dirname(__FILE__)}/basics"

class Classification < Sinatra::Base

  use Rack::Auth::Basic do |username, password|
    password == '25cf3e8f7e5adea77e023ffba89e203b1c0c33eb'
  end

  def ddb
    Fog::AWS::DynamoDB.new(
      :aws_access_key_id      => ENV['AWS_ACCESS_KEY_ID'],
      :aws_secret_access_key  => ENV['AWS_SECRET_ACCESS_KEY']
    )
  end

  def table_for_category(category)
    ['classification', ENV['RACK_ENV'], category].join('.')
  end

  # get a list of categories
  get('/categories') do
    data = ddb.list_tables.body['TableNames']
    status(200)
    body(data.to_json)
  end

  # categorize a set of tokens
#  post('/categories') do
#    tokens = JSON.parse(request.body.read)
#
#    status(200)
#    body(Category.match(tokens).to_json)
#  end

  # delete a category
  delete('/categories/:category') do |category|
    begin
      table = table_for_category(category)
      # request delete
      ddb.delete_table(table)
      # wait for delete to finish
      Fog.wait_for { !ddb.list_tables.include?(table) }
    rescue(Excon::Errors::BadRequest)
      # ignore errors, if for instance the table does not already exist
    end
    status(204)
  end

  # find probability of a set of tokens matching category
  # 200 - success
#  post('/categories/:category') do |category|
#    tokens = JSON.parse(request.body.read)
#
#    status(200)
#    body({category => Category[category].match(tokens)}.to_json)
#  end

  # update token counts in a category (create category if it doesn't exist)
  # 204 - tokens updated
  put('/categories/:category') do |category|
    begin
      table = table_for_category(category)
      tokens = JSON.parse(request.body.read)
      # atomically update each token's count
      tokens.each do |token, count|
        Fog::AWS[:dynamodb].update_item(
          table,
          {
            'HashKeyElement'  => { 'S' => 'geemus@gmail.com' },
            'RangeKeyElement' => { 'S' => token }
          },
          { 'count' => { 'Value' => { 'N' => count.to_s }, 'Action' => 'ADD' } }
        )
      end
      # update the total tokens in the category
      total = tokens.values.reduce(:+)
      Fog::AWS[:dynamodb].update_item(
        table,
        {
          'HashKeyElement'  => { 'S' => 'geemus@gmail.com' },
          'RangeKeyElement' => { 'S' => 'TOTAL' }
        },
        { 'count' => { 'Value' => { 'N' => total }, 'Action' => 'ADD' } }
      )
    rescue Excon::Errors::BadRequest => error
      if error.response.body['message'] == "Requested resource not found"
        # table does not exist, so create it
        ddb.create_table(
          table,
          {
            'HashKeyElement'  => { 'AttributeName' => 'user',  'AttributeType' => 'S' },
            'RangeKeyElement' => { 'AttributeName' => 'token', 'AttributeType' => 'S' }
          },
          { 'ReadCapacityUnits' => 10, 'WriteCapacityUnits' => 5 }
        )
        # wait for table to be ready
        Fog.wait_for { ddb.describe_table(table).body['Table']['TableStatus'] == 'ACTIVE' }
        # everything should now be ready to retry and add the tokens
        retry
      end
    end
    status(204)
  end

end
