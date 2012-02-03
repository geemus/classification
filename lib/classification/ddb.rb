module Classification
  class DDB

    attr_accessor :logger, :username

    def initialize(username, logger)
      @connection = Fog::AWS::DynamoDB.new(
        :aws_access_key_id      => ENV['AWS_ACCESS_KEY_ID'],
        :aws_secret_access_key  => ENV['AWS_SECRET_ACCESS_KEY']
      )
      @logger = logger
      @username = username
    end

    def get_items(table, keys)
      @connection.batch_get_item({
        table => {
          'Keys' => [*keys].map do |key|
            {
              'HashKeyElement'  => { 'S' => @username },
              'RangeKeyElement' => { 'S' => key }
            }
          end
        }
      }).body['Responses'][table]['Items']
    rescue Excon::Errors::BadRequest => error
      if error.respond_to?(:response) && error.response.body =~ /Requested resource not found/
        {}
      elsif error.respond_to?(:response) && error.response.body =~ /ProvisionedThroughputExceededException/
        logger.warn("Read capacity error for #{table}")
        sleep(1)
        retry
      else
        raise(error)
      end
    end

  end
end
