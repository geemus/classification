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
      categories_data = self.get_items(Classification::TOTAL_TABLE => Classification::TOTAL)[Classification::TOTAL_TABLE]
      categories = if categories_data.first && categories_data.first['categories']
        categories_data.first['categories']['SS']
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

  end
end
