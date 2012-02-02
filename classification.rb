require 'fog'
require 'json'
require 'sinatra/base'

require "#{File.dirname(__FILE__)}/basics"

class Classification < Sinatra::Base

  TOTAL = '__TOTAL__'
  TOTAL_TABLE = ['classification', ENV['RACK_ENV'], TOTAL].join('.')

  configure :development, :test do
    enable :dump_error
  end

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
  post('/categories') do
    tokens = JSON.parse(request.body.read)

    categories_data = ddb.batch_get_item({
      TOTAL_TABLE => {
        'Keys' => [
          {
            'HashKeyElement'  => { 'S' => env['REMOTE_USER'] },
            'RangeKeyElement' => { 'S' => TOTAL }
          }
        ]
      }
    }).body

    categories = categories_data['Responses'][TOTAL_TABLE]['Items'].first['categories']['SS']

    probabilities = {}
    categories.each do |category|
      probabilities[category] = get_probability(category, tokens)
    end

    status(200)
    body(probabilities.to_json)
  end

  # delete a category
  delete('/categories/:category') do |category|
    begin
      table = table_for_category(category)

      # request delete
      ddb.delete_table(table)

      # remove category from list in TOTAL_TABLE
      ddb.update_item(
        TOTAL_TABLE,
        {
          'HashKeyElement'  => { 'S' => env['REMOTE_USER'] },
          'RangeKeyElement' => { 'S' => TOTAL }
        },
        { 'categories' => { 'Value' => { 'SS' => [table.split('.').last] }, 'Action' => 'DELETE' } }
      )

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

    probability = get_probability(category, tokens)

    status(200)
    body({category => probability}.to_json)
  end

  # update token counts in a category (create category if it doesn't exist)
  # 204 - tokens updated
  put('/categories/:category') do |category|
    table = table_for_category(category)
    tokens = JSON.parse(request.body.read)

    # update the total tokens in the category
    total = tokens.values.reduce(:+)
    increment_token_count(TOTAL_TABLE, category, total)

    # atomically update each token's count
    tokens.each do |token, count|
      increment_token_count(table, token, count)
    end

    status(204)
  end

  private

  def ddb
    Fog::AWS::DynamoDB.new(
      :aws_access_key_id      => ENV['AWS_ACCESS_KEY_ID'],
      :aws_secret_access_key  => ENV['AWS_SECRET_ACCESS_KEY']
    )
  end

  def get_probability(category, tokens)
    category_total = get_category_tokens(TOTAL_TABLE, category)[category] || 0
    # total_total == category_total currently, and should be a read for a particular token across all categories
    #total_total = get_category_tokens(TOTAL_TABLE, TOTAL)[TOTAL]

    category_tokens = get_category_tokens(table_for_category(category), tokens.keys)

    assumed = 0.5
    if category_total == 0
      probability = assumed
    else
      probability = 1.0
      tokens.each do |token, count|
        conditional = category_tokens[token] / category_total
        # TODO: total_total should represent times this token appears in all categories (ie batch get with multiple tables), not a total items count
        # TODO: in the mean time, total_total can == category_total since there is only one category
        #weighted = (total_total * conditional + assumed) / (total_total + 1)
        weighted = (category_tokens[token] * conditional + assumed) / (category_tokens[token] + 1)
        count.times do
          probability *= weighted
        end
      end
    end

    # fisher
    probability = -2.0 * Math.log(probability)

    # inv chi
    m = probability / 2.0
    sum = term = Math.exp(-m)
    1.upto(tokens.length) do |i|
      term *= m / i
      sum += term
    end

    if ENV['DEBUG_FISHER']
      p category_tokens
      p probability
      p sum
    end

    sum = 0.0 if sum.nan?
    [sum, 1.0].min
  end

  def get_category_tokens(table, tokens)
    token_data = ddb.batch_get_item({
      table => {
        'Keys' => [*tokens].map do |token|
          {
            'HashKeyElement'  => { 'S' => env['REMOTE_USER'] },
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
  rescue Excon::Errors::BadRequest => error
    if error.respond_to?(:response)
      if error.response.body =~ /Requested resource not found/
        {}
      elsif error.response.body =~ /ProvisionedThroughputExceededException/
        logger.warn("Read capacity error for #{table}")
        sleep(1)
        retry
      end
    end
  end

  def increment_token_count(table, token, value)
    begin
      ddb.update_item(
        table,
        {
          'HashKeyElement'  => { 'S' => env['REMOTE_USER'] },
          'RangeKeyElement' => { 'S' => token }
        },
        { 'count' => { 'Value' => { 'N' => value.to_s }, 'Action' => 'ADD' } }
      )
    rescue Excon::Errors::BadRequest => error
      if error.respond_to?(:response)
        if error.response.body =~ /Requested resource not found/
          # table does not exist, so create it
          ddb.create_table(
            table,
            {
              'HashKeyElement'  => { 'AttributeName' => 'user',  'AttributeType' => 'S' },
              'RangeKeyElement' => { 'AttributeName' => 'token', 'AttributeType' => 'S' }
            },
            { 'ReadCapacityUnits' => 10, 'WriteCapacityUnits' => 5 }
          )

          unless table == TOTAL_TABLE
            # add category to list in TOTAL_TABLE
            ddb.update_item(
              TOTAL_TABLE,
              {
                'HashKeyElement'  => { 'S' => env['REMOTE_USER'] },
                'RangeKeyElement' => { 'S' => TOTAL }
              },
              { 'categories' => { 'Value' => { 'SS' => [table.split('.').last] }, 'Action' => 'ADD' } }
            )
          end

          # wait for table to be ready
          Fog.wait_for { ddb.describe_table(table).body['Table']['TableStatus'] == 'ACTIVE' }

          # everything should now be ready to retry and add the tokens
          retry
        elsif error.response.body =~ /ProvisionedThroughputExceededException/
          logger.warn("Write capacity error for #{table}")
          sleep(1)
          retry
        else
          raise(error)
        end
      else
        raise(error)
      end
    end
  end

  def table_for_category(category)
    ['classification', ENV['RACK_ENV'], category].join('.')
  end

end
