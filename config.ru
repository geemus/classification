require 'json'
require 'sinatra/base'

require "#{File.dirname(__FILE__)}/basics"

class Secrets < Sinatra::Base

  use Rack::Auth::Basic do |username, password|
    password == '25cf3e8f7e5adea77e023ffba89e203b1c0c33eb'
  end

  # get a list of categories
  get('/categories') do
    status(200)
    body(Category.categories.keys.to_json)
  end

  # categorize a set of tokens
  post('/categories') do
    tokens = JSON.parse(request.body.read)

    status(200)
    body(Category.match(tokens).to_json)
  end

  # delete a category
  delete('/categories/:category') do |category|
    Category.delete(category)
    status(204)
  end

  # find probability of a set of tokens matching category
  # 200 - success
  post('/categories/:category') do |category|
    tokens = JSON.parse(request.body.read)

    status(200)
    body({category => Category[category].match(tokens)}.to_json)
  end

  # update token counts in a category (create category if it doesn't exist)
  # 204 - tokens updated
  put('/categories/:category') do |category|
    tokens = JSON.parse(request.body.read)
    Category[category].update(tokens)
    status(204)
  end

end

run Secrets
