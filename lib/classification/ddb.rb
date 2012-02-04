module Classification
  class DDB

    attr_accessor :connection, :logger, :username

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
      categories_data = self.get_items('__TOTAL__' => '__META__')['__TOTAL__']
      categories = if categories_data.first && categories_data.first['__CATEGORIES__']
        categories_data.first['__CATEGORIES__']['SS']
      else
        []
      end
    end

    # gets a set of items from ddb
    # options should be in form { 'table_name' => [keys] }
    # returns { 'table_name' => [values] }
    def get_items(options)
      query, data = {}, {}
      options.each do |category, keys|
        data[category] = {}
        query[category_table(category)] = {
          'Keys' => [*keys].map do |key|
            {
              'HashKeyElement'  => { 'S' => @username },
              'RangeKeyElement' => { 'S' => key }
            }
          end
        }
      end

      query
      @connection.batch_get_item(query).body

      # flatten result
      @connection.batch_get_item(query).body['Responses'].each do |table, table_data|
        category = table.split('.').last
        data[category] = table_data['Items']
      end
      data
    rescue Excon::Errors::BadRequest => error
      if error.respond_to?(:response) && error.response.body =~ /Requested resource not found/
        data
      elsif error.respond_to?(:response) && error.response.body =~ /ProvisionedThroughputExceededException/
        @logger.warn("Read capacity error for #{category_table(category)}")
        sleep(1)
        retry
      else
        raise(error)
      end
    end

    # update a set of items in ddb
    # options should be in form { 'table_name' => { 'token' => count } }
    # returns - true?
    def update_token_counts(options)
      options.each do |category, tokens|
        # update total tokens for this category
        update_token_count(category_table('__TOTAL__'), "__#{category}__", tokens.values.reduce(:+))
        tokens.each do |token, count|
          # update token for this category
          update_token_count(category_table(category), token, count)
          # update token for all categories
          update_token_count(category_table('__TOTAL__'), token, count)
        end
      end
    end

    private

    def category_table(category)
      ['classification', ENV['RACK_ENV'], category].join('.')
    end

    def update_token_count(table, token, count)
      @connection.update_item(
        table,
        {
          'HashKeyElement'  => { 'S' => @username },
          'RangeKeyElement' => { 'S' => token }
        },
        { 'count' => { 'Value' => { 'N' => count.to_s }, 'Action' => 'ADD' } }
      )
    rescue Excon::Errors::BadRequest => error
      if error.respond_to?(:response) && error.response.body =~ /Requested resource not found/
        # table does not exist, so create it
        @connection.create_table(
          table,
          {
            'HashKeyElement'  => { 'AttributeName' => 'user',  'AttributeType' => 'S' },
            'RangeKeyElement' => { 'AttributeName' => 'token', 'AttributeType' => 'S' }
          },
          { 'ReadCapacityUnits' => 10, 'WriteCapacityUnits' => 5 }
        )

        unless table == category_table('__TOTAL__')
          # add category to list in TOTAL_TABLE
          @connection.update_item(
            category_table('__TOTAL__'),
            {
              'HashKeyElement'  => { 'S' => @username },
              'RangeKeyElement' => { 'S' => '__META__' }
            },
            { '__CATEGORIES__'=> { 'Value' => { 'SS' => [table.split('.').last] }, 'Action' => 'ADD' } }
          )
        end

        # wait for table to be ready
        Fog.wait_for { @connection.describe_table(table).body['Table']['TableStatus'] == 'ACTIVE' }

        # everything should now be ready to retry and add the tokens
        retry
      elsif error.respond_to?(:response) && error.response.body =~ /ProvisionedThroughputExceededException/
        logger.warn("Write capacity error for #{table}")
        sleep(1)
        retry
      else
        raise(error)
      end
    end

  end
end
