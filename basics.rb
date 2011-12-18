@categories_counts = Hash.new(0)
@tokens_counts = Hash.new {|hash,key| hash[key] = Hash.new(0)}
def tokenize(string)
  string.downcase!
  string.squeeze!(' ')
  string.gsub!(/[^a-z]\s/, ' ')

  tokens = Hash.new(0)
  string.split(' ').each do |token|
    tokens[token] += 1
  end
  tokens
end

def categorize(category, tokens)
  tokens.each do |token, count|
    @categories_counts[category] += count
    @tokens_counts[token] += count
  end
end

def probability(string, category)
  assumed_token_probability = 0.5
  probability = 1.0
  total_tokens_in_category = @categories_counts[category].to_f
  if total_tokens_in_category == 0.0
    assumed_token_probability
  else
    tokenize(string).each do |token, count|
      tokens_in_category = @tokens_counts[token][category].to_f
      token_probability = tokens_in_category / total_tokens_in_category

      total = @tokens_counts[token].values.inject(0) {|sum, count| sum + count}.to_f
      weight = 1.0

      weighted_token_probability = (total * token_probability + weight * assumed_token_probability) / (total + weight)
      count.times do
        probability *= weighted_token_probability
      end
    end
  end
  probability
end

def classify(string)
  @classifications = {}
  @categories_counts.each do |category, _|
    @classifications[category] = probability(string, category)
  end
  @classifications
end

@categories_counts['good'] = 1
@categories_counts['bad'] = 1

@tokens_counts['lorem'] = {'good' => 3, 'bad' => 1}

# bad
[
  {}
].each {|tokens| categorize('bad', tokens)

# good
[
  {}
].each {|tokens| categorize('good', tokens)

strings = [
  "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Fusce sodales consectetur purus in fermentum. Ut eu neque eu nisl aliquam ultricies. In sit amet metus id massa imperdiet euismod nec eget lacus. Praesent lacinia cursus arcu, vitae cursus velit euismod interdum. Aliquam ullamcorper ornare magna vitae vestibulum. Cras ac elit dui. Sed placerat commodo egestas. Nullam euismod iaculis sollicitudin. Quisque bibendum malesuada felis a feugiat. Nam ut justo diam, non elementum est. Ut aliquet nulla nulla. Pellentesque porttitor scelerisque vehicula.",
  "Etiam consectetur, ante id varius malesuada, tellus metus dictum leo, ac adipiscing ipsum augue ut velit. Vivamus eget neque massa. Sed sit amet purus massa. Nam vitae sem tortor. Aliquam rhoncus, mi id lacinia mollis, libero erat gravida risus, vitae laoreet libero nulla non elit. Vivamus ut quam eget est dictum condimentum a rutrum sapien. Aliquam rhoncus aliquet tellus et condimentum. Pellentesque at diam arcu, vitae vehicula neque. Pellentesque condimentum elementum accumsan. Vestibulum ut posuere velit. Pellentesque viverra magna eu dolor lobortis ut adipiscing tellus volutpat. Vivamus ut felis turpis. Aenean in turpis at metus iaculis dictum. Praesent orci quam, volutpat id commodo eget, pharetra vitae dui. Integer interdum, erat nec bibendum bibendum, eros dolor mattis nibh, vel egestas augue purus eu diam. Aliquam in sapien diam, id rhoncus turpis.",
  "Donec nunc est, dapibus eu faucibus in, pulvinar vel mi. Aliquam erat volutpat. Cras dapibus suscipit purus ac gravida. Integer vel diam id quam euismod sodales. Aliquam erat volutpat. Cras id tellus libero. Ut sit amet enim lectus.",
  "In nec dui aliquet ante luctus imperdiet. Duis ut odio ante, sed porttitor lacus. Pellentesque libero quam, venenatis sit amet facilisis eu, convallis in massa. Ut ligula lacus, scelerisque id fringilla eget, lacinia in arcu. Nullam augue velit, semper nec sodales vel, tempor a tortor. Pellentesque nec euismod orci. Proin enim felis, facilisis faucibus euismod eu, suscipit vitae lectus. Nam nec nulla convallis nulla sollicitudin ultricies eget pellentesque ante. Nulla facilisi. Nam venenatis, lectus eget pulvinar faucibus, leo lorem posuere lorem, in eleifend sem lectus sed ante. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas.",
  "Sed vestibulum imperdiet imperdiet. Praesent sed rutrum nunc. Phasellus non turpis lorem. Mauris faucibus sollicitudin dignissim. Suspendisse magna augue, tristique vel hendrerit sit amet, condimentum id ante. Praesent at turpis libero. Morbi vitae orci vel erat feugiat lobortis. Donec mollis auctor molestie. Praesent elementum mattis laoreet. Phasellus non ligula scelerisque sem viverra aliquet vel ut elit. Sed id odio non tellus pharetra vestibulum nec quis purus.",
  "http://geemus.com"
]

strings.each do |string|
  p tokenize(string)['lorem']
  p classify(string)
end
