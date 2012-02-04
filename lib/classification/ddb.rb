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
      categories_data = self.get_items(Classification::TOTAL_TABLE => Classification::TOTAL_KEY)[Classification::TOTAL_TABLE]
      categories = if categories_data.first && categories_data.first[Classification::CATEGORIES_KEY]
        categories_data.first[Classification::CATEGORIES_KEY]['SS']
      else
        []
      end
    end

    # gets a set of items from ddb
    # options should be in form { 'table_name' => [keys] }
    # returns { 'table_name' => [values] }
    def get_items(options)
      query, data = {}, {}
      options.each do |table, keys|
        data[table] = {}
        query[table] = {
          'Keys' => [*keys].map do |key|
            {
              'HashKeyElement'  => { 'S' => @username },
              'RangeKeyElement' => { 'S' => key }
            }
          end
        }
      end

      # flatten result
      @connection.batch_get_item(query).body['Responses'].each do |table, table_data|
        data[table] = table_data['Items']
      end
      data
    rescue Excon::Errors::BadRequest => error
      if error.respond_to?(:response) && error.response.body =~ /Requested resource not found/
        data
      elsif error.respond_to?(:response) && error.response.body =~ /ProvisionedThroughputExceededException/
        @logger.warn("Read capacity error for #{table}")
        sleep(1)
        retry
      else
        raise(error)
      end
    end

    # update a set of items in ddb
    # options should be in form { 'table_name' => { 'token' => count } }
    # returns - true?
    # TODO: also update TOTAL_TABLE[token][count]
    def update_token_counts(options)
      options.each do |table, items|
        items.each do |token, count|
          begin
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

              unless table == Classification::TOTAL_TABLE
                # add category to list in TOTAL_TABLE
                @connection.update_item(
                  Classification::TOTAL_TABLE,
                  {
                    'HashKeyElement'  => { 'S' => @username },
                    'RangeKeyElement' => { 'S' => Classification::TOTAL_KEY }
                  },
                  { Classification::CATEGORIES_KEY => { 'Value' => { 'SS' => [table.split('.').last] }, 'Action' => 'ADD' } }
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
    end

  end
end
