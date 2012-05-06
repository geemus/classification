module Classification
  class DDB

    attr_accessor :connection, :logger, :username

    # update a set of tokens for the category corpus in ddb
    # returns - true?
    def self.update_token_counts(username, category, tokens)
      puts("DDB.update_token_counts('#{username}', '#{category}', #{tokens.inspect})")
      connection = Fog::AWS::DynamoDB.new(
        :aws_access_key_id      => ENV['AWS_ACCESS_KEY_ID'],
        :aws_secret_access_key  => ENV['AWS_SECRET_ACCESS_KEY']
      )
      # update total tokens for this category
      update_token_count(connection, username, category_table('__TOTAL__'), "__#{category}__", tokens.values.reduce(:+))
      tokens.each do |token, count|
        # update token for this category
        update_token_count(connection, username, category_table(category), token, count)
        # update token for all categories
        update_token_count(connection, username, category_table('__TOTAL__'), token, count)
      end
    end

    def initialize(options={})
      @connection = Fog::AWS::DynamoDB.new(
        :aws_access_key_id      => ENV['AWS_ACCESS_KEY_ID'],
        :aws_secret_access_key  => ENV['AWS_SECRET_ACCESS_KEY']
      )
      @logger = options[:logger]
      @username = options[:username]
    end

    # gets a list of all categories for a user
    def get_categories
      categories_data = get_items('__TOTAL__' => '__META__')['__TOTAL__']
      categories = if categories_data.first && categories_data.first['__CATEGORIES__']
        categories_data.first['__CATEGORIES__']['SS']
      else
        []
      end
    end

    # get a set of token counts for category and total from ddb
    # returns { 'token' => { '__TOTAL__' => total_count, category => category_count } }
    def get_token_counts(category, tokens)
      tokens_keys = tokens.keys
      raw_data = get_items(category => tokens_keys, '__TOTAL__' => tokens_keys + ["__#{category}__"])

      category_tokens = Hash.new(0.0)
      raw_data[category].each do |item|
        category_tokens[item['token']['S']] = item['count']['N'].to_f
      end

      total_tokens = Hash.new(0.0)
      raw_data['__TOTAL__'].each do |item|
        total_tokens[item['token']['S']] = item['count']['N'].to_f
      end

      { category => category_tokens, '__TOTAL__' => total_tokens }
    end

    private

    def self.category_table(category)
      ['classification', ENV['RACK_ENV'], category].join('.')
    end

    def self.update_token_count(connection, username, table, token, count)
      connection.update_item(
        table,
        {
          'HashKeyElement'  => { 'S' => username },
          'RangeKeyElement' => { 'S' => token }
        },
        { 'count' => { 'Value' => { 'N' => count.to_s }, 'Action' => 'ADD' } }
      )
    rescue Excon::Errors::BadRequest => error
      if error.respond_to?(:response) && error.response.body =~ /Requested resource not found/
        # table does not exist, so create it
        connection.create_table(
          table,
          {
            'HashKeyElement'  => { 'AttributeName' => 'user',  'AttributeType' => 'S' },
            'RangeKeyElement' => { 'AttributeName' => 'token', 'AttributeType' => 'S' }
          },
          { 'ReadCapacityUnits' => 10, 'WriteCapacityUnits' => 5 }
        )

        unless table == category_table('__TOTAL__')
          # add category to list in TOTAL_TABLE
          connection.update_item(
            category_table('__TOTAL__'),
            {
              'HashKeyElement'  => { 'S' => username },
              'RangeKeyElement' => { 'S' => '__META__' }
            },
            { '__CATEGORIES__'=> { 'Value' => { 'SS' => [table.split('.').last] }, 'Action' => 'ADD' } }
          )
        end

        # wait for table to be ready
        Fog.wait_for { connection.describe_table(table).body['Table']['TableStatus'] == 'ACTIVE' }

        # everything should now be ready to retry and add the tokens
        retry
      elsif error.respond_to?(:response) && error.response.body =~ /ProvisionedThroughputExceededException/
        puts("Write capacity error for #{table}")
        sleep(1)
        retry
      else
        raise(error)
      end
    end

    def category_table(category)
      self.class.category_table(category)
    end

    # gets a set of items from ddb
    # options should be in form { 'table_name' => [keys] }
    # returns { 'table_name' => [values] }
    def get_items(options)
      data, query = {}, {}, {}
      options.each do |category, keys|
        data[category] = []
        query[category_table(category)] = {
          'Keys' => [*keys].map do |key|
            {
              'HashKeyElement'  => { 'S' => @username },
              'RangeKeyElement' => { 'S' => key }
            }
          end
        }
      end

      # loop until UnproccessedKeys is empty
      all_keys_processed = false
      until all_keys_processed
        begin
          response_body = @connection.batch_get_item(query).body
          response_body['Responses'].each do |table, table_data|
            data[table.split('.').last].concat(table_data['Items'])
          end
          if response_body['UnprocessedKeys'] == {}
            all_keys_processed = true
          else
            query = response_body['UnprocessedKeys']
          end
        rescue Excon::Errors::BadRequest => error
          if error.respond_to?(:response) && error.response.body =~ /Requested resource not found/
            # table doesn't exist, we can disregard and return empty data set
            all_keys_processed = true
          elsif error.respond_to?(:response) && error.response.body =~ /ProvisionedThroughputExceededException/
            @logger.warn("Read capacity error for #{query.keys}")
            sleep(1)
            retry
          else
            raise(error)
          end
        end
      end

      data
    end

  end
end
