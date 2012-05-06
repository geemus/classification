module Classification
  class Server < Sinatra::Base

    enable :logging

    use Rack::Auth::Basic do |username, password|
      password == '25cf3e8f7e5adea77e023ffba89e203b1c0c33eb'
    end

    # get a list of categories
    get('/categories') do
      categories = ddb.get_categories
      status(200)
      body(categories.to_json)
    end

    # categorize a set of tokens
    post('/categories') do
      tokens = JSON.parse(request.body.read)

      categories = ddb.get_categories

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
        table = ['classification', ENV['RACK_ENV'], category].join('.')

        # request delete
        ddb.connection.delete_table(table)

        # remove category from list in TOTAL_TABLE
        ddb.connection.update_item(
          ['classification', ENV['RACK_ENV'], '__TOTAL__'].join('.'),
          {
            'HashKeyElement'  => { 'S' => env['REMOTE_USER'] },
            'RangeKeyElement' => { 'S' => '__TOTAL__' }
          },
          { '__CATEGORIES__' => { 'Value' => { 'SS' => [category] }, 'Action' => 'DELETE' } }
        )

        # wait for delete to finish
        Fog.wait_for { !ddb.connection.list_tables.body['TableNames'].include?(table) }

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
      tokens = JSON.parse(request.body.read)

      # atomically update each token's count (happens asynchronously)
      QC.enqueue("Classification::DDB.update_token_counts", env['REMOTE_USER'], category, tokens)

      status(204)
    end

    private

    def ddb
      Classification::DDB.new(
        :logger   => logger,
        :username => env['REMOTE_USER']
      )
    end

    def get_probability(category, tokens)
      token_counts = ddb.get_token_counts(category, tokens)
      category_tokens = token_counts[category]
      category_total  = token_counts['__TOTAL__']["__#{category}__"]
      total_tokens    = token_counts['__TOTAL__']

      assumed, probability, weight = 0.5, 1.0, 0.25

      if category_total == 0
        assumed
      else
        tokens.each do |token, count|
          conditional = category_tokens[token] / category_total
          weighted = ((total_tokens[token] * conditional) + (assumed * weight)) / (total_tokens[token] + weight)

          count.times do
            probability *= weighted
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

        if sum.nan?
          0.0
        else
          [sum, 1.0].min
        end
      end
    end

  end
end
