module Classification
  class Server < Sinatra::Base

    configure :development, :test do
      enable :dump_error
    end

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
        table = table_for_category(category)

        # request delete
        ddb.connection.delete_table(table)

        # remove category from list in TOTAL_TABLE
        ddb.connection.update_item(
          Classification::TOTAL_TABLE,
          {
            'HashKeyElement'  => { 'S' => env['REMOTE_USER'] },
            'RangeKeyElement' => { 'S' => Classification::TOTAL_KEY }
          },
          { Classification::CATEGORIES_KEY => { 'Value' => { 'SS' => [table.split('.').last] }, 'Action' => 'DELETE' } }
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
      table = table_for_category(category)
      tokens = JSON.parse(request.body.read)

      # atomically update each token's count
      ddb.update_token_counts({
        Classification::TOTAL_TABLE => { category => tokens.values.reduce(:+) },
        table => tokens
      })

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
      category_total = get_category_tokens(Classification::TOTAL_TABLE, category)[category] || 0
      # TODO: should read total count for a particular token across all categories for a single user
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
      token_data = ddb.get_items(table => tokens)[table]

      category_tokens = Hash.new(0.0)
      token_data.each do |item|
        category_tokens[item['token']['S']] = item['count']['N'].to_f
      end

      category_tokens
    end

    def table_for_category(category)
      ['classification', ENV['RACK_ENV'], category].join('.')
    end

  end
end
