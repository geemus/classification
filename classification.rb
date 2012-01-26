require 'fog'
require 'json'
require 'sinatra/base'

require "#{File.dirname(__FILE__)}/basics"

class Classification < Sinatra::Base

  TOTAL = '__TOTAL__'
  TOTAL_TABLE = ['classification', ENV['RACK_ENV'], TOTAL].join('.')

  configure :development, :test do
    enable :dump_error  end

  enable :logging

  use Rack::Auth::Basic do |username, password|
    password == '25cf3e8f7e5adea77e023ffba89e203b1c0c33eb'
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
      Fog.wait_for { !ddb.list_tables.body['TableNames'].include?(table) }
    rescue Excon::Errors::BadRequest => error
      if error.response.body =~ /Requested resource not found/
        # ignore errors, if for instance the table does not already exist
      else
        raise(error)
      end
    end
    status(204)
  end

  # find probability of a set of tokens matching category
  # 200 - success
  post('/categories/:category') do |category|
    tokens = JSON.parse(request.body.read)

    probability = get_probability(category, 'geemus@gmail.com', tokens)

    status(200)
    body({category => probability}.to_json)
  end

  # update token counts in a category (create category if it doesn't exist)
  # 204 - tokens updated
  put('/categories/:category') do |category|
    table = table_for_category(category)

    # atomically update each token's count
    tokens = JSON.parse(request.body.read)
    tokens.each do |token, count|
      increment_token_count(table, 'geemus@gmail.com', token, count)
    end

    # update the total tokens in the category
    total = tokens.values.reduce(:+)
    increment_token_count(TOTAL_TABLE, 'geemus@gmail.com', category, total)
    increment_token_count(TOTAL_TABLE, 'geemus@gmail.com', TOTAL, total)

    status(204)
  end

  private

  def ddb
    Fog::AWS::DynamoDB.new(
      :aws_access_key_id      => ENV['AWS_ACCESS_KEY_ID'],
      :aws_secret_access_key  => ENV['AWS_SECRET_ACCESS_KEY']
    )
  end

  def get_probability(category, user, tokens)
    category_total = get_category_tokens(TOTAL_TABLE, 'geemus@gmail.com', category)[category]
    total_total = get_category_tokens(TOTAL_TABLE, 'geemus@gmail.com', TOTAL)[TOTAL]

    category_tokens = get_category_tokens(table_for_category(category), 'geemus@gmail.com', tokens.keys)

    assumed = 0.5
    if category_total == 0
      probability = assumed
    else
      probability = 1.0
      tokens.each do |token, count|
        conditional = category_tokens[token] / category_total
        weighted = (total_total * conditional + assumed) / (total_total + 1)
        count.times do
          probability *= weighted
        end
      end
    end

    probability
  end

  def get_category_tokens(table, user, tokens)
    token_data = ddb.batch_get_item({
      table => {
        'Keys' => [*tokens].map do |token|
          {
            'HashKeyElement'  => { 'S' => 'geemus@gmail.com' },
            'RangeKeyElement' => { 'S' => token }
          }
        end
      }
    }).body

    category_tokens = Hash.new(0.0)
    token_data['Responses'][table]['Items'].each do |item|
      category_tokens[item['token']['S']] = item['count']['N'].to_f
    end

    category_tokens
  end

  def increment_token_count(table, user, token, value)
    begin
      ddb.update_item(
        table,
        {
          'HashKeyElement'  => { 'S' => user },
          'RangeKeyElement' => { 'S' => token }
        },
        { 'count' => { 'Value' => { 'N' => value.to_s }, 'Action' => 'ADD' } }
      )
    rescue Excon::Errors::BadRequest => error
      if error.respond_to?(:response) && error.response.body =~ /Requested resource not found/
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
      else
        raise(error)
      end
    end
  end

  def table_for_category(category)
    ['classification', ENV['RACK_ENV'], category].join('.')
  end

end